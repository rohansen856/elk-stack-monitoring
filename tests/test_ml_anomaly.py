"""Tests for the behavioural anomaly model (Isolation Forest risk scoring)."""
import asyncio
import random
from datetime import datetime, timedelta, timezone

import pytest

from app.services import anomaly_detection
from app.services.anomaly_detection import AnomalyDetectionService
from app.services.ml.features import FEATURE_NAMES, sample_from_bucket
from app.services.ml.model import BehaviourModel, risk_from_percentile

HOUR_MS = 3600 * 1000
BASE_TS = int(datetime(2026, 11, 10, tzinfo=timezone.utc).timestamp() * 1000)


def bucket(ip, hour_index, events, failures=0, successes=0, users=1, hosts=1,
           destinations=1, bytes_out=0, process=0, privilege=0, max_risk=None):
    """A composite-aggregation bucket as Elasticsearch returns it."""
    return {
        "key": {"entity": ip, "hour": BASE_TS + hour_index * HOUR_MS},
        "doc_count": events,
        "failures": {"doc_count": failures},
        "successes": {"doc_count": successes},
        "users": {"value": users},
        "emails": {"value": 0},
        "hosts": {"value": hosts},
        "destinations": {"value": destinations},
        "bytes_out": {"value": bytes_out},
        "process": {"doc_count": process},
        "privilege": {"doc_count": privilege},
        "max_risk": {"value": max_risk},
    }


def normal_samples(n=400, seed=7):
    """Ordinary office traffic: a few logins, small transfers, working hours."""
    rng = random.Random(seed)
    out = []
    for i in range(n):
        successes = rng.randint(1, 4)
        failures = rng.choice([0, 0, 0, 1])
        out.append(sample_from_bucket(bucket(
            f"10.0.{i % 20}.{i % 7 + 1}", 8 + (i % 10),
            events=successes + failures + rng.randint(0, 6),
            failures=failures, successes=successes,
            hosts=rng.randint(1, 2), destinations=rng.randint(1, 3),
            bytes_out=rng.randint(10_000, 2_000_000), max_risk=rng.choice([None, 2]),
        )))
    return out


def brute_force_sample():
    return sample_from_bucket(bucket(
        "198.51.100.77", 3, events=180, failures=175, successes=1,
        users=40, hosts=1, destinations=1, bytes_out=0, max_risk=6,
    ))


def fitted(samples):
    return BehaviourModel().fit([s.vector for s in samples], [s.raw for s in samples])


def test_risk_bands_cover_the_1_to_10_scale():
    assert risk_from_percentile(0.0) == 10
    assert risk_from_percentile(0.004) == 9
    assert risk_from_percentile(0.04) == 6
    assert risk_from_percentile(0.3) == 3
    assert risk_from_percentile(0.6) == 2
    assert risk_from_percentile(0.9) == 1


def test_sample_from_bucket_builds_the_feature_vector():
    s = sample_from_bucket(bucket("203.0.113.5", 2, events=12, failures=9, successes=3, bytes_out=1023))

    assert s.entity == "203.0.113.5"
    assert s.window_start.startswith("2026-11-10T02:00")
    assert len(s.vector) == len(FEATURE_NAMES)
    assert s.raw["failure_ratio"] == pytest.approx(0.75)
    assert s.raw["auth_failures"] == 9


def test_brute_force_hour_scores_high_and_is_explained():
    model = fitted(normal_samples())
    attack = brute_force_sample()

    score = model.score([attack.vector], [attack.raw])[0]

    assert score.risk_score >= 9
    assert score.percentile < 0.005
    explained = {d.feature for d in score.deviations}
    assert "auth_failures" in explained or "failure_ratio" in explained


