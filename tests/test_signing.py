"""Content-pack signing tests (KIRO handoff #10 — signatures).

The manifest is signed with HMAC-SHA256 so a client can verify authenticity and
detect tampering of the bundled content pack.
"""
import hashlib
import hmac
import json
import os
import tempfile
from pathlib import Path

os.environ.setdefault(
    "HEARBLOOM_DB", str(Path(tempfile.gettempdir()) / "hearbloom_test.db")
)

from fastapi.testclient import TestClient  # noqa: E402

from services.api.main import app, CONTENT_SIGNING_KEY  # noqa: E402

client = TestClient(app)


def _recompute(manifest_without_signature: dict) -> str:
    canonical = json.dumps(
        manifest_without_signature, sort_keys=True, separators=(",", ":")
    ).encode()
    return hmac.new(CONTENT_SIGNING_KEY, canonical, hashlib.sha256).hexdigest()


def test_manifest_is_signed():
    m = client.get("/content/manifest").json()
    assert m["signature_algorithm"] == "HMAC-SHA256"
    assert len(m["signature"]) == 64
    signature = m.pop("signature")
    assert _recompute(m) == signature


def test_tampering_breaks_signature():
    m = client.get("/content/manifest").json()
    signature = m.pop("signature")
    # Tamper with a file hash — the recomputed signature must no longer match.
    m["files"]["catalog"]["sha256"] = "0" * 64
    assert _recompute(m) != signature


def test_signature_covers_versions():
    m = client.get("/content/manifest").json()
    signature = m.pop("signature")
    m["protocol_version"] = "9.9.9-forged"
    assert _recompute(m) != signature
