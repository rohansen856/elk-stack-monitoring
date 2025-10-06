import smtplib  # Add this back
import requests
from email.mime.text import MIMEText
from typing import Dict, Any, List
from datetime import datetime 
import structlog

logger = structlog.get_logger()

class AlertingService:
    def __init__(self):
        pass
    
    async def send_slack_alert(self, threat: Dict[str, Any], webhook_url: str = None):
        """Send alert to Slack"""
        if not webhook_url:
            webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
            
        payload = {
            "text": f"🚨 SECURITY ALERT: {threat['threat_type'].upper()}",
            "attachments": [
                {
                    "color": "danger" if threat.get('risk_score', 0) > 7 else "warning",
                    "fields": [
                        {"title": "Threat Type", "value": threat['threat_type'], "short": True},
                        {"title": "Risk Score", "value": str(threat.get('risk_score', 'N/A')), "short": True},
                        {"title": "Source IP", "value": threat.get('src_ip', 'N/A'), "short": True},
                        {"title": "Detected At", "value": threat.get('detected_at', 'N/A'), "short": True}
                    ]
                }
            ]
        }
        
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            logger.info("Slack alert sent", threat_type=threat['threat_type'], status=response.status_code)
        except Exception as e:
            logger.error("Failed to send Slack alert", error=str(e))
    
    async def send_email_alert(self, threat: Dict[str, Any], email_to: str = "admin@company.com"):
        """Send email alert"""
        try:
            msg = MIMEText(f"""
Security Alert Detected!

Threat Type: {threat['threat_type']}
Risk Score: {threat.get('risk_score', 'N/A')}
Source IP: {threat.get('src_ip', 'N/A')}
Detected At: {threat.get('detected_at', 'N/A')}

Please investigate immediately.
            """)
            msg['Subject'] = f"🚨 Security Alert: {threat['threat_type']}"
            msg['From'] = "security@company.com"
            msg['To'] = email_to
            
            logger.info("Email alert prepared", threat_type=threat['threat_type'])
        except Exception as e:
            logger.error("Failed to send email alert", error=str(e))
    
    async def create_elasticsearch_alert(self, threat: Dict[str, Any]):
        """Store alert in Elasticsearch for tracking"""
        try:
            from app.services.threat_detection import threat_detector
            
            alert_doc = {
                "@timestamp": threat.get('detected_at'),
                "alert_type": "security_threat",
                "threat_details": threat,
                "status": "active",
                "acknowledged": False
            }
            
            threat_detector.es.index(
                index=f"security-alerts-{datetime.now().strftime('%Y.%m.%d')}",
                body=alert_doc
            )
            logger.info("Alert stored in Elasticsearch", threat_type=threat['threat_type'])
        except Exception as e:
            logger.error("Failed to store alert in Elasticsearch", error=str(e))

alerting_service = AlertingService()