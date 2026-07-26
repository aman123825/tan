"""Psychometric fit and signal-detection measures (Python mirror).

Mirror of ``apps/flutter_app/lib/core/psychometrics.dart`` — the logistic
psychometric-function fit (deterministic coarse-to-fine ML grid search),
m-AFC d' (Hacker & Ratcliff, 1979), and the intraclass correlation
coefficients ICC(2,1) / ICC(3,1) for test–retest reliability (Shrout &
Fleiss, 1979; McGraw & Wong, 1996). Kept dependency-free (no numpy/scipy) so
the two implementations stay comparable line-for-line and are pinned by shared
golden values (``tests/test_psychometrics.py`` and the Dart harness).

Research summaries — never a diagnosis.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List, Optional, Sequence


def normal_pdf(z: float) -> float:
    return math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi)


def normal_cdf(z: float) -> float:
    """Standard normal CDF via Abramowitz & Stegun 7.1.26 (|err| < 1.5e-7).

    Deliberately the same approximation as the Dart mirror (not math.erf) so
    both sides produce bit-comparable values.
    """
    t = z / math.sqrt(2)
    x = abs(t)
    u = 1 / (1 + 0.3275911 * x)
    poly = u * (
        0.254829592
        + u * (-0.284496736 + u * (1.421413741 + u * (-1.453152027 + u * 1.061405429)))
    )
    erf = 1 - poly * math.exp(-x * x)
    signed = -erf if t < 0 else erf
    return 0.5 * (1 + signed)


def pc_from_dprime(d_prime: float, m: int) -> float:
    """Proportion correct for an unbiased m-AFC observer with sensitivity d'."""
    if m < 2:
        raise ValueError(f"m-AFC needs m >= 2, got {m}")
    lo, hi, n = -8.0, 8.0, 1600  # Simpson's rule, step 0.01
    h = (hi - lo) / n

    def f(z: float) -> float:
        return normal_pdf(z - d_prime) * normal_cdf(z) ** (m - 1)

    total = f(lo) + f(hi)
    for i in range(1, n):
        total += f(lo + i * h) * (2 if i % 2 == 0 else 4)
    return min(1.0, max(0.0, total * h / 3))


def dprime_from_pc(pc: float, m: int) -> Optional[float]:
    """Sensitivity d' from proportion correct on an m-AFC task (bisection)."""
    chance = 1 / m
    if pc <= chance + 1e-3 or pc >= 0.999:
        return None
    lo, hi = 0.0, 10.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if pc_from_dprime(mid, m) < pc:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


@dataclass(frozen=True)
class LogisticFit:
    alpha: float
    beta: float
    gamma: float
    lambda_: float
    target_proportion: float
    threshold: Optional[float]
    n_trials: int

    def probability_at(self, x: float) -> float:
        return self.gamma + (1 - self.gamma - self.lambda_) / (
            1 + math.exp(-self.beta * (x - self.alpha))
        )


def _neg_log_likelihood(
    x: Sequence[float],
    correct: Sequence[bool],
    alpha: float,
    beta: float,
    gamma: float,
    lambda_: float,
) -> float:
    nll = 0.0
    for xi, ci in zip(x, correct):
        p = gamma + (1 - gamma - lambda_) / (1 + math.exp(-beta * (xi - alpha)))
        p = min(1 - 1e-6, max(1e-6, p))
        nll -= math.log(p) if ci else math.log(1 - p)
    return nll


