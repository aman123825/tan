"""Content-integrity + export tests (KIRO handoff #9 export, #10 hashes/retirement)."""
import csv
import hashlib
import io
import os
import tempfile
from pathlib import Path

os.environ.setdefault(
    "HEARBLOOM_DB", str(Path(tempfile.gettempdir()) / "hearbloom_test.db")
)

from fastapi.testclient import TestClient  # noqa: E402

from services.api.main import app, ROOT, RETIRED_PROTOCOL_VERSIONS  # noqa: E402

client = TestClient(app)


def _session():
    pid = client.post("/profiles", json={}).json()["id"]
    sid = client.post("/sessions", json={"profile_id": pid}).json()["id"]
    return pid, sid


def _trial(session_id, **overrides):
    body = {
        "session_id": session_id,
        "module_id": "auditory",
        "group_id": "gap",
        "mode": "test",
        "target": "interval_2",
        "response": "interval_2",
        "correct": True,
        "latency_ms": 700,
        "replay_count": 0,
        "parameters": {"gap_ms": 12.0},
    }
    body.update(overrides)
    return body


def test_content_manifest_hashes_match_files():
    m = client.get("/content/manifest").json()
    assert m["research_only"] is True
    assert m["protocol_version"]
    cat = m["files"]["catalog"]
    # Hash is a real SHA-256 of the served catalog file.
    expected = hashlib.sha256((ROOT / "protocols/catalog.json").read_bytes()).hexdigest()
    assert cat["sha256"] == expected
    assert len(cat["sha256"]) == 64
    assert cat["bytes"] > 0


def test_manifest_lists_retired_versions():
    m = client.get("/content/manifest").json()
    assert "0.0.1-alpha" in m["retired_protocol_versions"]
    assert sorted(m["retired_protocol_versions"]) == m["retired_protocol_versions"]


def test_retired_protocol_version_is_rejected():
    _, sid = _session()
    retired = sorted(RETIRED_PROTOCOL_VERSIONS)[0]
    bad = client.post("/trials", json=_trial(sid, protocol_version=retired))
    assert bad.status_code == 400
    ok = client.post("/trials", json=_trial(sid, protocol_version="1.0.0"))
    assert ok.status_code == 200


def test_export_csv_has_header_and_rows():
    pid, sid = _session()
    client.post("/trials", json=_trial(sid))
    client.post("/trials", json=_trial(sid, correct=False, response="interval_1"))

    r = client.get(f"/profiles/{pid}/export.csv")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers.get("content-disposition", "")

    reader = list(csv.DictReader(io.StringIO(r.text)))
    assert len(reader) == 2
    assert reader[0]["module_id"] == "auditory"
    assert reader[0]["group_id"] == "gap"
    assert reader[0]["protocol_version"] == "1.0.0"
    assert {"at", "session_id", "app_version", "stimulus_version"} <= set(reader[0].keys())


def test_export_json_structure():
    pid, sid = _session()
    client.post("/trials", json=_trial(sid))
    data = client.get(f"/profiles/{pid}/export.json").json()
    assert data["research_only"] is True
    assert data["exported_at"]
    assert data["profile"]["safety"]["research_only"] is True
    assert len(data["sessions"]) >= 1
    assert len(data["trials"]) >= 1


def test_export_unknown_profile_404():
    assert client.get("/profiles/does-not-exist/export.json").status_code == 404
    assert client.get("/profiles/does-not-exist/export.csv").status_code == 404
