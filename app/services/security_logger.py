from elasticsearch import Elasticsearch
from datetime import datetime
import structlog
import json
from typing import Dict, Any, Optional
from app.config import settings
import socket

logger = structlog.get_logger()

class SecurityLogger:
    def __init__(self):
        self.es = Elasticsearch([f"http://{settings.elasticsearch_host}:{settings.elasticsearch_port}"])
        self.hostname = socket.gethostname()
        self.service_name = "threat-detection-api"

    async def log_authentication_event(self,
                                     event_type: str,
                                     email: str,
                                     user_id: Optional[str] = None,
                                     source_ip: Optional[str] = None,
                                     user_agent: Optional[str] = None,
                                     additional_data: Optional[Dict[str, Any]] = None):
        """Log authentication events to Elasticsearch"""

        timestamp = datetime.utcnow()

        # Create ECS-compliant security event
        event_doc = {
            "@timestamp": timestamp.isoformat(),
            "event": {
                "action": event_type,
                "category": ["authentication"],
                "type": ["info"],
                "outcome": "success" if "success" in event_type else "failure",
                "dataset": "security.authentication"
            },
            "user": {
                "email": email,
                "id": user_id
            },
            "source": {
                "ip": source_ip or "127.0.0.1"
            },
            "user_agent": {
                "original": user_agent or "unknown"
            },
            "host": {
                "name": self.hostname
            },
            "service": {
                "name": self.service_name
            },
            "security_event": event_type,
            "src_ip": source_ip or "127.0.0.1",
            "message": f"{event_type}: {email}",
            "log_category": "authentication",
            "ecs": {
                "version": "8.0.0"
            }
        }

        if additional_data:
            event_doc.update(additional_data)

        try:
            # Index to security-auth-logs with date-based index
            index_name = f"security-auth-logs-{timestamp.strftime('%Y.%m.%d')}"

            result = self.es.index(
                index=index_name,
                body=event_doc
            )

            logger.info("Security event logged",
                       event_type=event_type,
                       email=email,
                       index=index_name,
                       document_id=result.get('_id'))

        except Exception as e:
            logger.error("Failed to log security event",
                        error=str(e),
                        event_type=event_type,
                        email=email)

    async def log_api_access_event(self,
                                 endpoint: str,
                                 method: str,
                                 status_code: int,
                                 user_email: Optional[str] = None,
                                 source_ip: Optional[str] = None,
                                 response_size: Optional[int] = None,
                                 additional_data: Optional[Dict[str, Any]] = None):
        """Log API access events for detecting reconnaissance and data exfiltration"""

        timestamp = datetime.utcnow()

        # Determine event outcome
        outcome = "success" if 200 <= status_code < 400 else "failure"

        event_doc = {
            "@timestamp": timestamp.isoformat(),
            "event": {
                "action": "api_access",
                "category": ["network"],
                "type": ["access"],
                "outcome": outcome,
                "dataset": "security.api"
            },
            "http": {
                "request": {
                    "method": method
                },
                "response": {
                    "status_code": status_code
                }
            },
            "url": {
                "path": endpoint
            },
            "user": {
                "email": user_email
            },
            "source": {
                "ip": source_ip or "127.0.0.1"
            },
            "network": {
                "bytes_out": response_size or 0
            },
            "host": {
                "name": self.hostname
            },
            "service": {
                "name": self.service_name
            },
            "src_ip": source_ip or "127.0.0.1",
            "message": f"API {method} {endpoint} - {status_code}",
            "log_category": "api_access",
            "ecs": {
                "version": "8.0.0"
            }
        }

        if additional_data:
            event_doc.update(additional_data)

        try:
            # Index to security-api-logs with date-based index
            index_name = f"security-api-logs-{timestamp.strftime('%Y.%m.%d')}"

            result = self.es.index(
                index=index_name,
                body=event_doc
            )

        except Exception as e:
            logger.error("Failed to log API access event",
                        error=str(e),
                        endpoint=endpoint,
                        method=method)

    async def log_powershell_event(self,
                                  command: str,
                                  user: str,
                                  host: str,
                                  process_id: int,
                                  source_ip: Optional[str] = None):
        """Log PowerShell execution events"""

        timestamp = datetime.utcnow()

        event_doc = {
            "@timestamp": timestamp.isoformat(),
            "event": {
                "action": "process_start",
                "category": ["process"],
                "type": ["start"],
                "outcome": "success",
                "dataset": "security.powershell"
            },
            "process": {
                "name": "powershell.exe",
                "command_line": command,
                "pid": process_id
            },
            "user": {
                "name": user
            },
            "host": {
                "name": host
            },
            "source": {
                "ip": source_ip or "127.0.0.1"
            },
            "service": {
                "name": self.service_name
            },
            "message": f"PowerShell execution: {command}",
            "log_category": "powershell_execution",
            "ecs": {
                "version": "8.0.0"
            }
        }

        try:
            index_name = f"security-powershell-logs-{timestamp.strftime('%Y.%m.%d')}"

            result = self.es.index(
                index=index_name,
                body=event_doc
            )

            logger.info("PowerShell event logged",
                       command=command[:100],
                       user=user,
                       index=index_name)

        except Exception as e:
            logger.error("Failed to log PowerShell event",
                        error=str(e),
                        command=command[:100])

    async def log_network_event(self,
                               event_type: str,
                               source_ip: str,
                               destination_ip: str,
                               bytes_transferred: int,
                               direction: str = "outbound",
                               additional_data: Optional[Dict[str, Any]] = None):
        """Log network events for data exfiltration detection"""

        timestamp = datetime.utcnow()

        event_doc = {
            "@timestamp": timestamp.isoformat(),
            "event": {
                "action": "network_connection",
                "category": ["network"],
                "type": ["connection"],
                "outcome": "success",
                "dataset": "security.network"
            },
            "source": {
                "ip": source_ip
            },
            "destination": {
                "ip": destination_ip
            },
            "network": {
                "bytes": bytes_transferred,
                "bytes_out": bytes_transferred if direction == "outbound" else 0,
                "direction": direction
            },
            "host": {
                "name": self.hostname
            },
            "service": {
                "name": self.service_name
            },
            "src_ip": source_ip,
            "message": f"Network {event_type}: {source_ip} -> {destination_ip} ({bytes_transferred} bytes)",
            "log_category": "network_traffic",
            "ecs": {
                "version": "8.0.0"
            }
        }

        if additional_data:
            event_doc.update(additional_data)

        try:
            index_name = f"security-network-logs-{timestamp.strftime('%Y.%m.%d')}"

            result = self.es.index(
                index=index_name,
                body=event_doc
            )

        except Exception as e:
            logger.error("Failed to log network event",
                        error=str(e),
                        event_type=event_type)

# Global instance
security_logger = SecurityLogger()