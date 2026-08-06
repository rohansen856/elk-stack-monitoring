"""Shared test fixtures.

IMPORTANT: the test environment is configured at module import time, *before*
``app.*`` is imported.  ``app.config.Settings`` is instantiated at import time
(``app/config.py``), so any variable not present here causes a hard
``ValidationError`` on import.  Setting them explicitly also guarantees the suite
never picks up the developer's real ``.env``, which holds live credentials.
"""
import os

# --- test environment (must precede every `app.` import) --------------------
_TEST_ENV = {
    "DATABASE_URL": "sqlite://",  # overridden per-test by the `engine` fixture
    "REDIS_URL": "redis://127.0.0.1:6379/15",
    "SECRET_KEY": "test-only-secret-key-not-used-anywhere-real",
    "ALGORITHM": "HS256",
    "ACCESS_TOKEN_EXPIRE_MINUTES": "30",
    "ENVIRONMENT": "development",
    "LOG_LEVEL": "WARNING",
    "ELASTICSEARCH_HOST": "127.0.0.1",
    "ELASTICSEARCH_PORT": "9200",
    "ELASTICSEARCH_PASSWORD": "test-es-password",
    "LOGSTASH_HOST": "127.0.0.1",
    "LOGSTASH_TCP_PORT": "5959",
    "EMAIL_SMTP_SERVER": "127.0.0.1",
    "EMAIL_SMTP_PORT": "2525",
    "EMAIL_SMTP_USERNAME": "test@example.com",
    "EMAIL_SMTP_PASSWORD": "test-smtp-password",
    "EMAIL_SENDER_ADDRESS": "test@example.com",
    "EMAIL_SENDER_NAME": "Sentinel Test",
    "SLACK_WEBHOOK_URL": "https://hooks.slack.test/services/TEST/TEST/TEST",
}
for _k, _v in _TEST_ENV.items():
    os.environ[_k] = _v

import fakeredis.aioredis  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402

# Importing the models registers their mappers on Base.metadata.
from app.models.password_reset import PasswordResetToken  # noqa: E402,F401
from app.models.todo import Todo  # noqa: E402,F401
from app.models.user import User  # noqa: E402,F401


@pytest.fixture(scope="function")
def engine():
    """A fresh in-memory SQLite database per test.

    Uses StaticPool so every connection sees the same in-memory database; this
    keeps the test DB out of the repository root, where the old file-backed
    ``./test.db`` ended up committed to git.
    """
    eng = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=eng)
    yield eng
    Base.metadata.drop_all(bind=eng)
    eng.dispose()


@pytest.fixture(scope="function")
def db_session(engine):
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(scope="function")
def fake_redis(monkeypatch):
    """Replace the cache's Redis client with an in-process fake.

    Without this the cache code paths never execute under test, which is why the
    stats-invalidation defect went unnoticed.
    """
    from app import cache as cache_module

    # The cache now uses redis.asyncio, so the fake must be the async variant.
    fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache_module.cache, "redis_client", fake)
    return fake


@pytest.fixture(scope="function")
def client(engine, fake_redis):
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def override_get_db():
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def disable_rate_limiting():
    """Rate limits are keyed on the client IP, and every test shares 127.0.0.1.

    Left enabled, one test's requests exhaust the budget for the next. Tests
    that specifically exercise limiting re-enable it via `rate_limiting`.
    """
    from app.rate_limit import limiter

    limiter.enabled = False
    yield
    limiter.enabled = True


@pytest.fixture
def rate_limiting():
    """Opt back in to rate limiting for tests that assert on it."""
    from app.rate_limit import limiter

    limiter.enabled = True
    limiter.reset()
    yield
    limiter.enabled = False


@pytest.fixture
def test_user():
    return {
        "email": "test@example.com",
        "username": "testuser",
        "password": "testpassword123",
    }


@pytest.fixture
def test_todo():
    return {
        "title": "Test Todo",
        "description": "This is a test todo",
        "priority": "medium",
    }


@pytest.fixture
def auth_headers(client, test_user):
    """Register + log in, returning ready-to-use Authorization headers."""
    client.post("/api/v1/users/register", json=test_user)
    resp = client.post(
        "/api/v1/users/login",
        data={"username": test_user["email"], "password": test_user["password"]},
    )
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def second_user_headers(client):
    """A second, unrelated account - used for cross-tenant authorization tests."""
    other = {
        "email": "mallory@example.com",
        "username": "mallory",
        "password": "malloryPassword123",
    }
    client.post("/api/v1/users/register", json=other)
    resp = client.post(
        "/api/v1/users/login",
        data={"username": other["email"], "password": other["password"]},
    )
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
