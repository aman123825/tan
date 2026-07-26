"""Trial persistence + version-tracking tests.

Verifies the server stores full version lineage on every trial, rejects blank
lineage / invalid workflow modes, and accepts the exact payload shape produced
by the Dart client (`buildTrialPayload` /
`apps/flutter_app/lib/core/trial_event.dart`).
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

# Must match apps/flutter_app/lib/core/trial_event.dart::kTrialPayloadKeys.
DART_PAYLOAD_KEYS = [
    "session_id",
    "module_id",
    "group_id",
    "mode",
    "target",
    "response",
    "correct",
    "latency_ms",
    "replay_count",
    "parameters",
    "app_version",
    "protocol_version",
    "stimulus_version",
]


def _session():
    p = client.post("/profiles", json={}).json()
    return client.post("/sessions", json={"profile_id": p["id"]}).json(), p


def _trial(session_id, **overrides):
    body = {
        "session_id": session_id,
        "module_id": "noise",
        "group_id": "sentence_noise",
        "mode": "training",
        "target": "bell",
        "response": "bell",
        "correct": True,
        "latency_ms": 640,
        "replay_count": 0,
        "parameters": {"snr_db": 8},
        "app_version": "0.1.0",
        "protocol_version": "1.0.0",
        "stimulus_version": "demo-0.1",
    }
    body.update(overrides)
    return body


def test_trial_stores_full_version_lineage():
    s, p = _session()
    body = _trial(
        s["id"],
        app_version="1.2.3",
        protocol_version="9.9.9",
        stimulus_version="pack-2025",
    )
    assert client.post("/trials", json=body).status_code == 200
    trials = client.get(f"/profiles/{p['id']}/results").json()["trials"]
    mine = [t for t in trials if t["session_id"] == s["id"]]
    assert len(mine) == 1
    stored = mine[0]
    assert stored["app_version"] == "1.2.3"
    assert stored["protocol_version"] == "9.9.9"
    assert stored["stimulus_version"] == "pack-2025"


def test_blank_version_is_rejected():
    s, _ = _session()
    for field in ("app_version", "protocol_version", "stimulus_version"):
        r = client.post("/trials", json=_trial(s["id"], **{field: ""}))
        assert r.status_code == 422, field


def test_invalid_workflow_mode_rejected():
    s, _ = _session()
    r = client.post("/trials", json=_trial(s["id"], mode="freestyle"))
    assert r.status_code == 400


def test_each_workflow_mode_accepted():
    s, _ = _session()
    for mode in ("introduction", "preview", "training", "test", "results"):
        r = client.post("/trials", json=_trial(s["id"], mode=mode))
        assert r.status_code == 200, mode


def test_different_protocol_versions_are_both_retained():
    s, p = _session()
    client.post("/trials", json=_trial(s["id"], protocol_version="1.0.0"))
    client.post("/trials", json=_trial(s["id"], protocol_version="2.0.0"))
    trials = [
        t
        for t in client.get(f"/profiles/{p['id']}/results").json()["trials"]
        if t["session_id"] == s["id"]
    ]
    versions = {t["protocol_version"] for t in trials}
    assert {"1.0.0", "2.0.0"} <= versions


def test_dart_client_payload_shape_is_accepted():
    # The exact key set the Dart client sends must be accepted as-is.
    s, _ = _session()
    body = _trial(s["id"])
    assert sorted(body.keys()) == sorted(DART_PAYLOAD_KEYS)
    assert client.post("/trials", json=body).status_code == 200
