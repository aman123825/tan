"""Clinician review-mode tests (KIRO handoff #9).

Reviewing annotates a session; it must never change locked assessment scoring.
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


def _profile_session_with_trial():
    pid = client.post("/profiles", json={}).json()["id"]
    sid = client.post("/sessions", json={"profile_id": pid}).json()["id"]
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
    return pid, sid


def test_review_records_reviewer_and_status():
    pid, sid = _profile_session_with_trial()
    r = client.post(
        f"/sessions/{sid}/review",
        json={"reviewed_by": "Dr Rao", "status": "approved", "note": "clean run"},
    )
    assert r.status_code == 200
    row = r.json()
    assert row["reviewed_by"] == "Dr Rao"
    assert row["review_status"] == "approved"
    assert row["review_note"] == "clean run"
    assert row["reviewed_at"]


def test_review_surfaced_in_export():
    pid, sid = _profile_session_with_trial()
    client.post(
        f"/sessions/{sid}/review",
        json={"reviewed_by": "Dr Rao", "status": "flagged", "note": "recheck"},
    )
    data = client.get(f"/profiles/{pid}/export.json").json()
    session = next(s for s in data["sessions"] if s["id"] == sid)
    assert session["review_status"] == "flagged"
    assert session["reviewed_by"] == "Dr Rao"


def test_invalid_review_status_rejected():
    _, sid = _profile_session_with_trial()
    r = client.post(
        f"/sessions/{sid}/review",
        json={"reviewed_by": "Dr Rao", "status": "brilliant"},
    )
    assert r.status_code == 400


def test_review_requires_reviewer():
    _, sid = _profile_session_with_trial()
    r = client.post(f"/sessions/{sid}/review", json={"reviewed_by": ""})
    assert r.status_code == 422


def test_review_unknown_session_404():
    r = client.post(
        "/sessions/nope/review", json={"reviewed_by": "Dr Rao", "status": "approved"}
    )
    assert r.status_code == 404


def test_review_does_not_change_scoring():
    pid, sid = _profile_session_with_trial()
    before = client.get(f"/profiles/{pid}/results").json()
    client.post(
        f"/sessions/{sid}/review",
        json={"reviewed_by": "Dr Rao", "status": "flagged", "note": "n/a"},
    )
    after = client.get(f"/profiles/{pid}/results").json()
    # Locked deterministic scoring is immutable under review.
    assert before["total_trials"] == after["total_trials"]
    assert before["accuracy"] == after["accuracy"]
    assert [t["correct"] for t in before["trials"]] == [
        t["correct"] for t in after["trials"]
    ]
