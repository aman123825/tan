"""Golden-vector test for the deterministic staircase.

Pins the exact trajectory of the real Python `snr_staircase` for a fixed
response sequence. The identical numbers are asserted by the Dart engine
harness (`apps/flutter_app/tool/verify/engine_harness.dart`), which proves the
Dart `AdaptiveTrack` is behaviourally equivalent to the Python `Staircase`.

If the engine's adaptation logic ever drifts, this test (and the Dart harness)
fail — the deterministic core is intentionally locked.
"""
from packages.protocol_engine.engine import (
    snr_staircase,
    gap_staircase,
    frequency_staircase,
    Staircase,
)

# Fixed response sequence (True = correct).
SEQ = [
    True, True, True, True, True, True, False, True, True, False,
    False, True, True, False, True, True, False, False, True, True,
    False, True, True, False,
]
GOLDEN_TRAJ = [
    12, 10, 10, 8, 8, 6, 8, 8, 6, 8,
    10, 10, 8, 10, 10, 8, 10, 12, 12, 10,
    12, 12, 10, 12,
]
GOLDEN_REVERSALS = [6, 8, 6, 10, 8, 10, 8, 12, 10, 12, 10]
GOLDEN_THRESHOLD = 62 / 6


def test_snr_staircase_golden_trajectory():
    s = snr_staircase()
    traj = [s.submit(c) for c in SEQ]
    assert traj == GOLDEN_TRAJ
    assert s.reversals == GOLDEN_REVERSALS
    assert s.complete is True
    assert s.trials == len(SEQ)
    assert abs(s.threshold() - GOLDEN_THRESHOLD) < 1e-9
    assert abs(s.threshold_sd() - 1.3743685419) < 1e-9  # reversal SD (precision)


def test_two_down_one_up_semantics():
    # Two correct answers make the task harder (value down by step); one wrong
    # answer makes it easier (value up by step). Never the reverse.
    s = snr_staircase()
    assert s.submit(True) == 12   # first correct: no move
    assert s.submit(True) == 10   # second correct: harder (down)
    assert s.submit(False) == 12  # wrong: easier (up), reversal recorded
    assert s.reversals == [10]



# --- Levitt step-size reduction (gap staircase: step 4 -> 1 over 2 reversals) ---
GAP_TRAJ = [
    20, 16, 16, 12, 12, 8, 10, 10, 9, 10,
    11, 11, 10, 11, 11, 10, 11, 12, 12, 11,
    12, 12, 11, 12,
]
GAP_REVERSALS = [8, 10, 9, 11, 10, 11, 10, 12, 11, 12, 11]
GAP_THRESHOLD = 67 / 6  # mean of the last 6 (fine-step) reversals


def test_gap_staircase_step_reduction_golden():
    g = gap_staircase()
    traj = [g.submit(c) for c in SEQ]
    assert traj == GAP_TRAJ
    assert g.reversals == GAP_REVERSALS
    assert g.complete is True
    assert abs(g.threshold() - GAP_THRESHOLD) < 1e-9
    assert abs(g.threshold_sd() - 0.6871842709) < 1e-9  # threshold precision
    # Step shrank from the initial 4 ms to its 1 ms floor (Levitt, 1971).
    assert g.current_step == 1


def test_frequency_staircase_reduction():
    f = frequency_staircase()
    assert f.submit(True) == 6   # first correct: no move
    assert f.submit(True) == 4   # second correct: harder, down by initial step 2
    assert f.submit(False) == 5  # wrong: easier, up by reduced step 1


def test_target_proportions_match_levitt():
    # n-down/1-up converges on P = 0.5**(1/n) correct (Levitt, 1971, Table II).
    assert abs(snr_staircase().target_proportion - 0.5 ** 0.5) < 1e-9  # 0.707
    three_down = Staircase(0, -9, 9, 1, "down", rule_correct=3)
    assert abs(three_down.target_proportion - 0.5 ** (1 / 3)) < 1e-9  # 0.794
