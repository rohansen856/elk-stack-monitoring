"""Regression tests for detection, alerting and validation defects found by the
2026-11-17 end-to-end run against a live stack (see AUDIT/RUNTIME_BASELINE_2026-11-17.md).
"""
import asyncio
import json
from datetime import timedelta

from app.services.alerting import alerting_service
from app.services.threat_detection import EVENT_INDICES, ThreatDetectionService


def _run(coro):
    return asyncio.run(coro)


def test_alert_is_actually_written_to_elasticsearch(fake_elasticsearch):
    """create_elasticsearch_alert never awaited the async index() call, so no
    alert was stored while the method still reported success."""
    ok = _run(alerting_service.create_elasticsearch_alert({"threat_type": "x", "risk_score": 9}))

    assert ok is True
    assert len(fake_elasticsearch.indexed) == 1
    written = fake_elasticsearch.indexed[0]
    assert written["index"].startswith("security-alerts-")
    assert written["document"]["threat_type"] == "x"


def test_privilege_escalation_hunt_requires_a_matching_condition():
    """Without minimum_should_match the `should` clauses were optional and the
    hunt returned every event from the last hour as privilege escalation."""
    q = ThreatDetectionService._privilege_escalation_query()["query"]["bool"]

    assert q["should"], "hunt has no escalation conditions"
    assert q.get("minimum_should_match") == 1


def test_powershell_detection_does_not_use_case_sensitive_wildcards():
    """A case-sensitive wildcard on the analysed `message` field could never
    match 'Invoke-Expression' etc. (tokens are lowercased)."""
    body = ThreatDetectionService._powershell_pattern_query("Invoke-Expression", timedelta(hours=1))
    text = json.dumps(body, default=str)

    assert '"wildcard"' not in text
    assert {"match_phrase": {"message": "Invoke-Expression"}} in body["query"]["bool"]["should"]


def test_detectors_exclude_derived_indices_and_use_ip_fields(fake_elasticsearch):
    """security-threats-* (enrichment copies) and security-alerts-* matched
    security-* and were counted a second time; src_ip is an `ip` field, so
    aggregating on src_ip.keyword found nothing."""
    _run(ThreatDetectionService().detect_brute_force_attacks())

    search = fake_elasticsearch.searches[-1]
    assert search["index"] == EVENT_INDICES
    assert "-security-threats-*" in EVENT_INDICES and "-security-alerts-*" in EVENT_INDICES
    assert search["body"]["aggs"]["by_src_ip"]["terms"]["field"] == "src_ip"


def test_overlong_todo_title_is_rejected_with_422(client, auth_headers):
    """The column is String(255); an unbounded schema let longer titles reach
    Postgres and fail there as a 500."""
    resp = client.post("/api/v1/todos/", json={"title": "x" * 300}, headers=auth_headers)

    assert resp.status_code == 422


def test_metrics_rejects_jwt_of_deactivated_user(client, auth_headers, db_session, test_user):
    """/metrics accepted any once-valid JWT, unlike every other endpoint."""
    from app.models.user import User

    assert client.get("/metrics", headers=auth_headers).status_code == 200

    user = db_session.query(User).filter(User.email == test_user["email"]).one()
    user.is_active = False
    db_session.commit()

    assert client.get("/metrics", headers=auth_headers).status_code == 401
