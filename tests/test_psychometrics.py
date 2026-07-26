"""Golden tests for the psychometrics module (mirrored in Dart).

The same pinned values are asserted by
``apps/flutter_app/tool/verify/psychometrics_harness.dart`` — if either side
drifts, its suite fails.
"""
from packages.protocol_engine.psychometrics import (
    dprime_from_pc,
    fit_logistic,
    icc21,
    icc31,
    normal_cdf,
    pc_from_dprime,
)

# The shared golden staircase-style run (parameter value, correct) — arbitrary
# but FIXED; both language implementations must fit it identically.
GOLDEN_X = [12, 10, 8, 6, 4, 6, 4, 2, 4, 2, 3, 2, 3, 2, 3, 2, 1, 2, 1, 2]
GOLDEN_CORRECT = [
    True, True, True, True, False, True, True, False, True, False,
    True, False, True, True, False, True, False, True, False, True,
]


def test_normal_cdf_reference_points():
    assert abs(normal_cdf(0.0) - 0.5) < 1e-9
    assert abs(normal_cdf(1.0) - 0.8413447) < 2e-7
    assert abs(normal_cdf(-1.0) - 0.1586553) < 2e-7


def test_pc_from_dprime_matches_analytic_2afc():
    # 2AFC closed form: pc = Phi(d'/sqrt(2)) = 0.760250 for d' = 1.
    assert abs(pc_from_dprime(1.0, 2) - 0.7602499) < 1e-4


def test_pc_from_dprime_published_3afc():
    # Hacker & Ratcliff (1979) tables: d' = 1.0 -> pc ~= 0.6337 for 3AFC.
    assert abs(pc_from_dprime(1.0, 3) - 0.6337020) < 1e-4


def test_pc_from_dprime_golden_4afc():
    assert abs(pc_from_dprime(2.0, 4) - 0.8227929) < 1e-4


def test_dprime_inverts_pc():
    assert abs(dprime_from_pc(0.634, 3) - 1.0010300) < 1e-3
    # At/below chance or near-perfect: no stable estimate.
    assert dprime_from_pc(0.33, 3) is None
    assert dprime_from_pc(0.9999, 3) is None


def test_logistic_fit_golden_run():
    fit = fit_logistic(
        [float(v) for v in GOLDEN_X], GOLDEN_CORRECT, guess_rate=1 / 3
    )
    assert fit is not None
    assert abs(fit.alpha - 3.2152778) < 1e-5
    assert abs(fit.beta - 1.0375200) < 1e-5
    assert abs(fit.threshold - 3.5178188) < 1e-5
    assert abs(fit.probability_at(6.0) - 0.9459273) < 1e-5


def test_logistic_fit_refuses_degenerate_input():
    xs = [float(v) for v in GOLDEN_X]
    assert fit_logistic(xs, [True] * len(xs), guess_rate=1 / 3) is None
    assert fit_logistic(xs[:4], GOLDEN_CORRECT[:4], guess_rate=1 / 3) is None
    assert fit_logistic([2.0] * 10, GOLDEN_CORRECT[:10], guess_rate=1 / 3) is None


# Shared golden test–retest matrix (4 subjects × 2 occasions) — arbitrary but
# FIXED; the Dart harness pins the same ICC values.
GOLDEN_RETEST = [
    [10.0, 12.0],
    [14.0, 13.0],
    [18.0, 19.0],
    [22.0, 21.0],
]


def test_icc_golden_matrix():
    # Hand-computed via the Shrout & Fleiss (1979) mean squares:
    # MSR = 45.125, MSC = 0.125, MSE = 1.125.
    assert abs(icc21(GOLDEN_RETEST) - 0.9617486338797814) < 1e-9
    assert abs(icc31(GOLDEN_RETEST) - 0.9513513513513514) < 1e-9


def test_icc_agreement_not_above_consistency_with_offset():
    # A constant +2 offset on occasion 2 hurts absolute agreement, ICC(2,1),
    # but not consistency, ICC(3,1).
    shifted = [[a, b + 2.0] for a, b in GOLDEN_RETEST]
    assert icc21(shifted) < icc31(shifted)
    assert abs(icc31(shifted) - 1.0) < 1e-9 or icc31(shifted) <= 1.0


def test_icc_refuses_degenerate_input():
    assert icc21([[1.0, 2.0]]) is None  # one subject
    assert icc21([[1.0], [2.0]]) is None  # one occasion
    assert icc21([[1.0, 2.0], [3.0]]) is None  # ragged
    assert icc21([[5.0, 5.0], [5.0, 5.0]]) is None  # zero variance
    assert icc31([[5.0, 5.0], [5.0, 5.0]]) is None
