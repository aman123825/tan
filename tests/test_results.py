"""Results separation + reliability tests.

Verifies that results are bucketed per (condition, output_device, module,
group, mode) and never pooled across output device, and that reliability is
computed by the deterministic engine (Score.reliability).
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


def _new_profile():
    return client.post("/profiles", json={}).json()["id"]


def _new_session(pid, device="wired_headphones"):
    return client.post(
        "/sessions", json={"profile_id": pid, "output_device": device}
    ).json()["id"]


def _post_trials(session_id, n, *, correct=True, latency_ms=500, replay=0, mode="test"):
    for i in range(n):
        client.post(
            "/trials",
            json={
                "session_id": session_id,
                "module_id": "noise",
                "group_id": "sentence_noise",
                "mode": mode,
                "target": "bell",
                "response": "bell" if correct else "ball",
                "correct": correct,
                "latency_ms": latency_ms,
                "replay_count": replay,
            },
        )


def _bucket(separated, device):
    return next(b for b in separated if b["output_device"] == device)


def test_results_not_pooled_across_output_device():
    pid = _new_profile()
    wired = _new_session(pid, "wired_headphones")
    bluetooth = _new_session(pid, "bluetooth")
    _post_trials(wired, 3)
    _post_trials(bluetooth, 5)

    res = client.get(f"/profiles/{pid}/results").json()
    assert res["pooling_policy"] == "not_pooled_across_condition_or_device"
    assert res["total_trials"] == 8
    devices = {b["output_device"] for b in res["separated"]}
    assert devices == {"wired_headphones", "bluetooth"}
    assert _bucket(res["separated"], "wired_headphones")["n"] == 3
    assert _bucket(res["separated"], "bluetooth")["n"] == 5


def test_reliability_reliable_for_clean_run():
    pid = _new_profile()
    s = _new_session(pid)
    _post_trials(s, 20, latency_ms=600, replay=0)
    res = client.get(f"/profiles/{pid}/results").json()
    bucket = res["separated"][0]
    assert bucket["reliability"]["reliable"] is True


def test_reliability_flags_too_fast_responses():
    pid = _new_profile()
    s = _new_session(pid)
    _post_trials(s, 20, latency_ms=100, replay=0)  # all faster than 180ms
    res = client.get(f"/profiles/{pid}/results").json()
    bucket = res["separated"][0]
    assert bucket["reliability"]["reliable"] is False


def test_reliability_insufficient_trials():
    pid = _new_profile()
    s = _new_session(pid)
    _post_trials(s, 5)
    res = client.get(f"/profiles/{pid}/results").json()
    bucket = res["separated"][0]
    assert bucket["reliability"]["reason"] == "insufficient_trials"


def test_training_and_test_modes_separated():
    pid = _new_profile()
    s = _new_session(pid)
    _post_trials(s, 2, mode="training")
    _post_trials(s, 3, mode="test")
    res = client.get(f"/profiles/{pid}/results").json()
    modes = {b["mode"] for b in res["separated"]}
    assert {"training", "test"} <= modes