def fit_logistic(
    x: List[float],
    correct: List[bool],
    *,
    guess_rate: float,
    lapse_rate: float = 0.02,
    target_proportion: float = 0.707,
) -> Optional[LogisticFit]:
    """Deterministic coarse-to-fine ML fit; mirrors ``fitLogistic`` in Dart."""
    if len(x) != len(correct) or len(x) < 8:
        return None
    x_min, x_max = min(x), max(x)
    rng = x_max - x_min
    if rng <= 0:
        return None
    if not any(correct) or all(correct):
        return None

    best_alpha = (x_min + x_max) / 2
    best_beta = 2 / rng
    best_nll = math.inf

    alpha_lo, alpha_hi = x_min - rng * 0.25, x_max + rng * 0.25
    beta_lo, beta_hi = 0.1 / rng, 50 / rng
    for _round in range(3):
        steps = 24
        log_beta_lo, log_beta_hi = math.log(beta_lo), math.log(beta_hi)
        for i in range(steps + 1):
            a = alpha_lo + (alpha_hi - alpha_lo) * i / steps
            for j in range(steps + 1):
                b = math.exp(log_beta_lo + (log_beta_hi - log_beta_lo) * j / steps)
                nll = _neg_log_likelihood(x, correct, a, b, guess_rate, lapse_rate)
                if nll < best_nll:
                    best_nll, best_alpha, best_beta = nll, a, b
        a_span = (alpha_hi - alpha_lo) / steps * 2
        alpha_lo, alpha_hi = best_alpha - a_span, best_alpha + a_span
        beta_lo, beta_hi = best_beta / 2.5, best_beta * 2.5

    threshold: Optional[float] = None
    sigma = (target_proportion - guess_rate) / (1 - guess_rate - lapse_rate)
    if 0 < sigma < 1:
        threshold = best_alpha + math.log(sigma / (1 - sigma)) / best_beta

    return LogisticFit(
        alpha=best_alpha,
        beta=best_beta,
        gamma=guess_rate,
        lambda_=lapse_rate,
        target_proportion=target_proportion,
        threshold=threshold,
        n_trials=len(x),
    )


def _icc_mean_squares(
    data: Sequence[Sequence[float]],
) -> Optional[tuple]:
    """Two-way ANOVA mean squares (MSR, MSC, MSE) for an n×k score matrix.

    Returns None when the matrix is smaller than 2×2 or ragged.
    """
    n = len(data)
    if n < 2:
        return None
    k = len(data[0])
    if k < 2:
        return None
    if any(len(row) != k for row in data):
        return None
    grand = sum(v for row in data for v in row) / (n * k)
    row_means = [sum(row) / k for row in data]
    col_means = [sum(data[i][j] for i in range(n)) / n for j in range(k)]
    ssr = sum((m - grand) ** 2 for m in row_means)
    ssc = sum((m - grand) ** 2 for m in col_means)
    sse = sum(
        (data[i][j] - row_means[i] - col_means[j] + grand) ** 2
        for i in range(n)
        for j in range(k)
    )
    msr = k * ssr / (n - 1)
    msc = n * ssc / (k - 1)
    mse = sse / ((n - 1) * (k - 1))
    return msr, msc, mse


def icc21(data: Sequence[Sequence[float]]) -> Optional[float]:
    """ICC(2,1): two-way random effects, absolute agreement, single measure.

    ``data`` is an n-subjects × k-occasions matrix (each row one subject's
    scores on the same test, in occasion order). Returns None for a matrix
    smaller than 2×2, ragged rows, or zero variance.
    """
    ms = _icc_mean_squares(data)
    if ms is None:
        return None
    msr, msc, mse = ms
    n, k = len(data), len(data[0])
    denom = msr + (k - 1) * mse + k * (msc - mse) / n
    if abs(denom) < 1e-12:
        return None
    return (msr - mse) / denom


def icc31(data: Sequence[Sequence[float]]) -> Optional[float]:
    """ICC(3,1): two-way mixed effects, consistency, single measure.

    Same input and degeneracy rules as :func:`icc21`.
    """
    ms = _icc_mean_squares(data)
    if ms is None:
        return None
    msr, _msc, mse = ms
    k = len(data[0])
    denom = msr + (k - 1) * mse
    if abs(denom) < 1e-12:
        return None
    return (msr - mse) / denom
