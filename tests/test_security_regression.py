"""Regression tests derived from the forensic audit in AUDIT/.

Every test here corresponds to a finding that was reproduced against a live
instance.  Each is written to FAIL against the pre-remediation code and pass
once its fix lands - that is the evidence the fix actually works.

Finding IDs refer to AUDIT/FINDINGS.md.
"""
import asyncio
import inspect

import pytest
from app.main import app

# --------------------------------------------------------------------------
# SEC-001 - the security router was entirely unauthenticated (14 endpoints)
# --------------------------------------------------------------------------

def _security_routes():
    """Every route under /api/v1/security, as (method, path) pairs.

    Read from the generated OpenAPI schema rather than walking app.routes:
    that reflects the real public surface and does not depend on how a given
    FastAPI version represents included routers internally.

    Parametrising over this rather than a hardcoded list means a newly added
    endpoint is covered automatically - an unauthenticated route cannot be
    introduced silently. test_security_router_is_not_empty guards against this
    discovery returning nothing and the checks becoming vacuous.
    """
    schema = app.openapi()
    out = []
    for path, operations in schema.get("paths", {}).items():
        if not path.startswith("/api/v1/security"):
            continue
        for method in operations:
            if method.upper() in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
                out.append((method.upper(), path))
    return sorted(set(out))


SECURITY_ROUTES = _security_routes()


def test_security_router_is_not_empty():
    """Guard: if this fails the parametrisation below is silently vacuous."""
    assert len(SECURITY_ROUTES) >= 14, SECURITY_ROUTES


@pytest.mark.parametrize("method,path", SECURITY_ROUTES)
def test_security_routes_require_authentication(client, method, path):
    """SEC-001: anonymous callers must not reach any security endpoint.

    Pre-fix: all 14 returned 200 to an unauthenticated caller, including four
    POST endpoints that wrote attacker-controlled events into Elasticsearch.
    """
    resp = client.request(method, path, json={})
    assert resp.status_code in (401, 403), (
        f"{method} {path} returned {resp.status_code} without credentials; "
        "expected 401/403"
    )


def test_simulate_endpoints_rejected_in_production(client, auth_headers, monkeypatch):
    """SEC-001: the /simulate/* fixtures must be disabled when ENVIRONMENT=production."""
    from app import config

    monkeypatch.setattr(config.settings, "environment", "production")
    resp = client.post(
        "/api/v1/security/simulate/powershell",
        headers=auth_headers,
        json={
            "command": "whoami",
            "user": "u",
            "host": "h",
            "process_id": 1,
            "source_ip": "127.0.0.1",
        },
    )
    assert resp.status_code == 404, (
        f"simulate endpoint reachable in production (got {resp.status_code})"
    )


# --------------------------------------------------------------------------
# SEC-003 - predictable, brute-forceable password-reset OTP
# --------------------------------------------------------------------------

def test_otp_uses_cryptographic_randomness():
    """SEC-003: the OTP must come from `secrets`, never the `random` module.

    Pre-fix: email_service.py used random.choices (Mersenne Twister), whose
    output is fully reproducible from recoverable generator state.
    """
    from app.services import email_service

    # Inspect the compiled code objects rather than the source text, so an
    # explanatory docstring mentioning the old implementation cannot affect the
    # result. Walks nested code objects because the call sits in a generator
    # expression.
    import types

    def names(code):
        collected = set(code.co_names)
        for const in code.co_consts:
            if isinstance(const, types.CodeType):
                collected |= names(const)
        return collected

    referenced = names(email_service.generate_otp.__code__)
    assert "secrets" in referenced, "generate_otp does not use the `secrets` module"
    assert "random" not in referenced, "generate_otp still uses the `random` module"


def test_otp_has_sufficient_keyspace():
    """SEC-003: a 6-digit OTP (10^6) is exhaustible inside its own 15-min window."""
    from app.services.email_service import generate_otp

    assert len(generate_otp()) >= 8, "OTP is too short to resist online brute force"


