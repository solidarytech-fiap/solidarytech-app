import os
import sys
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("AWS_DYNAMODB_TABLE", "SolidaryTechVolunteers")
os.environ.setdefault("AWS_REGION", "us-east-1")


@pytest.fixture
def client_and_table():
    table = MagicMock()
    resource = MagicMock()
    resource.Table.return_value = table
    with patch("boto3.resource", return_value=resource):
        sys.modules.pop("app", None)
        import app as app_module

        app_module.app.config["TESTING"] = True
        yield app_module.app.test_client(), table


def test_health(client_and_table):
    client, _ = client_and_table
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "volunteer-service"


def test_register_missing_fields(client_and_table):
    client, _ = client_and_table
    assert client.post("/volunteers", json={"name": "Ana"}).status_code == 400


def test_register_ok(client_and_table):
    client, table = client_and_table
    resp = client.post("/volunteers", json={"name": "Ana", "email": "ana@x.org", "ngo_id": 1})
    assert resp.status_code == 201
    table.put_item.assert_called_once()


def test_list_by_ngo(client_and_table):
    client, table = client_and_table
    table.scan.return_value = {"Items": [{"volunteer_id": "1", "ngo_id": 1}]}
    resp = client.get("/volunteers/1")
    assert resp.status_code == 200
    assert len(resp.get_json()) == 1
