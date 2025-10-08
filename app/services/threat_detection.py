from elasticsearch import Elasticsearch
from datetime import datetime, timedelta
import structlog
from typing import List, Dict, Any
from app.config import settings

logger = structlog.get_logger()

class ThreatDetectionService:
    def __init__(self):
        self.es = Elasticsearch([f"http://{settings.elasticsearch_host}:{settings.elasticsearch_port}"])
        
    async def detect_brute_force_attacks(self, time_window_minutes: int = 15) -> List[Dict]:
        """Detect multiple failed logins followed by successful login"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=time_window_minutes)
        
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                        {"terms": {"security_event.keyword": ["authentication_failure", "authentication_success"]}}
                    ]
                }
            },
            "aggs": {
                "by_src_ip": {
                    "terms": {"field": "src_ip.keyword", "size": 100},
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
            result = self.es.search(index="security-*", body=query)
            threats = []
            
            if 'aggregations' not in result or 'by_src_ip' not in result['aggregations']:
                logger.info("No aggregation data found for brute force detection")
                return threats
            
            for bucket in result['aggregations']['by_src_ip']['buckets']:
                src_ip = bucket['key']
                events = {e['key']: e['doc_count'] for e in bucket['events']['buckets']}
                
                failed_count = events.get('authentication_failure', 0)
                success_count = events.get('authentication_success', 0)
                
                # Brute force pattern: 5+ failures followed by success
                if failed_count >= 5 and success_count >= 1:
                    threats.append({
                        "threat_type": "brute_force_attack",
                        "src_ip": src_ip,
                        "failed_attempts": failed_count,
                        "successful_attempts": success_count,
                        "risk_score": min(failed_count * 2, 10),
                        "detected_at": datetime.utcnow().isoformat()
                    })
                    
            return threats
            
        except Exception as e:
            logger.error("Error in brute force detection", error=str(e))
            return []
    
    async def detect_data_exfiltration(self, threshold_mb: int = 100) -> List[Dict]:
        """Detect unusual outbound data transfer"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                        {"exists": {"field": "network.bytes_out"}}
                    ]
                }
            },
            "aggs": {
                "by_src_ip": {
                    "terms": {"field": "src_ip.keyword"},
                    "aggs": {
                        "total_bytes": {"sum": {"field": "network.bytes_out"}}
                    }
                }
            }
        }
        
        try:
            result = self.es.search(index="security-network-*", body=query)
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
                        "detected_at": datetime.utcnow().isoformat()
                    })
                    
            return threats
            
        except Exception as e:
            logger.error("Error in data exfiltration detection", error=str(e))
            return []
    
    async def detect_powershell_attacks(self) -> List[Dict]:
        """Detect suspicious PowerShell commands"""
        suspicious_patterns = [
            "Invoke-Expression", "IEX", "DownloadString", "EncodedCommand",
            "PowerShell.exe -enc", "bypass", "hidden", "noprofile"
        ]
        
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        threats = []
        
        try:
            for pattern in suspicious_patterns:
                query = {
                    "query": {
                        "bool": {
                            "must": [
                                {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                                {"wildcard": {"message": f"*{pattern}*"}},
                                {"match": {"log_category": "powershell_execution"}}
                            ]
                        }
                    }
                }
                
                result = self.es.search(index="security-*", body=query)
                
                # Check if hits exist
                if result.get('hits', {}).get('total', {}).get('value', 0) > 0:
                    threats.append({
                        "threat_type": "suspicious_powershell",
                        "pattern": pattern,
                        "occurrences": result['hits']['total']['value'],
                        "risk_score": 7,
                        "detected_at": datetime.utcnow().isoformat()
                    })
                    
            return threats
            
        except Exception as e:
            logger.error("Error in PowerShell attack detection", error=str(e))
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
                    "detected_at": datetime.utcnow().isoformat()
                })
                
            return correlated_threats
            
        except Exception as e:
            logger.error("Error in APT correlation", error=str(e))
            return []
    
    async def hunt_ecs_powershell_external(self) -> List[Dict]:
        """Hunt for PowerShell execution from external IPs (ECS format)"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        # The exact query you mentioned
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                        {"term": {"event.action.keyword": "process_start"}},
                        {"wildcard": {"process.command_line": "*powershell*"}}
                    ],
                    "must_not": [
                        {"range": {"source.ip": {"gte": "10.0.0.0", "lte": "10.255.255.255"}}},
                        {"range": {"source.ip": {"gte": "192.168.0.0", "lte": "192.168.255.255"}}},
                        {"range": {"source.ip": {"gte": "172.16.0.0", "lte": "172.31.255.255"}}}
                    ]
                }
            },
            "aggs": {
                "by_host": {
                    "terms": {"field": "host.name.keyword"},
                    "aggs": {
                        "by_source_ip": {
                            "terms": {"field": "source.ip.keyword"}
                        },
                        "by_user": {
                            "terms": {"field": "user.name.keyword"}
                        }
                    }
                }
            }
        }
        
        try:
            result = self.es.search(index="security-*", body=query)
            threats = []
            
            if result['hits']['total']['value'] > 0:
                threats.append({
                    "threat_type": "ecs_external_powershell",
                    "description": "PowerShell execution from external IP detected",
                    "events_count": result['hits']['total']['value'],
                    "query_used": "event.action:process_start AND process.command_line:*powershell* AND source.ip:!10.0.0.0/8",
                    "affected_hosts": len(result.get('aggregations', {}).get('by_host', {}).get('buckets', [])),
                    "risk_score": 9,
                    "detected_at": datetime.utcnow().isoformat()
                })
            
            return threats
        except Exception as e:
            logger.error("Error in ECS PowerShell hunting", error=str(e))
            return []

    async def hunt_apt_kill_chain_ecs(self) -> List[Dict]:
        """Hunt for complete APT kill chain using ECS"""
        
        # Step 1: Find PowerShell execution (already implemented)
        powershell_threats = await self.hunt_ecs_powershell_external()
        
        # Step 2: Find C2 traffic
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        c2_query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                        {"term": {"event.action.keyword": "network_connection"}},
                        {"range": {"network.bytes": {"gte": 1024}}},
                        {"term": {"network.direction.keyword": "outbound"}}
                    ],
                    "must_not": [
                        {"terms": {"destination.ip.keyword": ["127.0.0.1", "::1"]}},
                        {"range": {"destination.ip": {"gte": "10.0.0.0", "lte": "10.255.255.255"}}}
                    ]
                }
            }
        }
        
        try:
            c2_result = self.es.search(index="security-*", body=c2_query)
            
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
                    "detected_at": datetime.utcnow().isoformat()
                }]
            
            return []
        except Exception as e:
            logger.error("Error in APT kill chain hunting", error=str(e))
            return []

    async def hunt_lateral_movement_ecs(self) -> List[Dict]:
        """Hunt for lateral movement using ECS"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=2)
        
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}},
                        {"term": {"event.action.keyword": "authentication_success"}},
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
            result = self.es.search(index="security-*", body=query)
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
                            "hunt_query": "event.action:authentication_success AND logon.type:3",
                            "risk_score": min(unique_hosts * 2, 10),
                            "detected_at": datetime.utcnow().isoformat()
                        })
            
            return threats
        except Exception as e:
            logger.error("Error in lateral movement hunting", error=str(e))
            return []

    async def hunt_privilege_escalation_ecs(self) -> List[Dict]:
        """Hunt for privilege escalation using ECS"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        query = {
            "query": {
                "bool": {
                    "must": [
                        {"range": {"@timestamp": {"gte": start_time, "lte": end_time}}}
                    ],
                    "should": [
                        {"wildcard": {"process.command_line": "*runas*"}},
                        {"wildcard": {"process.command_line": "*sudo*"}},
                        {"term": {"event.action.keyword": "privilege_use"}},
                        {"term": {"winlog.event_id": "4672"}}  # Windows special privileges
                    ]
                }
            }
        }
        
        try:
            result = self.es.search(index="security-*", body=query)
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
                        "hunt_query": "process.command_line:*runas* OR process.command_line:*sudo*",
                        "risk_score": 8,
                        "detected_at": datetime.utcnow().isoformat()
                    })
            
            return threats
        except Exception as e:
            logger.error("Error in privilege escalation hunting", error=str(e))
            return []

threat_detector = ThreatDetectionService()