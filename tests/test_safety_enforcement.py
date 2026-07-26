"""Server-side safety-enforcement tests (docs/SAFETY.md invariants).

Complements the headless Dart safety harness
(`apps/flutter_app/tool/verify/safety_harness.dart`) which proves the client
never raises master volume on wrong answers.
"""
import os
import tempfile
from pathlib import Path

os.environ.setdefault(
    "HEARBLOOM_DB", str(Path(tempfile.gettempdir()) / "hearbloom_test.db")
)

from fastapi.testclient import TestClient  # noqa: E402

from services.api.main import app  # noqa: E402
from ml.recommender import recommend  # noqa: E402

client = TestClient(app)


def test_reject_auto_volume_true():
    r = client.post("/profiles", json={"safety": {"auto_volume": True}})
    assert r.status_code == 400


def test_reject_absolute_thresholds_true():
    r = client.post("/profiles", json={"safety": {"absolute_thresholds": True}})
    assert r.status_code == 400


def test_profile_safety_defaults_are_coerced_safe():
    # Even a client that tries to disable research_only gets it forced back on.
    r = client.post("/profiles", json={"safety": {"research_only": False}})
    assert r.status_code == 200
    s = r.json()["safety"]
    assert s["auto_volume"] is False
    assert s["absolute_thresholds"] is False
    assert s["research_only"] is True
    assert s["separate_ear_approved"] is False


def test_separate_ear_presentation_requires_clinician_approval():
    p = client.post("/profiles", json={}).json()
    r = client.post("/sessions", json={"profile_id": p["id"], "condition": "left"})
    assert r.status_code == 403


def test_separate_ear_presentation_allowed_with_approval():
    p = client.post(
        "/profiles", json={"safety": {"separate_ear_approved": True}}
    ).json()
    assert p["safety"]["separate_ear_approved"] is True
    r = client.post("/sessions", json={"profile_id": p["id"], "condition": "right"})
    assert r.status_code == 200
    assert r.json()["condition"] == "right"


def test_invalid_condition_rejected():
    p = client.post("/profiles", json={}).json()
    r = client.post(
        "/sessions", json={"profile_id": p["id"], "condition": "both_ears"}
    )
    assert r.status_code == 400


def test_invalid_output_device_rejected():
    p = client.post("/profiles", json={}).json()
    r = client.post(
        "/sessions", json={"profile_id": p["id"], "output_device": "bone_conduction"}
    )
    assert r.status_code == 400


def test_comfortable_level_persisted_and_bounded():
    p = client.post("/profiles", json={}).json()
    ok = client.post(
        "/sessions", json={"profile_id": p["id"], "comfortable_level": 0.42}
    )
    assert ok.status_code == 200
    assert ok.json()["comfortable_level"] == 0.42
    # Out-of-range level is rejected by model validation (never a raw dB HL).
    bad = client.post(
        "/sessions", json={"profile_id": p["id"], "comfortable_level": 1.5}
    )
    assert bad.status_code == 422


def test_recommender_never_instructs_a_volume_increase():
    fatigued_wrong = [
        {
            "module_id": "noise",
            "group_id": "sentence_noise",
            "correct": 0,
            "replay_count": 0,
            "fatigue_after": 2,
        }
        for _ in range(25)
    ]
    for trials in ([], fatigued_wrong):
        rec = recommend(trials)
        params = rec.get("parameters", {})
        assert not any("volume" in str(k).lower() for k in params), rec
        assert rec.get("reason")
        assert 0.0 <= rec["confidence"] <= 1.0
