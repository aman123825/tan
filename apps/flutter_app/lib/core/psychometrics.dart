/// Psychometric-function fit and signal-detection measures (pure Dart).
///
/// Two research-standard analyses computed from a session's per-trial data:
///
/// 1. **Logistic psychometric fit** — maximum-likelihood fit of
///    `P(correct | x) = γ + (1 − γ − λ)·σ(β(x − α))` to the (parameter,
///    correct) pairs of an adaptive run, with the guess rate γ fixed at the
///    task's chance level (1/n for nAFC) and a small fixed lapse rate λ.
///    Reports the threshold (the parameter value at the staircase's target
///    proportion), the slope β, and the fitted curve. The fit is a
///    deterministic coarse-to-fine grid search (no RNG), so results are
///    reproducible bit-for-bit.
///
/// 2. **d′ for n-alternative forced choice** — sensitivity from proportion
///    correct via the standard m-AFC observer model
///    `pc(d′) = ∫ φ(z − d′)·Φ(z)^(m−1) dz` (Hacker & Ratcliff, 1979; Green &
///    Swets, 1966), inverted numerically. For m = 2 this reduces to
///    `pc = Φ(d′/√2)`.
///
/// 3. **Intraclass correlation coefficients** — test–retest reliability from
///    an n-subjects × k-occasions score matrix via the two-way ANOVA mean
///    squares (Shrout & Fleiss, 1979; McGraw & Wong, 1996): ICC(2,1)
///    (two-way random effects, absolute agreement, single measurement) and
///    ICC(3,1) (two-way mixed effects, consistency, single measurement).
///
/// Mirrored in `packages/protocol_engine/psychometrics.py` and pinned by
/// shared golden values (`tool/verify/psychometrics_harness.dart`,
/// `tests/test_psychometrics.py`). Research summaries — never a diagnosis.
library;

import 'dart:math' as math;

/// Standard normal probability density.
double normalPdf(double z) =>
    math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi);

/// Standard normal CDF via the Abramowitz & Stegun 7.1.26 erf approximation
/// (|error| < 1.5e-7) — deterministic and dependency-free.
double normalCdf(double z) {
  final t = z / math.sqrt2;
  final x = t.abs();
  final u = 1 / (1 + 0.3275911 * x);
  final poly = u *
      (0.254829592 +
          u *
              (-0.284496736 +
                  u * (1.421413741 + u * (-1.453152027 + u * 1.061405429))));
  final erf = 1 - poly * math.exp(-x * x);
  final signed = t < 0 ? -erf : erf;
  return 0.5 * (1 + signed);
}

/// Proportion correct for an unbiased m-AFC observer with sensitivity
/// [dPrime]: `∫ φ(z − d′)·Φ(z)^(m−1) dz` (Simpson's rule over z ∈ [−8, 8]).
double pcFromDPrime(double dPrime, int m) {
  if (m < 2) throw ArgumentError('m-AFC needs m >= 2, got $m');
  const lo = -8.0, hi = 8.0;
  const n = 1600; // even; step 0.01
  const h = (hi - lo) / n;
  double f(double z) =>
      normalPdf(z - dPrime) * math.pow(normalCdf(z), m - 1).toDouble();
  var sum = f(lo) + f(hi);
  for (var i = 1; i < n; i++) {
    sum += f(lo + i * h) * (i.isEven ? 2 : 4);
  }
  return (sum * h / 3).clamp(0.0, 1.0);
}

