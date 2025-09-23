import pytest
from fastapi.testclient import TestClient


def get_auth_headers(client: TestClient, test_user):
    client.post("/api/v1/users/register", json=test_user)
    login_data = {
        "username": test_user["email"],
        "password": test_user["password"]
    }
    login_response = client.post("/api/v1/users/login", data=login_data)
    token = login_response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_create_todo(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)
    response = client.post("/api/v1/todos/", json=test_todo, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == test_todo["title"]
    assert data["description"] == test_todo["description"]
    assert data["priority"] == test_todo["priority"]
    assert data["completed"] is False
    assert "id" in data


def test_get_todos(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    client.post("/api/v1/todos/", json=test_todo, headers=headers)

    response = client.get("/api/v1/todos/", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["title"] == test_todo["title"]


def test_get_todo_by_id(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    create_response = client.post("/api/v1/todos/", json=test_todo, headers=headers)
    todo_id = create_response.json()["id"]

    response = client.get(f"/api/v1/todos/{todo_id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == test_todo["title"]


def test_update_todo(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    create_response = client.post("/api/v1/todos/", json=test_todo, headers=headers)
    todo_id = create_response.json()["id"]

    update_data = {"title": "Updated Todo", "completed": True}
    response = client.put(f"/api/v1/todos/{todo_id}", json=update_data, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Updated Todo"
    assert data["completed"] is True


def test_delete_todo(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    create_response = client.post("/api/v1/todos/", json=test_todo, headers=headers)
    todo_id = create_response.json()["id"]

    response = client.delete(f"/api/v1/todos/{todo_id}", headers=headers)
    assert response.status_code == 200

    get_response = client.get(f"/api/v1/todos/{todo_id}", headers=headers)
    assert get_response.status_code == 404


def test_get_todo_stats(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    client.post("/api/v1/todos/", json=test_todo, headers=headers)
    completed_todo = {**test_todo, "title": "Completed Todo"}
    create_response = client.post("/api/v1/todos/", json=completed_todo, headers=headers)
    todo_id = create_response.json()["id"]
    client.put(f"/api/v1/todos/{todo_id}", json={"completed": True}, headers=headers)

    response = client.get("/api/v1/todos/stats/summary", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["total_todos"] == 2
    assert data["completed_todos"] == 1
    assert data["pending_todos"] == 1
    assert data["completion_rate"] == 50.0


def test_filter_todos_by_completion(client: TestClient, test_user, test_todo):
    headers = get_auth_headers(client, test_user)

    client.post("/api/v1/todos/", json=test_todo, headers=headers)
    completed_todo = {**test_todo, "title": "Completed Todo"}
    create_response = client.post("/api/v1/todos/", json=completed_todo, headers=headers)
    todo_id = create_response.json()["id"]
    client.put(f"/api/v1/todos/{todo_id}", json={"completed": True}, headers=headers)

    response = client.get("/api/v1/todos/?completed=true", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["completed"] is True


def test_search_todos(client: TestClient, test_user):
    headers = get_auth_headers(client, test_user)

    todo1 = {"title": "Buy groceries", "description": "Milk and bread"}
    todo2 = {"title": "Walk the dog", "description": "In the park"}

    client.post("/api/v1/todos/", json=todo1, headers=headers)
    client.post("/api/v1/todos/", json=todo2, headers=headers)

    response = client.get("/api/v1/todos/?search=groceries", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert "groceries" in data[0]["title"]


def test_unauthorized_access(client: TestClient, test_todo):
    response = client.post("/api/v1/todos/", json=test_todo)
    assert response.status_code == 403


def test_access_other_users_todo(client: TestClient, test_todo):
    user1 = {"email": "user1@example.com", "username": "user1", "password": "password123"}
    user2 = {"email": "user2@example.com", "username": "user2", "password": "password123"}

    headers1 = get_auth_headers(client, user1)
    headers2 = get_auth_headers(client, user2)

    create_response = client.post("/api/v1/todos/", json=test_todo, headers=headers1)
    todo_id = create_response.json()["id"]

    response = client.get(f"/api/v1/todos/{todo_id}", headers=headers2)
    assert response.status_code == 404