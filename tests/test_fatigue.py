"""Fatigue self-report round-trip tests.

Fatigue is informational only (it never alters locked scoring); these tests
verify it is captured at session start (`fatigue_before`), recorded at session
end (`fatigue_after`), persisted, and range-validated (0..10).
"""
import os
import tempfile
from pathlib import Path

os.environ.setdefault(
    "HEARBLOOM_DB", str(Path(tempfile.gettempdir()) / "hearbloom_test.db")
)

from fastapi.testclient import TestClient  # noqa: E402

from services.api.main import app  # noqa: E402

client = TestClient(app)


def test_fatigue_before_and_after_persist():
    pid = client.post("/profiles", json={}).json()["id"]
    sid = client.post(
        "/sessions",
        json={"profile_id": pid, "fatigue_before": 4},
    ).json()["id"]
    client.post(
        "/trials",
        json={
            "session_id": sid,
            "module_id": "noise",
            "group_id": "sentence_noise",
            "mode": "test",
            "target": "bell",
            "response": "bell",
            "correct": True,
            "latency_ms": 500,
        },
    )
    end = client.post(f"/sessions/{sid}/end", json={"fatigue_after": 7})
    assert end.status_code == 200
    assert end.json()["fatigue_after"] == 7

    export = client.get(f"/profiles/{pid}/export.json").json()
    session = next(s for s in export["sessions"] if s["id"] == sid)
    assert session["fatigue_before"] == 4
    assert session["fatigue_after"] == 7
    assert session["ended_at"] is not None


def test_fatigue_after_out_of_range_rejected():
    pid = client.post("/profiles", json={}).json()["id"]
    sid = client.post("/sessions", json={"profile_id": pid}).json()["id"]
    assert client.post(f"/sessions/{sid}/end", json={"fatigue_after": 11}).status_code == 422
    assert client.post(f"/sessions/{sid}/end", json={"fatigue_after": -1}).status_code == 422


def test_fatigue_before_out_of_range_rejected():
    pid = client.post("/profiles", json={}).json()["id"]
    r = client.post("/sessions", json={"profile_id": pid, "fatigue_before": 99})
    assert r.status_code == 422
