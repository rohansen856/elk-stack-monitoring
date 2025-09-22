import pytest
from fastapi.testclient import TestClient


def test_register_user(client: TestClient, test_user):
    response = client.post("/api/v1/users/register", json=test_user)
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == test_user["email"]
    assert data["username"] == test_user["username"]
    assert "id" in data


def test_register_duplicate_email(client: TestClient, test_user):
    client.post("/api/v1/users/register", json=test_user)
    response = client.post("/api/v1/users/register", json=test_user)
    assert response.status_code == 400
    assert "Email already registered" in response.json()["detail"]


def test_login_user(client: TestClient, test_user):
    client.post("/api/v1/users/register", json=test_user)

    login_data = {
        "username": test_user["email"],
        "password": test_user["password"]
    }
    response = client.post("/api/v1/users/login", data=login_data)
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"


def test_login_invalid_credentials(client: TestClient):
    login_data = {
        "username": "nonexistent@example.com",
        "password": "wrongpassword"
    }
    response = client.post("/api/v1/users/login", data=login_data)
    assert response.status_code == 401


def test_get_current_user(client: TestClient, test_user):
    client.post("/api/v1/users/register", json=test_user)

    login_data = {
        "username": test_user["email"],
        "password": test_user["password"]
    }
    login_response = client.post("/api/v1/users/login", data=login_data)
    token = login_response.json()["access_token"]

    headers = {"Authorization": f"Bearer {token}"}
    response = client.get("/api/v1/users/me", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == test_user["email"]


def test_get_current_user_invalid_token(client: TestClient):
    headers = {"Authorization": "Bearer invalid_token"}
    response = client.get("/api/v1/users/me", headers=headers)
    assert response.status_code == 401