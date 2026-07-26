/// Advanced psychoacoustic stimuli + sessions (pure Dart, Flutter-free):
/// the multi-rate temporal modulation transfer function (TMTF), spectral
/// ripple discrimination, and iterated rippled noise (IRN) pitch strength.
///
/// * **TMTF** — modulation-detection thresholds measured at several rates
///   (4–512 Hz) with an abbreviated staircase per rate; plotting threshold
///   against rate traces the listener's temporal envelope filter
///   (Viemeister, 1979; Bacon & Viemeister, 1985).
/// * **Spectral ripple** — 3AFC oddball: two noises with the same sinusoidal
///   log-frequency spectral envelope, one with the envelope phase inverted;
///   the adapted parameter is the ripple period in octaves (smaller period =
///   denser ripples = harder; report 1/period ripples-per-octave — cf. Won,
///   Drennan & Rubinstein, 2007).
/// * **IRN** — delay-and-add noise: each iteration deepens the temporal
///   regularity at 1/delay, strengthening the perceived pitch (Yost, 1996).
///   2AFC: pick the interval with a pitch-like quality vs plain noise; the
///   adapted parameter is the iteration count.
///
/// SAFETY: every staircase adapts a stimulus parameter (depth, period,
/// iterations) — never master volume. Deterministic for a given seed.
library;

import 'dart:math';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';

// ---------------------------------------------------------------------------
// TMTF (A9)
// ---------------------------------------------------------------------------

/// The TMTF measurement rates (Hz), low → high.
const List<double> kTmtfRatesHz = <double>[4, 8, 32, 128, 512];

/// Abbreviated per-rate modulation staircase (6 reversals, Levitt reduction)
/// so the five-rate curve stays a single-sitting session.
AdaptiveTrack tmtfTrack() => AdaptiveTrack(
      value: -4,
      min: -40,
      max: 0,
      step: 4,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 2,
      stopReversals: 6,
      thresholdReversals: 4,
    );

/// Builds one 3AFC TMTF trial: three noise bursts, the target amplitude-
/// modulated at [rateHz] with depth [depthDb], the others steady.
List<double> buildTmtfSequence({
  required int targetInterval,
  required double depthDb,
  required double rateHz,
  required int seed,
  double intervalSeconds = 0.5,
  double gapSeconds = 0.25,
  int sampleRate = kSampleRate,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < 3; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    if (i == targetInterval) {
      parts.add(amNoise(
        seconds: intervalSeconds,
        rateHz: rateHz,
        depthDb: depthDb,
        seed: seed * 10 + i,
        sampleRate: sampleRate,
      ));
    } else {
      parts.add(whiteNoise(
        seconds: intervalSeconds,
        seed: seed * 10 + i,
        sampleRate: sampleRate,
      ));
    }
  }
  return concat(parts);
}

/// Sequences the whole TMTF: one abbreviated modulation staircase per rate
/// in [kTmtfRatesHz] order, 3AFC per trial.
class TmtfSession {
  TmtfSession({
    this.moduleId = 'auditory',
    this.groupId = 'tmtf',
    this.maxTrialsPerRate = 18,
    List<double>? rates,
  }) : rates = rates ?? kTmtfRatesHz {
    for (final r in this.rates) {
      _tracks[r] = tmtfTrack();
      _trialCounts[r] = 0;
    }
  }

  final String moduleId;
  final String groupId;
  final int maxTrialsPerRate;
  final List<double> rates;

  final Map<double, AdaptiveTrack> _tracks = <double, AdaptiveTrack>{};
  final Map<double, int> _trialCounts = <double, int>{};
  final List<TrialRecord> records = <TrialRecord>[];

  int _rateIndex = 0;

  bool get isComplete => _rateIndex >= rates.length;
  double get currentRateHz => rates[_rateIndex.clamp(0, rates.length - 1)];
  AdaptiveTrack get _track => _tracks[currentRateHz]!;

  /// Modulation depth (dB) of the next presentation at the current rate.
  double get currentDepthDb => _track.value;

  int get completedTrials => records.length;
  int get trialNumber => records.length + 1;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// 1-based index of the rate currently being measured (for progress UI).
  int get rateNumber => (_rateIndex + 1).clamp(1, rates.length);

  bool submit(int targetInterval, int chosenInterval, {int latencyMs = 0}) {
    if (isComplete) return false;
    final rate = currentRateHz;
    final correct = chosenInterval == targetInterval;
    records.add(TrialRecord(
      target: 'interval_${targetInterval + 1}',
      response: 'interval_${chosenInterval + 1}',
      correct: correct,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'depth_db': _track.value,
        'rate_hz': rate,
      },
    ));
    _track.submit(correct);
    _trialCounts[rate] = (_trialCounts[rate] ?? 0) + 1;
    if (_track.complete || _trialCounts[rate]! >= maxTrialsPerRate) {
      _rateIndex++;
    }
    return correct;
  }

  /// Depth threshold (dB) at [rateHz]; null while unmeasured/unconverged.
  double? thresholdFor(double rateHz) => _tracks[rateHz]?.threshold;

  /// Mean threshold across converged rates (the trend headline), or null.
  double? get meanThresholdDb {
    final t = <double>[
      for (final r in rates)
        if (thresholdFor(r) != null) thresholdFor(r)!,
    ];
    if (t.isEmpty) return null;
    return t.reduce((a, b) => a + b) / t.length;
  }
}

