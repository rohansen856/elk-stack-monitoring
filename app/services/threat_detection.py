from datetime import datetime, timedelta, timezone
import structlog
from typing import Dict, List
from elasticsearch import AsyncElasticsearch
from app.services.es_client import (
    get_elasticsearch,
    raise_if_detection_broken,
)

logger = structlog.get_logger()

# Raw security events. Excludes the derived indices that hold copies of
# events (threat-intel enrichment output) and our own alerts, which otherwise
# matched `security-*` and were counted a second time by every detector.
EVENT_INDICES = "security-*,-security-threats-*,-security-alerts-*"
NETWORK_INDICES = "security-network-*"

# Non-routable source ranges. These queries need source.ip/destination.ip to be
# mapped as `ip` (see the sentinel-security-events template created by the
# setup-elk service). Previously they were dynamic text fields, so `range`
# compared strings lexicographically: 10.3.0.1 sorted outside "10.0.0.0" -
# "10.255.255.255", and 127.0.0.1 counted as external.
PRIVATE_AND_LOOPBACK = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "127.0.0.0/8",
    "::1/128",
    "fc00::/7",
]

# Event actions as written by the application's security logger and by the
# Logstash parsers, which name the same thing differently.
ACTIONS_PROCESS_START = ["process_start", "process_created"]
ACTIONS_LOGON_SUCCESS = ["authentication_success", "successful_logon"]
ACTIONS_PRIVILEGE = ["privilege_use", "privilege_escalation"]


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _time_range(delta: timedelta) -> Dict:
    end_time = _utcnow()
    return {"range": {"@timestamp": {"gte": end_time - delta, "lte": end_time}}}


def _contains_ci(field: str, needle: str) -> Dict:
    return {"wildcard": {field: {"value": f"*{needle}*", "case_insensitive": True}}}