def test_issuing_a_new_otp_invalidates_previous_ones(db_session, monkeypatch):
    """SEC-003: only one OTP may be valid at a time.

    Pre-fix: five /forgot-password calls produced five simultaneously valid OTPs,
    multiplying an attacker's hit probability at will.
    """
    from app.crud.user import create_user
    from app.models.password_reset import PasswordResetToken
    from app.schemas.user import UserCreate
    from app.services import email_service

    async def _ok(*a, **k):
        return True

    monkeypatch.setattr(email_service, "send_email", _ok)
    user = create_user(
        db_session,
        UserCreate(email="otp@example.com", username="otpuser", password="TestPassword123!"),
    )

    for _ in range(5):
        asyncio.run(email_service.send_password_reset_otp(db_session, user))

    unused = (
        db_session.query(PasswordResetToken)
        .filter(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.is_used == False,  # noqa: E712 - SQLAlchemy needs ==
        )
        .count()
    )
    assert unused == 1, f"{unused} OTPs are simultaneously valid; expected exactly 1"


def test_reset_password_locks_out_after_repeated_failures(client, test_user, monkeypatch):
    """SEC-003: repeated wrong OTPs must stop being processed.

    Pre-fix: 60 consecutive wrong guesses all returned 400 with no lockout and no
    rate limiting, at a measured 66.7 req/s.
    """
    from app.services import email_service

    async def _ok(*a, **k):
        return True

    monkeypatch.setattr(email_service, "send_email", _ok)
    client.post("/api/v1/users/register", json=test_user)
    client.post("/api/v1/users/forgot-password", json={"email": test_user["email"]})

    statuses = []
    for i in range(25):
        resp = client.post(
            "/api/v1/users/reset-password",
            json={
                "email": test_user["email"],
                "otp": f"{i:08d}",
                "new_password": "brandNewPassword123",
            },
        )
        statuses.append(resp.status_code)

    assert any(s in (423, 429) for s in statuses), (
        "no lockout or rate limit after 25 wrong OTP attempts; "
        f"statuses seen: {sorted(set(statuses))}"
    )


# --------------------------------------------------------------------------
# SEC-007 - user-enumeration oracle on /forgot-password
# --------------------------------------------------------------------------

def test_forgot_password_does_not_reveal_account_existence(client, test_user, monkeypatch):
    """SEC-007: known and unknown emails must be indistinguishable.

    Pre-fix: a known email whose SMTP send failed returned 500 while an unknown
    one returned 200 - a clean oracle, contradicting the code's own comment.
    """
    from app.services import email_service

    # Simulate the failing-SMTP condition that exposed the oracle.
    async def _fail(*a, **k):
        return False

    monkeypatch.setattr(email_service, "send_email", _fail)
    client.post("/api/v1/users/register", json=test_user)

    known = client.post("/api/v1/users/forgot-password", json={"email": test_user["email"]})
    unknown = client.post(
        "/api/v1/users/forgot-password", json={"email": "nobody@example.com"}
    )

    assert known.status_code == unknown.status_code, (
        f"status differs: known={known.status_code} unknown={unknown.status_code}"
    )
    assert known.json() == unknown.json(), "response body differs between known/unknown email"


# --------------------------------------------------------------------------
# SEC-012 - password change did not invalidate issued tokens
# --------------------------------------------------------------------------

