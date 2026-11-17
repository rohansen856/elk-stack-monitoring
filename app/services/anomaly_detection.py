"""Behavioural anomaly detection (machine learning risk scoring).

The rule-based detectors in threat_detection.py catch known patterns with fixed
thresholds (5 failed logins, 3 hosts, 100 MB). This service catches the
complement: activity that matches no rule but is unusual for this environment.

- Training: Isolation Forest over every source IP's hourly behaviour in the
  baseline window (default: the 7 days before the scoring window).
- Scoring: the same features for the most recent window; each entity gets a
  1-10 risk score calibrated against the baseline (see ml/model.py) and the
  features that deviated most, so an analyst can see *why*.

The model is trained in-process and cached; it retrains when it is older than
ML_RETRAIN_MINUTES or on demand. Training runs in a worker thread so it never
blocks the event loop. When the baseline is too small to learn from, the
service says so (status "insufficient_baseline") instead of inventing scores.
"""
import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import structlog
from elasticsearch import AsyncElasticsearch
from starlette.concurrency import run_in_threadpool

from app.config import settings
from app.services.es_client import get_elasticsearch, raise_if_detection_broken
from app.services.ml.features import FEATURE_NAMES, collect_samples
from app.services.ml.model import BehaviourModel

logger = structlog.get_logger()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AnomalyDetectionService:
    def __init__(self) -> None:
        self._model: Optional[BehaviourModel] = None
        self._trained_at: Optional[datetime] = None
        self._baseline: Dict[str, str] = {}
        self._last_status = "untrained"
        self._last_samples = 0
        self._lock = asyncio.Lock()

    @property
    def es(self) -> AsyncElasticsearch:
        return get_elasticsearch()

    # ------------------------------------------------------------------ state
    def status(self) -> Dict[str, Any]:
        return {
            "enabled": settings.ml_anomaly_enabled,
            "status": self._last_status,
            "algorithm": "isolation_forest",
            "trained_at": self._trained_at.isoformat() if self._trained_at else None,
            "training_samples": self._last_samples,
            "min_training_samples": settings.ml_min_training_samples,
            "baseline_window": self._baseline or None,
            "score_window_minutes": settings.ml_score_window_minutes,
            "features": FEATURE_NAMES,
        }

    def _is_stale(self) -> bool:
        if self._model is None or self._trained_at is None:
            return True
        return _utcnow() - self._trained_at > timedelta(minutes=settings.ml_retrain_minutes)

    async def _collect(self, start: datetime, end: datetime):
        try:
            return await collect_samples(self.es, start, end)
        except Exception as e:
            logger.error("Behaviour feature collection failed", error=str(e))
            raise_if_detection_broken(e, "Behaviour feature collection failed")
            return []

    # --------------------------------------------------------------- training
    async def train(self, force: bool = False) -> Dict[str, Any]:
        if not settings.ml_anomaly_enabled:
            self._last_status = "disabled"
            return self.status()

        async with self._lock:
            if not force and not self._is_stale():
                return self.status()

            now = _utcnow()
            end = now - timedelta(minutes=settings.ml_score_window_minutes)
            start = end - timedelta(days=settings.ml_baseline_days)
            samples = await self._collect(start, end)
            self._baseline = {"from": start.isoformat(), "to": end.isoformat()}
            self._last_samples = len(samples)

            if len(samples) < settings.ml_min_training_samples:
                # Keep any previous model rather than discarding a good one
                # because one window was quiet.
                self._last_status = "insufficient_baseline" if self._model is None else "trained"
                logger.warning(
                    "Not enough baseline behaviour to train the anomaly model",
                    samples=len(samples),
                    required=settings.ml_min_training_samples,
                )
                return self.status()

            model = BehaviourModel()
            await run_in_threadpool(model.fit, [s.vector for s in samples], [s.raw for s in samples])
            self._model, self._trained_at, self._last_status = model, now, "trained"
            logger.info("Anomaly model trained", samples=len(samples))
            return self.status()

    # ---------------------------------------------------------------- scoring
    async def detect(self, min_risk: int = 1) -> Dict[str, Any]:
        """Score the recent window. Returns the model status and the anomalies."""
        if not settings.ml_anomaly_enabled:
            self._last_status = "disabled"
            return {"model": self.status(), "anomalies": []}

        await self.train()
        if self._model is None:
            return {"model": self.status(), "anomalies": []}

        now = _utcnow()
        start = now - timedelta(minutes=settings.ml_score_window_minutes)
        # The scoring window can straddle an hour boundary; aggregate from the
        # start of that hour so the current partial bucket is complete so far.
        samples = await self._collect(start.replace(minute=0, second=0, microsecond=0), now)
        scores = await run_in_threadpool(
            self._model.score, [s.vector for s in samples], [s.raw for s in samples]
        )

        # One finding per entity: its most anomalous hour in the window.
        best: Dict[str, Dict[str, Any]] = {}
        for sample, score in zip(samples, scores):
            current = best.get(sample.entity)
            if current is not None and current["anomaly_score"] <= score.anomaly_score:
                continue
            best[sample.entity] = {
                "entity": sample.entity,
                "window_start": sample.window_start,
                "risk_score": score.risk_score,
                "anomaly_score": score.anomaly_score,
                "baseline_percentile": score.percentile,
                "deviations": [d.describe() for d in score.deviations],
                "features": {k: round(v, 3) for k, v in sample.raw.items() if not k.startswith("hour_")},
            }

        anomalies = sorted(
            (a for a in best.values() if a["risk_score"] >= min_risk),
            key=lambda a: (-a["risk_score"], a["anomaly_score"]),
        )
        return {"model": self.status(), "anomalies": anomalies}

    async def scan_threats(self) -> Dict[str, Any]:
        """Anomalies at or above ML_THREAT_MIN_RISK, shaped like rule-based threats."""
        result = await self.detect(min_risk=settings.ml_threat_min_risk)
        detected_at = _utcnow().isoformat()
        threats: List[Dict[str, Any]] = [
            {
                "threat_type": "behavioral_anomaly",
                "detector": "isolation_forest",
                "src_ip": a["entity"],
                "risk_score": a["risk_score"],
                "baseline_percentile": a["baseline_percentile"],
                "window_start": a["window_start"],
                "deviations": a["deviations"],
                "detected_at": detected_at,
            }
            for a in result["anomalies"]
        ]
        return {"model": result["model"], "threats": threats}


anomaly_detector = AnomalyDetectionService()
