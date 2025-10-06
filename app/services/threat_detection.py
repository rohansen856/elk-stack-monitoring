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

threat_detector = ThreatDetectionService()