/// Sensitivity d′ from proportion correct [pc] on an m-AFC task, by bisection
/// on [pcFromDPrime]. Returns null when [pc] is at/below chance (1/m) or too
/// close to 1 for a stable estimate.
double? dPrimeFromPc(double pc, int m) {
  final chance = 1 / m;
  if (pc <= chance + 1e-3 || pc >= 0.999) return null;
  var lo = 0.0, hi = 10.0;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (pcFromDPrime(mid, m) < pc) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// The result of a logistic psychometric-function fit.
class LogisticFit {
  const LogisticFit({
    required this.alpha,
    required this.beta,
    required this.gamma,
    required this.lambda,
    required this.targetProportion,
    required this.threshold,
    required this.nTrials,
  });

  /// Inflection point (parameter value at the halfway proportion).
  final double alpha;

  /// Slope (per parameter unit; positive = higher parameter is easier).
  final double beta;

  /// Guess rate (chance floor, fixed at 1/n for an nAFC task).
  final double gamma;

  /// Fixed lapse rate.
  final double lambda;

  /// The proportion the threshold is read at (e.g. 0.707 for 2-down/1-up).
  final double targetProportion;

  /// Parameter value where the fitted curve crosses [targetProportion], or
  /// null when that proportion is outside the curve's asymptotes.
  final double? threshold;

  final int nTrials;

  /// The fitted proportion correct at parameter value [x].
  double probabilityAt(double x) =>
      gamma + (1 - gamma - lambda) / (1 + math.exp(-beta * (x - alpha)));
}

double _negLogLikelihood(
  List<double> x,
  List<bool> correct,
  double alpha,
  double beta,
  double gamma,
  double lambda,
) {
  var nll = 0.0;
  for (var i = 0; i < x.length; i++) {
    var p = gamma + (1 - gamma - lambda) / (1 + math.exp(-beta * (x[i] - alpha)));
    p = p.clamp(1e-6, 1 - 1e-6);
    nll -= correct[i] ? math.log(p) : math.log(1 - p);
  }
  return nll;
}

/// Fits the logistic psychometric function to per-trial data by maximum
/// likelihood over a deterministic coarse-to-fine grid.
///
/// [x] is the adapted parameter at each trial (staircase trajectory) and
/// [correct] the per-trial outcome. [guessRate] is the task's chance level
/// (1/n for nAFC). [targetProportion] is where the threshold is read
/// (defaults to the 2-down/1-up point, ≈ 0.707). Assumes a larger parameter
/// makes the task easier — true for every staircase in this app (bigger gap /
/// delta / SNR). Returns null when there are fewer than 8 usable trials, no
/// spread in [x], or all-correct / all-wrong outcomes (nothing to fit).
LogisticFit? fitLogistic(
  List<double> x,
  List<bool> correct, {
  required double guessRate,
  double lapseRate = 0.02,
  double targetProportion = 0.707,
}) {
  if (x.length != correct.length || x.length < 8) return null;
  final xMin = x.reduce(math.min), xMax = x.reduce(math.max);
  final range = xMax - xMin;
  if (range <= 0) return null;
  final anyCorrect = correct.any((c) => c);
  final anyWrong = correct.any((c) => !c);
  if (!anyCorrect || !anyWrong) return null;

  var bestAlpha = (xMin + xMax) / 2;
  var bestBeta = 2 / range;
  var bestNll = double.infinity;

  var alphaLo = xMin - range * 0.25, alphaHi = xMax + range * 0.25;
  var betaLo = 0.1 / range, betaHi = 50 / range;
  for (var round = 0; round < 3; round++) {
    const steps = 24;
    final logBetaLo = math.log(betaLo), logBetaHi = math.log(betaHi);
    for (var i = 0; i <= steps; i++) {
      final a = alphaLo + (alphaHi - alphaLo) * i / steps;
      for (var j = 0; j <= steps; j++) {
        final b =
            math.exp(logBetaLo + (logBetaHi - logBetaLo) * j / steps);
        final nll = _negLogLikelihood(x, correct, a, b, guessRate, lapseRate);
        if (nll < bestNll) {
          bestNll = nll;
          bestAlpha = a;
          bestBeta = b;
        }
      }
    }
    // Narrow the grid around the current best for the next round.
    final aSpan = (alphaHi - alphaLo) / steps * 2;
    alphaLo = bestAlpha - aSpan;
    alphaHi = bestAlpha + aSpan;
    betaLo = bestBeta / 2.5;
    betaHi = bestBeta * 2.5;
  }

  // Threshold: x where the curve crosses the target proportion.
  double? threshold;
  final sigma = (targetProportion - guessRate) / (1 - guessRate - lapseRate);
  if (sigma > 0 && sigma < 1) {
    threshold = bestAlpha + math.log(sigma / (1 - sigma)) / bestBeta;
  }

  return LogisticFit(
    alpha: bestAlpha,
    beta: bestBeta,
    gamma: guessRate,
    lambda: lapseRate,
    targetProportion: targetProportion,
    threshold: threshold,
    nTrials: x.length,
  );
}

/// Two-way ANOVA mean squares for an n×k score matrix: (MSR, MSC, MSE).
/// Returns null when the matrix is smaller than 2×2 or ragged.
(double, double, double)? _iccMeanSquares(List<List<double>> data) {
  final n = data.length;
  if (n < 2) return null;
  final k = data.first.length;
  if (k < 2) return null;
  for (final row in data) {
    if (row.length != k) return null;
  }
  var grand = 0.0;
  for (final row in data) {
    for (final v in row) {
      grand += v;
    }
  }
  grand /= n * k;
  final rowMeans = <double>[
    for (final row in data) row.reduce((a, b) => a + b) / k,
  ];
  final colMeans = List<double>.filled(k, 0);
  for (final row in data) {
    for (var j = 0; j < k; j++) {
      colMeans[j] += row[j] / n;
    }
  }
  var ssr = 0.0, ssc = 0.0, sse = 0.0;
  for (var i = 0; i < n; i++) {
    ssr += (rowMeans[i] - grand) * (rowMeans[i] - grand);
    for (var j = 0; j < k; j++) {
      final resid = data[i][j] - rowMeans[i] - colMeans[j] + grand;
      sse += resid * resid;
    }
  }
  for (var j = 0; j < k; j++) {
    ssc += (colMeans[j] - grand) * (colMeans[j] - grand);
  }
  final msr = k * ssr / (n - 1);
  final msc = n * ssc / (k - 1);
  final mse = sse / ((n - 1) * (k - 1));
  return (msr, msc, mse);
}

/// ICC(2,1): two-way random effects, absolute agreement, single measurement
/// (Shrout & Fleiss, 1979) — the standard test–retest reliability coefficient
/// when systematic session-to-session shifts should count against agreement.
///
/// [data] is an n-subjects × k-occasions matrix (each row one subject's scores
/// on the same test, in occasion order). Returns null for a matrix smaller
/// than 2×2, ragged rows, or zero variance (nothing to apportion).
double? icc21(List<List<double>> data) {
  final ms = _iccMeanSquares(data);
  if (ms == null) return null;
  final (msr, msc, mse) = ms;
  final n = data.length, k = data.first.length;
  final denom = msr + (k - 1) * mse + k * (msc - mse) / n;
  if (denom.abs() < 1e-12) return null;
  return (msr - mse) / denom;
}

/// ICC(3,1): two-way mixed effects, consistency, single measurement —
/// reliability when systematic occasion shifts (e.g. practice effects) are
/// excluded and only relative agreement matters. Same input/degeneracy rules
/// as [icc21].
double? icc31(List<List<double>> data) {
  final ms = _iccMeanSquares(data);
  if (ms == null) return null;
  final (msr, _, mse) = ms;
  final k = data.first.length;
  final denom = msr + (k - 1) * mse;
  if (denom.abs() < 1e-12) return null;
  return (msr - mse) / denom;
}
