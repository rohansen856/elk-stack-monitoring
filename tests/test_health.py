from fastapi.testclient import TestClient


def test_health_check_reports_healthy(client: TestClient):
    """A healthy stack must report 200 and say so.

    The previous version of this test asserted only that the `status` and
    `database` keys existed, never their values. Because /health returned 200
    even when unhealthy, it passed with the database and Redis both down.
    """
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database"] == "ok"
    assert data["redis"] == "ok"


def test_metrics_requires_credentials(client: TestClient):
    """Prometheus metrics are no longer world-readable (AUDIT SEC-014)."""
    assert client.get("/metrics").status_code == 401


def test_metrics_accessible_with_scrape_token(client: TestClient, monkeypatch):
    """A dedicated scrape token is accepted, since Prometheus cannot log in."""
    from app import config

    monkeypatch.setattr(config.settings, "metrics_token", "test-scrape-token")
    response = client.get(
        "/metrics", headers={"Authorization": "Bearer test-scrape-token"}
    )
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]


def test_metrics_accessible_with_user_token(client: TestClient, auth_headers):
    """A normal authenticated user may also read metrics."""
    response = client.get("/metrics", headers=auth_headers)
    assert response.status_code == 200