class ThreatDetectionService:
    @property
    def es(self) -> AsyncElasticsearch:
        # Resolved on every use rather than captured at import: the shared
        # client is closed and rebuilt across application lifespans, and a
        # captured reference kept pointing at the closed one.
        return get_elasticsearch()

    async def detect_brute_force_attacks(self, time_window_minutes: int = 15) -> List[Dict]:
        """Detect multiple failed logins followed by successful login"""
        query = {
            "size": 0,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(timedelta(minutes=time_window_minutes)),
                        {"terms": {"security_event.keyword": ["authentication_failure", "authentication_success"]}},
                    ]
                }
            },
            "aggs": {
                "by_src_ip": {
                    "terms": {"field": "src_ip", "size": 100},
                    "aggs": {
                        "events": {
                            "terms": {"field": "security_event.keyword"},
                            "aggs": {"latest": {"max": {"field": "@timestamp"}}}
                        }
                    }
                }
            }
        }

        try:
            result = await self.es.search(index=EVENT_INDICES, body=query)
            threats = []

            if 'aggregations' not in result or 'by_src_ip' not in result['aggregations']:
                logger.info("No aggregation data found for brute force detection")
                return threats

            for bucket in result['aggregations']['by_src_ip']['buckets']:
                src_ip = bucket['key']
                events = {e['key']: e['doc_count'] for e in bucket['events']['buckets']}

                failed_count = events.get('authentication_failure', 0)
                success_count = events.get('authentication_success', 0)

                # Brute force patterns:
                # 1. Multiple failures (5+ failures = suspicious)
                # 2. Multiple failures followed by success (more dangerous)
                if failed_count >= 5:
                    risk_score = min(failed_count, 10)
                    if success_count >= 1:
                        risk_score = min(failed_count * 2, 10)  # Higher score if successful

                    threats.append({
                        "threat_type": "brute_force_attack",
                        "src_ip": src_ip,
                        "failed_attempts": failed_count,
                        "successful_attempts": success_count,
                        "risk_score": risk_score,
                        "attack_pattern": "successful_brute_force" if success_count > 0 else "failed_brute_force",
                        "detected_at": _utcnow().isoformat()
                    })

            return threats

        except Exception as e:
            logger.error("Error in brute force detection", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in brute force detection")
            return []

    async def detect_data_exfiltration(self, threshold_mb: int = 100) -> List[Dict]:
        """Detect unusual outbound data transfer"""
        query = {
            "size": 0,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(timedelta(hours=1)),
                        {"exists": {"field": "network.bytes_out"}}
                    ]
                }
            },
            "aggs": {
                "by_src_ip": {
                    "terms": {"field": "src_ip", "size": 100},
                    "aggs": {
                        "total_bytes": {"sum": {"field": "network.bytes_out"}}
                    }
                }
            }
        }

        try:
            result = await self.es.search(index=NETWORK_INDICES, body=query)
            threats = []

            if 'aggregations' not in result or 'by_src_ip' not in result['aggregations']:
                logger.info("No network data found for data exfiltration detection")
                return threats

            threshold_bytes = threshold_mb * 1024 * 1024
            for bucket in result['aggregations']['by_src_ip']['buckets']:
                total_bytes = bucket['total_bytes']['value']
                if total_bytes > threshold_bytes:
                    threats.append({
                        "threat_type": "data_exfiltration",
                        "src_ip": bucket['key'],
                        "bytes_transferred": total_bytes,
                        "mb_transferred": round(total_bytes / (1024 * 1024), 2),
                        "risk_score": min(int(total_bytes / threshold_bytes * 5), 10),
                        "detected_at": _utcnow().isoformat()
                    })

            return threats

        except Exception as e:
            logger.error("Error in data exfiltration detection", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in data exfiltration detection")
            return []

    @staticmethod
    def _powershell_pattern_query(pattern: str, start_delta: timedelta) -> Dict:
        """Phrase-match a PowerShell indicator in any field that carries a command.

        Previously this was a case-sensitive `wildcard` on the analysed
        `message` text field. Its tokens are lowercased, so any pattern with an
        uppercase letter, hyphen or space ("Invoke-Expression", "IEX",
        "DownloadString", "EncodedCommand", "PowerShell.exe -enc") could never
        match; only "bypass", "hidden" and "noprofile" ever fired. A phrase
        match is case-insensitive and, unlike `*IEX*`, does not fire on words
        that merely contain the letters (e.g. "index").
        """
        return {
            "size": 0,
            "track_total_hits": True,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(start_delta),
                        {
                            "bool": {
                                "should": [
                                    {"term": {"log_category.keyword": "powershell_execution"}},
                                    {"terms": {"event.action.keyword": ACTIONS_PROCESS_START}},
                                ],
                                "minimum_should_match": 1,
                            }
                        },
                    ],
                    "should": [
                        {"match_phrase": {"message": pattern}},
                        {"match_phrase": {"process.command_line": pattern}},
                        {"match_phrase": {"event_message": pattern}},
                    ],
                    "minimum_should_match": 1,
                }
            },
        }

    async def detect_powershell_attacks(self) -> List[Dict]:
        """Detect suspicious PowerShell commands"""
        suspicious_patterns = [
            "Invoke-Expression", "IEX", "DownloadString", "EncodedCommand",
            "PowerShell.exe -enc", "bypass", "hidden", "noprofile"
        ]

        threats = []

        try:
            for pattern in suspicious_patterns:
                query = self._powershell_pattern_query(pattern, timedelta(hours=24))
                result = await self.es.search(index=EVENT_INDICES, body=query)

                # Check if hits exist
                if result.get('hits', {}).get('total', {}).get('value', 0) > 0:
                    threats.append({
                        "threat_type": "suspicious_powershell",
                        "pattern": pattern,
                        "occurrences": result['hits']['total']['value'],
                        "risk_score": 7,
                        "detected_at": _utcnow().isoformat()
                    })

            return threats

        except Exception as e:
            logger.error("Error in PowerShell attack detection", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in PowerShell attack detection")
            return []

    async def correlate_apt_indicators(self) -> List[Dict]:
        """Cross-system correlation for APT detection"""
        try:
            powershell_threats = await self.detect_powershell_attacks()

            network_threats = await self.detect_data_exfiltration(threshold_mb=50)

            correlated_threats = []

            if powershell_threats and network_threats:
                correlated_threats.append({
                    "threat_type": "apt_killchain",
                    "stage": "execution_and_exfiltration",
                    "powershell_indicators": len(powershell_threats),
                    "network_indicators": len(network_threats),
                    "risk_score": 9,
                    "description": "Detected PowerShell execution followed by data exfiltration",
                    "detected_at": _utcnow().isoformat()
                })

            return correlated_threats

        except Exception as e:
            logger.error("Error in APT correlation", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in APT correlation")
            return []

    async def hunt_ecs_powershell_external(self) -> List[Dict]:
        """Hunt for PowerShell execution from external IPs (ECS format)"""
        query = {
            "size": 0,
            "track_total_hits": True,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(timedelta(hours=24)),
                        {"terms": {"event.action.keyword": ACTIONS_PROCESS_START}},
                        # An event without a source address is not evidence of
                        # an external origin.
                        {"exists": {"field": "source.ip"}},
                    ],
                    "should": [
                        _contains_ci("process.command_line", "powershell"),
                        _contains_ci("process.name", "powershell"),
                        {"match_phrase": {"event_message": "powershell"}},
                    ],
                    "minimum_should_match": 1,
                    "must_not": [
                        {"terms": {"source.ip": PRIVATE_AND_LOOPBACK}},
                    ]
                }
            },
            "aggs": {
                "by_host": {
                    "terms": {"field": "host.name.keyword"},
                    "aggs": {
                        "by_source_ip": {
                            "terms": {"field": "source.ip"}
                        },
                        "by_user": {
                            "terms": {"field": "user.name.keyword"}
                        }
                    }
                }
            }
        }

        try:
            result = await self.es.search(index=EVENT_INDICES, body=query)
            threats = []

            if result['hits']['total']['value'] > 0:
                threats.append({
                    "threat_type": "ecs_external_powershell",
                    "description": "PowerShell execution from external IP detected",
                    "events_count": result['hits']['total']['value'],
                    "query_used": "event.action:(process_start OR process_created) AND process.command_line:*powershell* AND NOT source.ip:(private OR loopback)",
                    "affected_hosts": len(result.get('aggregations', {}).get('by_host', {}).get('buckets', [])),
                    "risk_score": 9,
                    "detected_at": _utcnow().isoformat()
                })

            return threats
        except Exception as e:
            logger.error("Error in ECS PowerShell hunting", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in ECS PowerShell hunting")
            return []

    async def hunt_apt_kill_chain_ecs(self) -> List[Dict]:
        """Hunt for complete APT kill chain using ECS"""

        # Step 1: Find PowerShell execution (already implemented)
        powershell_threats = await self.hunt_ecs_powershell_external()

        # Step 2: Find C2 traffic
        c2_query = {
            "size": 0,
            "track_total_hits": True,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(timedelta(hours=24)),
                        {"term": {"event.action.keyword": "network_connection"}},
                        {"range": {"network.bytes": {"gte": 1024}}},
                        {"term": {"network.direction.keyword": "outbound"}}
                    ],
                    "must_not": [
                        {"terms": {"destination.ip": PRIVATE_AND_LOOPBACK}},
                    ]
                }
            }
        }

        try:
            c2_result = await self.es.search(index=EVENT_INDICES, body=c2_query)

            # Correlate across both
            if (powershell_threats and
                c2_result['hits']['total']['value'] > 0):

                return [{
                    "threat_type": "apt_kill_chain_complete",
                    "stages": ["execution", "command_and_control"],
                    "powershell_events": len(powershell_threats),
                    "c2_connections": c2_result['hits']['total']['value'],
                    "description": "Complete APT kill chain detected: PowerShell execution + C2 traffic",
                    "risk_score": 10,
                    "detected_at": _utcnow().isoformat()
                }]

            return []
        except Exception as e:
            logger.error("Error in APT kill chain hunting", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in APT kill chain hunting")
            return []

    async def hunt_lateral_movement_ecs(self) -> List[Dict]:
        """Hunt for lateral movement using ECS"""
        query = {
            "size": 0,
            "query": {
                "bool": {
                    "filter": [
                        _time_range(timedelta(hours=2)),
                        {"terms": {"event.action.keyword": ACTIONS_LOGON_SUCCESS}},
                        {"term": {"logon.type": "3"}}  # Network logon
                    ]
                }
            },
            "aggs": {
                "by_user": {
                    "terms": {"field": "user.name.keyword"},
                    "aggs": {
                        "unique_hosts": {
                            "cardinality": {"field": "host.name.keyword"}
                        },
                        "hosts_accessed": {
                            "terms": {"field": "host.name.keyword", "size": 20}
                        }
                    }
                }
            }
        }

        try:
            result = await self.es.search(index=EVENT_INDICES, body=query)
            threats = []

            if 'aggregations' in result:
                for bucket in result['aggregations']['by_user']['buckets']:
                    user = bucket['key']
                    unique_hosts = bucket['unique_hosts']['value']

                    # Lateral movement: user accessing 3+ different hosts
                    if unique_hosts >= 3:
                        hosts = [h['key'] for h in bucket['hosts_accessed']['buckets']]
                        threats.append({
                            "threat_type": "lateral_movement",
                            "user": user,
                            "unique_hosts_accessed": unique_hosts,
                            "hosts": hosts,
                            "hunt_query": "event.action:(authentication_success OR successful_logon) AND logon.type:3",
                            "risk_score": min(unique_hosts * 2, 10),
                            "detected_at": _utcnow().isoformat()
                        })

            return threats
        except Exception as e:
            logger.error("Error in lateral movement hunting", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in lateral movement hunting")
            return []

    @staticmethod
    def _privilege_escalation_query() -> Dict:
        return {
            "size": 500,
            "sort": [{"@timestamp": {"order": "desc"}}],
            "query": {
                "bool": {
                    "filter": [_time_range(timedelta(hours=1))],
                    "should": [
                        _contains_ci("process.command_line", "runas"),
                        _contains_ci("process.command_line", "sudo"),
                        {"terms": {"event.action.keyword": ACTIONS_PRIVILEGE}},
                        {"term": {"winlog.event_id": "4672"}},  # Windows special privileges (Winlogbeat)
                        {"term": {"event.id": "4672"}},         # same, parsed from syslog by Logstash
                    ],
                    # Without this the `should` clauses were optional, so the
                    # hunt returned up to 500 arbitrary events from the last
                    # hour, each reported as privilege escalation with risk 8.
                    "minimum_should_match": 1,
                }
            },
        }

    async def hunt_privilege_escalation_ecs(self) -> List[Dict]:
        """Hunt for privilege escalation using ECS"""
        query = self._privilege_escalation_query()

        try:
            result = await self.es.search(index=EVENT_INDICES, body=query)
            threats = []

            if result['hits']['total']['value'] > 0:
                for hit in result['hits']['hits']:
                    source = hit['_source']
                    threats.append({
                        "threat_type": "privilege_escalation",
                        "user": source.get('user', {}).get('name', 'unknown'),
                        "process": source.get('process', {}).get('name', 'unknown'),
                        "command_line": source.get('process', {}).get('command_line', ''),
                        "host": source.get('host', {}).get('name', 'unknown'),
                        "hunt_query": "process.command_line:(*runas* OR *sudo*) OR event.action:(privilege_use OR privilege_escalation) OR event_id:4672",
                        "risk_score": 8,
                        "detected_at": _utcnow().isoformat()
                    })

            return threats
        except Exception as e:
            logger.error("Error in privilege escalation hunting", error=str(e))
            # Raises for connection/auth failures so a broken detector is
            # never reported as 'no threats'; returns for a missing index,
            # which legitimately means nothing has been ingested yet.
            raise_if_detection_broken(e, "Error in privilege escalation hunting")
            return []

threat_detector = ThreatDetectionService()