// ---------------------------------------------------------------------------
// Spectral ripple (A10)
// ---------------------------------------------------------------------------

/// Ripple staircase over the ripple PERIOD in octaves (smaller = denser =
/// harder): 1.0 oct start (1 ripple/oct) down to 0.1 oct (10 ripples/oct).
AdaptiveTrack rippleTrack() => AdaptiveTrack(
      value: 1.0,
      min: 0.1,
      max: 2.0,
      step: 0.2,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 0.05,
    );

/// One rippled-noise burst: [components] log-spaced sinusoids 100–8000 Hz
/// whose amplitudes follow a sinusoidal envelope in log2 frequency with
/// period [periodOct] octaves and phase [ripplePhase]. Component phases come
/// from [seed] (shared across the intervals of a trial so ONLY the ripple
/// phase differs).
List<double> rippleStimulus({
  required double periodOct,
  required double ripplePhase,
  required int seed,
  double seconds = 0.35,
  int components = 160,
  double amp = 0.5,
  int sampleRate = kSampleRate,
}) {
  final rng = Random(seed);
  final phases =
      List<double>.generate(components, (_) => rng.nextDouble() * 2 * pi);
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0);
  const loHz = 100.0, hiHz = 8000.0;
  final octaves = log(hiHz / loHz) / ln2;
  final density = 1 / periodOct; // ripples per octave
  for (var c = 0; c < components; c++) {
    final oct = octaves * c / (components - 1);
    final f = loHz * pow(2, oct);
    // Envelope in [0.05, 1]: full-depth sinusoidal ripple on a log-f grid.
    final a =
        0.525 + 0.475 * sin(2 * pi * density * oct + ripplePhase);
    final w = 2 * pi * f / sampleRate;
    for (var i = 0; i < n; i++) {
      out[i] += a * sin(w * i + phases[c]);
    }
  }
  // Peak-normalize to [amp], then raised-cosine fades against clicks.
  var peak = 0.0;
  for (final v in out) {
    final x = v.abs();
    if (x > peak) peak = x;
  }
  if (peak > 0) {
    final k = amp / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  final fade = (0.008 * sampleRate).round().clamp(0, n ~/ 2);
  for (var i = 0; i < fade; i++) {
    final g = 0.5 * (1 - cos(pi * i / fade));
    out[i] *= g;
    out[n - 1 - i] *= g;
  }
  return out;
}

/// Builds one 3AFC ripple trial: two standard-phase ripples and one inverted
/// (the target), all sharing component phases.
List<double> buildRippleOddballSequence({
  required int targetInterval,
  required double periodOct,
  required int seed,
  double gapSeconds = 0.25,
  int sampleRate = kSampleRate,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < 3; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    parts.add(rippleStimulus(
      periodOct: periodOct,
      ripplePhase: i == targetInterval ? pi : 0,
      seed: seed, // shared → only the ripple phase differs
      sampleRate: sampleRate,
    ));
  }
  return concat(parts);
}

// ---------------------------------------------------------------------------
// Iterated rippled noise (A11)
// ---------------------------------------------------------------------------

/// IRN staircase over the iteration count (fewer = weaker pitch = harder).
AdaptiveTrack irnTrack() => AdaptiveTrack(
      value: 8,
      min: 1,
      max: 16,
      step: 2,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 1,
    );

/// Iterated rippled noise: [iterations] rounds of delay-and-add with delay
/// `1/pitchHz` produce a pitch at [pitchHz] whose salience grows with the
/// iteration count. RMS-matched to the seeded source noise.
List<double> irnStimulus({
  required int iterations,
  double pitchHz = 125,
  required int seed,
  double seconds = 0.4,
  double amp = 0.2,
  int sampleRate = kSampleRate,
}) {
  var x = whiteNoise(
      seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
  final refRms = rms(x);
  final delay = max(1, (sampleRate / pitchHz).round());
  for (var it = 0; it < iterations; it++) {
    final next = List<double>.of(x);
    for (var i = delay; i < next.length; i++) {
      next[i] += x[i - delay];
    }
    x = next;
    // Re-normalize each round so level stays constant while regularity grows.
    final r = rms(x);
    if (r > 0) {
      final k = refRms / r;
      for (var i = 0; i < x.length; i++) {
        x[i] *= k;
      }
    }
  }
  return x;
}

/// Builds one 2AFC IRN trial: one interval plain noise, the target IRN with
/// [iterations] (rounded from the continuous staircase value).
List<double> buildIrnSequence({
  required int targetInterval,
  required double iterations,
  required int seed,
  double gapSeconds = 0.3,
  int sampleRate = kSampleRate,
}) {
  final n = iterations.round().clamp(1, 16);
  final parts = <List<double>>[];
  for (var i = 0; i < 2; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    if (i == targetInterval) {
      parts.add(irnStimulus(
          iterations: n, seed: seed * 7 + 1, sampleRate: sampleRate));
    } else {
      parts.add(whiteNoise(
          seconds: 0.4, seed: seed * 7 + 2, sampleRate: sampleRate));
    }
  }
  return concat(parts);
}