def test_token_is_rejected_after_password_change(client, test_user, db_session):
    """SEC-012: a token minted before a password change must stop working.

    Pre-fix: the old token still returned 200 on /users/me afterwards; there is
    no refresh, logout or revocation anywhere in the application.
    """
    from app.crud.user import get_password_hash
    from app.models.user import User

    client.post("/api/v1/users/register", json=test_user)
    token = client.post(
        "/api/v1/users/login",
        data={"username": test_user["email"], "password": test_user["password"]},
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/api/v1/users/me", headers=headers).status_code == 200

    user = db_session.query(User).filter(User.email == test_user["email"]).first()
    user.hashed_password = get_password_hash("aCompletelyNewPassword456")
    db_session.commit()

    assert client.get("/api/v1/users/me", headers=headers).status_code == 401, (
        "token still valid after the password was changed"
    )


# --------------------------------------------------------------------------
# SEC-015 - validation errors echoed the rejected value
# --------------------------------------------------------------------------

def test_validation_errors_do_not_echo_submitted_values(client):
    """SEC-015: the rejected input must not be returned to the client.

    Pre-fix: posting a non-string password/otp echoed the value back in
    `input`, and the same payload was shipped to Logstash and indexed.
    """
    resp = client.post(
        "/api/v1/users/reset-password",
        json={"email": "a@example.com", "otp": 123456, "new_password": 55512345},
    )
    assert resp.status_code == 422
    body = resp.text
    assert '"input"' not in body, "validation response still echoes the rejected input"
    assert "123456" not in body and "55512345" not in body, (
        "validation response leaks the submitted secret value"
    )


# --------------------------------------------------------------------------
# FUNC-001 - detection silently returned [] when Elasticsearch rejected the query
# --------------------------------------------------------------------------

def test_detection_surfaces_failure_instead_of_empty_result(client, auth_headers, monkeypatch):
    """FUNC-001: an Elasticsearch failure must not look like 'no threats'.

    Pre-fix: threat_detection.py built its ES client with no credentials, so
    every query 401'd against a security-enabled cluster; all eight handlers
    swallowed it and returned 200 {"threats": [], "count": 0} - byte-identical
    to a clean result.
    """
    from app.services import threat_detection

    async def _boom(*args, **kwargs):
        raise Exception("simulated Elasticsearch authentication failure")

    monkeypatch.setattr(threat_detection.threat_detector.es, "search", _boom)

    resp = client.get("/api/v1/security/threats/brute-force", headers=auth_headers)
    assert resp.status_code == 503, (
        f"detection reported success ({resp.status_code}) while Elasticsearch was failing; "
        f"body={resp.text[:200]}"
    )


def test_missing_index_is_reported_as_no_results_not_degraded(client, auth_headers, monkeypatch):
    """A missing index means 'nothing ingested yet', not 'detection is broken'.

    The counterpart to the test above: failing loudly is right for a connection
    or auth error, but a fresh deployment with no security-* indices must not
    report itself degraded forever.
    """
    from elastic_transport import ApiResponseMeta, HttpHeaders
    from elasticsearch import NotFoundError

    from app.services import threat_detection

    meta = ApiResponseMeta(
        status=404, http_version="1.1", headers=HttpHeaders(), duration=0.0, node=None
    )

    async def _not_found(*args, **kwargs):
        raise NotFoundError("index_not_found_exception", meta, {})

    monkeypatch.setattr(threat_detection.threat_detector.es, "search", _not_found)

    resp = client.get("/api/v1/security/threats/powershell", headers=auth_headers)
    assert resp.status_code == 200, f"missing index reported as {resp.status_code}"
    assert resp.json()["count"] == 0


def test_threat_detection_client_is_authenticated():
    """FUNC-001: the detector's ES client must send credentials, like the logger's."""
    from app.services import threat_detection

    src = inspect.getsource(threat_detection)
    assert "basic_auth" in src or "es_client" in src, (
        "threat_detection builds an Elasticsearch client without credentials"
    )


# --------------------------------------------------------------------------
# OPS-002 - /health reported 200 while unhealthy
# --------------------------------------------------------------------------

def test_health_returns_503_when_a_dependency_is_down(client, monkeypatch):
    """OPS-002: an unhealthy service must fail its probe.

    Pre-fix: /health returned 200 with body {"status":"unhealthy",...}, so
    Kubernetes liveness and readiness probes could never fail.
    """
    from app.cache import cache

    async def _unhealthy():
        return False

    monkeypatch.setattr(cache, "health_check", _unhealthy)
    resp = client.get("/health")
    assert resp.status_code == 503, (
        f"/health returned {resp.status_code} while a dependency was down"
    )


def test_health_does_not_leak_database_connections(client, monkeypatch):
    """OPS-002: engine.connect() was never closed, leaking a connection per probe.

    Counts opened vs closed connections directly rather than reading pool
    internals, which differ between pool implementations.
    """
    from app import main as main_module

    opened, closed = [], []
    real_connect = main_module.engine.connect

    def tracking_connect(*args, **kwargs):
        conn = real_connect(*args, **kwargs)
        opened.append(conn)
        real_close = conn.close

        def close_and_record(*a, **k):
            closed.append(conn)
            return real_close(*a, **k)

        conn.close = close_and_record
        return conn

    monkeypatch.setattr(main_module.engine, "connect", tracking_connect)

    for _ in range(25):
        client.get("/health")

    leaked = len(opened) - len(closed)
    assert leaked == 0, (
        f"{leaked} of {len(opened)} health-check connections were never closed"
    )


# --------------------------------------------------------------------------
# SEC-014 - /metrics was anonymous
# --------------------------------------------------------------------------

def test_metrics_endpoint_requires_authentication(client):
    """SEC-014: Prometheus metrics must not be world-readable."""
    resp = client.get("/metrics")
    assert resp.status_code in (401, 403), (
        f"/metrics served anonymously (got {resp.status_code})"
    )


# --------------------------------------------------------------------------
# BUG-001 - the stats cache was never invalidated
# --------------------------------------------------------------------------

def test_stats_reflect_newly_created_todo(client, auth_headers, test_todo):
    """BUG-001: creating a todo must invalidate the cached statistics.

    Pre-fix (reproduced with a live Redis): stats kept reporting total_todos=1
    after a second todo was created, because create/update/delete invalidate
    `todos:*` and the single-todo key but never `stats:user:{id}`.
    """
    client.post("/api/v1/todos/", headers=auth_headers, json=test_todo)
    first = client.get("/api/v1/todos/stats/summary", headers=auth_headers).json()
    assert first["total_todos"] == 1

    client.post("/api/v1/todos/", headers=auth_headers, json={"title": "second todo"})
    second = client.get("/api/v1/todos/stats/summary", headers=auth_headers).json()

    assert second["total_todos"] == 2, (
        f"stats are stale after create: {second} (cache not invalidated)"
    )


# --------------------------------------------------------------------------
# Behaviour verified CORRECT during the audit - locked in against regression
# --------------------------------------------------------------------------

def test_cross_tenant_read_is_denied(client, auth_headers, second_user_headers, test_todo):
    """No IDOR: another user must not read someone else's todo."""
    todo_id = client.post("/api/v1/todos/", headers=auth_headers, json=test_todo).json()["id"]
    assert client.get(f"/api/v1/todos/{todo_id}", headers=second_user_headers).status_code == 404


def test_cross_tenant_writes_are_denied(client, auth_headers, second_user_headers, test_todo):
    """No IDOR on writes - untested by the original suite, which covered only GET."""
    todo_id = client.post("/api/v1/todos/", headers=auth_headers, json=test_todo).json()["id"]

    assert client.put(
        f"/api/v1/todos/{todo_id}", headers=second_user_headers, json={"title": "pwned"}
    ).status_code == 404
    assert client.delete(
        f"/api/v1/todos/{todo_id}", headers=second_user_headers
    ).status_code == 404

    owner_view = client.get(f"/api/v1/todos/{todo_id}", headers=auth_headers)
    assert owner_view.status_code == 200
    assert owner_view.json()["title"] == test_todo["title"], "owner's todo was modified"


def test_todo_id_is_an_integer(client, auth_headers, test_todo):
    """CONTRACT-001: ids are integers, not the UUID strings the docs claimed."""
    body = client.post("/api/v1/todos/", headers=auth_headers, json=test_todo).json()
    assert isinstance(body["id"], int), f"id is {type(body['id']).__name__}, expected int"


def test_password_hash_is_not_exposed(client, test_user):
    """UserResponse must never serialise hashed_password - untested previously."""
    body = client.post("/api/v1/users/register", json=test_user).json()
    assert "hashed_password" not in body
    assert "password" not in body


def test_otp_is_single_use(db_session, monkeypatch):
    """Verified correct during the audit; locked in."""
    from app.crud.user import create_user
    from app.schemas.user import UserCreate
    from app.services import email_service

    async def _ok(*a, **k):
        return True

    monkeypatch.setattr(email_service, "send_email", _ok)
    user = create_user(
        db_session,
        UserCreate(email="single@example.com", username="singleuse", password="TestPassword123!"),
    )
    otp = asyncio.run(email_service.send_password_reset_otp(db_session, user))

    assert email_service.verify_password_reset_otp(db_session, user.email, otp) is not None
    assert email_service.verify_password_reset_otp(db_session, user.email, otp) is None


def test_otp_cannot_be_redeemed_by_another_account(db_session, monkeypatch):
    """Verified correct during the audit; locked in."""
    from app.crud.user import create_user
    from app.schemas.user import UserCreate
    from app.services import email_service

    async def _ok(*a, **k):
        return True

    monkeypatch.setattr(email_service, "send_email", _ok)
    victim = create_user(
        db_session,
        UserCreate(email="victim@example.com", username="victim", password="TestPassword123!"),
    )
    create_user(
        db_session,
        UserCreate(email="other@example.com", username="other", password="TestPassword123!"),
    )
    otp = asyncio.run(email_service.send_password_reset_otp(db_session, victim))

    assert email_service.verify_password_reset_otp(db_session, "other@example.com", otp) is None
