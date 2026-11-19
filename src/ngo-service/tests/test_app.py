import os
import sys
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DATABASE_URL", "postgres://test:test@localhost:5432/test")


@pytest.fixture
def client_and_cursor():
    cursor = MagicMock()
    conn = MagicMock()
    conn.cursor.return_value.__enter__.return_value = cursor
    pool = MagicMock()
    pool.getconn.return_value = conn

    with patch("psycopg2.pool.ThreadedConnectionPool", return_value=pool):
        sys.modules.pop("app", None)
        import app as app_module

        app_module.app.config["TESTING"] = True
        yield app_module.app.test_client(), cursor


def test_health(client_and_cursor):
    client, _ = client_and_cursor
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "ngo-service"


def test_create_ngo_missing_fields(client_and_cursor):
    client, _ = client_and_cursor
    resp = client.post("/ngos", json={"name": "X"})
    assert resp.status_code == 400


def test_create_ngo_ok(client_and_cursor):
    client, cursor = client_and_cursor
    cursor.fetchone.return_value = {"id": 1, "name": "ONG", "email": "a@b.org", "cause": "Educacao", "city": "SP"}
    resp = client.post("/ngos", json={"name": "ONG", "email": "a@b.org", "cause": "Educacao", "city": "SP"})
    assert resp.status_code == 201
    assert resp.get_json()["id"] == 1


def test_metrics_endpoint(client_and_cursor):
    client, _ = client_and_cursor
    client.post("/ngos", json={})
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"http_requests_total" in resp.data
