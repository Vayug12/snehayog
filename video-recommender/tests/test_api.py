import pytest
from fastapi.testclient import TestClient
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.api.main import app

client = TestClient(app)


def test_root():
    response = client.get("/")
    assert response.status_code == 200


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