def test_normal_behaviour_scores_low():
    baseline = normal_samples()
    model = fitted(baseline)
    fresh = normal_samples(n=100, seed=99)

    risks = sorted(s.risk_score for s in model.score([x.vector for x in fresh], [x.raw for x in fresh]))

    assert risks[len(risks) // 2] <= 3          # median
    # Risk 8 means "rarer than 99% of the baseline", so about 1 in 100 normal
    # hours reaches it by construction; this is the scan's alert threshold.
    assert sum(r >= 8 for r in risks) <= 3


def test_scores_are_deterministic_for_the_same_baseline():
    baseline = normal_samples()
    attack = brute_force_sample()

    a = fitted(baseline).score([attack.vector], [attack.raw])[0]
    b = fitted(baseline).score([attack.vector], [attack.raw])[0]

    assert (a.anomaly_score, a.risk_score) == (b.anomaly_score, b.risk_score)


def _patch_collector(monkeypatch, baseline, recent):
    async def fake_collect(es, start, end):
        # The service asks for the baseline window first (ending before the
        # scoring window) and then for the recent window ending now.
        return recent if end > datetime.now(timezone.utc) - timedelta(minutes=5) else baseline
    monkeypatch.setattr(anomaly_detection, "collect_samples", fake_collect)


def test_service_trains_on_baseline_and_reports_the_attacker(monkeypatch):
    recent = normal_samples(n=5, seed=3) + [brute_force_sample()]
    _patch_collector(monkeypatch, normal_samples(), recent)
    service = AnomalyDetectionService()

    result = asyncio.run(service.detect(min_risk=7))

    assert result["model"]["status"] == "trained"
    assert result["model"]["training_samples"] == 400
    assert [a["entity"] for a in result["anomalies"]] == ["198.51.100.77"]
    assert result["anomalies"][0]["deviations"], "anomaly is not explained"

    threats = asyncio.run(service.scan_threats())["threats"]
    assert threats[0]["threat_type"] == "behavioral_anomaly"
    assert 1 <= threats[0]["risk_score"] <= 10


def test_service_refuses_to_score_without_enough_baseline(monkeypatch):
    _patch_collector(monkeypatch, normal_samples(n=10), [brute_force_sample()])
    service = AnomalyDetectionService()

    result = asyncio.run(service.detect())

    assert result["model"]["status"] == "insufficient_baseline"
    assert result["anomalies"] == []


def test_ml_endpoints_require_authentication(client):
    assert client.get("/api/v1/security/ml/status").status_code == 401
    assert client.get("/api/v1/security/ml/anomalies").status_code == 401
    assert client.post("/api/v1/security/ml/train").status_code == 401


def test_ml_endpoints_and_scan_report_model_state(client, auth_headers):
    status = client.get("/api/v1/security/ml/status", headers=auth_headers)
    assert status.status_code == 200
    assert status.json()["algorithm"] == "isolation_forest"

    # The fake Elasticsearch holds no events, so there is nothing to learn from.
    anomalies = client.get("/api/v1/security/ml/anomalies", headers=auth_headers)
    assert anomalies.status_code == 200
    assert anomalies.json()["model"]["status"] == "insufficient_baseline"

    scan = client.get("/api/v1/security/threats/scan", headers=auth_headers)
    assert scan.status_code == 200
    assert scan.json()["ml_model"]["status"] == "insufficient_baseline"

    assert client.get("/api/v1/security/ml/anomalies?min_risk=11", headers=auth_headers).status_code == 422


def test_explanations_only_report_increases_over_baseline():
    model = fitted(normal_samples())
    # Nothing but a few failures; every other feature is at or below baseline.
    quiet = sample_from_bucket(bucket("10.9.9.9", 9, events=6, failures=6, successes=0,
                                      users=0, hosts=0, destinations=0, bytes_out=0))

    deviations = model.score([quiet.vector], [quiet.raw])[0].deviations

    assert deviations and all(d.robust_z > 0 for d in deviations)
    assert {d.feature for d in deviations} <= {"auth_failures", "failure_ratio", "events"}
