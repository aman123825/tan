"""Explainable-recommender tests.

The recommender is advisory and rules-first: it suggests what to train next,
always with a human-readable reason and a confidence, and it can never alter
locked assessment scoring or raise master volume.
"""
from ml.recommender import recommend

ALLOWED_KEYS = {"group_id", "module_id", "reason", "confidence", "parameters"}


def _trials(module, group, *, n, correct, fatigue=0, replay=0):
    return [
        {
            "module_id": module,
            "group_id": group,
            "correct": correct,
            "fatigue_after": fatigue,
            "replay_count": replay,
        }
        for _ in range(n)
    ]


def _assert_explainable(rec):
    assert set(rec).issubset(ALLOWED_KEYS), rec
    assert rec["reason"], "recommendation must carry a human-readable reason"
    assert 0.0 <= rec["confidence"] <= 1.0
    # Advisory only: never an instruction that raises master volume.
    assert not any("volume" in str(k).lower() for k in rec.get("parameters", {}))


def test_empty_history_gives_gentle_baseline():
    rec = recommend([])
    assert rec["group_id"] == "sentence_noise"
    assert rec["parameters"]["mode"] == "training"
    _assert_explainable(rec)


def test_high_fatigue_recommends_shorter_easier_block():
    rec = recommend(_trials("noise", "sentence_noise", n=5, correct=1, fatigue=8))
    # Fatigue takes priority over accuracy and steers to an easier, shorter task.
    assert rec["parameters"].get("difficulty") == "easy"
    assert rec["confidence"] >= 0.8
    _assert_explainable(rec)


def test_weak_area_reduces_complexity_without_volume():
    rec = recommend(_trials("noise", "initial_consonant_noise", n=10, correct=0, fatigue=2))
    assert rec["group_id"] == "initial_consonant_noise"
    assert rec["parameters"]["difficulty_delta"] == -1
    _assert_explainable(rec)


def test_untried_domain_is_explored_when_performance_is_ok():
    # Strong performance in one practiced area, low fatigue -> collect a baseline
    # in an unmeasured domain.
    rec = recommend(_trials("foundation", "word", n=8, correct=1, fatigue=1))
    assert (rec["module_id"], rec["group_id"]) in {
        ("auditory", "gap"),
        ("auditory", "modulation_depth"),
        ("noise", "sentence_noise"),
        ("assessment", "cognition_battery"),
    }
    _assert_explainable(rec)


def test_stable_performance_continues_adaptive_sin():
    trials = []
    for module, group in [
        ("auditory", "gap"),
        ("auditory", "modulation_depth"),
        ("noise", "sentence_noise"),
        ("assessment", "cognition_battery"),
    ]:
        trials += _trials(module, group, n=5, correct=1, fatigue=1)
    rec = recommend(trials)
    assert rec["group_id"] == "sentence_noise"
    assert rec["confidence"] == 0.72
    _assert_explainable(rec)


def test_all_branches_are_explainable_and_advisory():
    cases = [
        [],
        _trials("noise", "sentence_noise", n=3, correct=1, fatigue=9),
        _trials("noise", "vowel_noise", n=12, correct=0, fatigue=1),
        _trials("foundation", "word", n=6, correct=1, fatigue=0),
    ]
    for trials in cases:
        _assert_explainable(recommend(trials))
