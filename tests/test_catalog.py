"""Catalog integrity tests.

These pin the structural contract that the Flutter typed models
(`apps/flutter_app/lib/models/catalog.dart`) and the deterministic engine rely
on. They intentionally mirror the headless Dart harness
(`apps/flutter_app/tool/verify/catalog_harness.dart`) so both languages assert
the same invariants.
"""
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
WORKFLOW = ["introduction", "preview", "training", "test", "results"]


def load_catalog():
    return json.loads((ROOT / "protocols/catalog.json").read_text())


def app_catalog_copy():
    return json.loads(
        (ROOT / "apps/flutter_app/assets/protocols/catalog.json").read_text()
    )


def test_document_level_contract():
    c = load_catalog()
    assert c["schema_version"]
    assert c["product"] == "HearBloom"
    assert c["status"] == "research_specification"
    assert len(c["modules"]) == 9
    assert sum(len(m["groups"]) for m in c["modules"]) == 56


def test_every_group_is_well_formed_and_unvalidated():
    c = load_catalog()
    seen_keys = set()
    for m in c["modules"]:
        assert m["id"] and m["name"], "module needs id and name"
        assert isinstance(m.get("audience", []), list)
        ids_in_module = set()
        for g in m["groups"]:
            assert g["id"] and g["name"], f"group needs id/name in {m['id']}"
            assert g.get("protocol"), f"group {m['id']}/{g['id']} needs a protocol"
            assert g["modes"] == WORKFLOW, f"{m['id']}/{g['id']} workflow drift"
            # Research-only invariant: nothing is silently validated.
            assert g["validation_status"] == "unvalidated"
            assert g["id"] not in ids_in_module, "duplicate group id within module"
            ids_in_module.add(g["id"])
            seen_keys.add(f"{m['id']}/{g['id']}")
    assert len(seen_keys) == 56


def test_telephone_inherits_foundation():
    c = load_catalog()
    tel = next(m for m in c["modules"] if m["id"] == "telephone")
    assert tel["inherits"] == "foundation"
    assert tel["groups"] == []


def test_adaptive_sin_group_present_for_later_slices():
    c = load_catalog()
    noise = next(m for m in c["modules"] if m["id"] == "noise")
    sin = next(g for g in noise["groups"] if g["id"] == "sentence_noise")
    assert sin["protocol"] == "adaptive_snr_4afc"
    assert sin["parameters"]["step_db"] == 2


def test_app_asset_copy_matches_source_catalog():
    # The Flutter client ships its own copy under assets/. It must not drift
    # from the source-of-truth catalog the backend serves.
    assert load_catalog() == app_catalog_copy()
