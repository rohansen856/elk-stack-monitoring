"""Outbound security alerting.

Previously this posted to a hardcoded placeholder webhook
(``https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK``) because no caller ever
supplied one and ``SLACK_WEBHOOK_URL`` from the environment was never read by
any Python code. Failures were swallowed, so alerts silently reached nobody
while the documentation claimed multi-channel alerting was operational.
See AUDIT ALERT-001.
"""
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import httpx
import structlog

from app.config import settings
from app.services.es_client import get_elasticsearch

logger = structlog.get_logger()

HTTP_TIMEOUT_SECONDS = 10


class AlertingService:
    def __init__(self) -> None:
        self._warned_no_webhook = False

    def _resolve_webhook(self, webhook_url: Optional[str]) -> Optional[str]:
        url = webhook_url or settings.slack_webhook_url
        if not url:
            # Warn once, loudly, instead of posting into the void.
            if not self._warned_no_webhook:
                logger.warning(
                    "SLACK_WEBHOOK_URL is not configured; Slack alerting is disabled. "
                    "Security alerts will NOT be delivered."
                )
                self._warned_no_webhook = True
            return None
        return url

    async def send_slack_alert(
        self, threat: Dict[str, Any], webhook_url: Optional[str] = None
    ) -> bool:
        """Post a threat to Slack. Returns True only if Slack accepted it."""
        url = self._resolve_webhook(webhook_url)
        if url is None:
            return False

        # .get() throughout: threat dicts are assembled by several detectors and
        # a missing key previously raised KeyError inside a background task.
        threat_type = threat.get("threat_type", "unknown")
        risk_score = threat.get("risk_score", "N/A")

        payload = {
            "text": f"\U0001f6a8 SECURITY ALERT: {str(threat_type).upper()}",
            "attachments": [
                {
                    "color": "danger" if _as_number(risk_score) > 7 else "warning",
                    "fields": [
                        {"title": "Threat Type", "value": str(threat_type), "short": True},
                        {"title": "Risk Score", "value": str(risk_score), "short": True},
                        {"title": "Source IP", "value": str(threat.get("src_ip", "N/A")), "short": True},
                        {"title": "Detected At", "value": str(threat.get("detected_at", "N/A")), "short": True},
                    ],
                }
            ],
        }

        try:
            async with httpx.AsyncClient(timeout=HTTP_TIMEOUT_SECONDS) as client:
                response = await client.post(url, json=payload)
            if response.status_code >= 400:
                logger.error(
                    "Slack rejected the alert",
                    threat_type=threat_type,
                    status=response.status_code,
                )
                return False
            logger.info("Slack alert sent", threat_type=threat_type, status=response.status_code)
            return True
        except Exception as e:
            logger.error("Failed to send Slack alert", threat_type=threat_type, error=str(e))
            return False

    async def create_elasticsearch_alert(self, threat: Dict[str, Any]) -> bool:
        """Record the alert in Elasticsearch for dashboards and retention."""
        doc = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "alert_type": "security_threat",
            "threat": threat,
            "risk_score": threat.get("risk_score"),
            "threat_type": threat.get("threat_type", "unknown"),
        }
        index = f"security-alerts-{datetime.now(timezone.utc).strftime('%Y.%m.%d')}"
        try:
            # Uses the shared authenticated client rather than reaching into
            # another service's private attribute.
            get_elasticsearch().index(index=index, body=doc)
            return True
        except Exception as e:
            logger.error("Failed to record alert in Elasticsearch", error=str(e))
            return False


def _as_number(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


alerting_service = AlertingService()
