/// Timbre-discrimination training protocol logic (pure Dart, Flutter-free).
///
/// Four classic waveforms at the *same pitch* — sine, triangle, sawtooth,
/// square — are told apart in a four-alternative forced choice. Difficulty is
/// controlled by a spectral-morph parameter: as it rises, each waveform's
/// harmonic spectrum is blended toward the average spectrum of all four, so the
/// timbres become progressively *more similar* and harder to distinguish.
///
/// Adaptation changes only the spectral-morph amount, never master volume.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';

/// The four discriminable waveforms.
enum Waveform { sine, triangle, sawtooth, square }

extension WaveformInfo on Waveform {
  String get label => switch (this) {
        Waveform.sine => 'Sine',
        Waveform.triangle => 'Triangle',
        Waveform.sawtooth => 'Sawtooth',
        Waveform.square => 'Square',
      };
}

/// Number of harmonics used in the additive model.
const int _kHarmonics = 12;

/// Signed harmonic-amplitude series (index 0 = fundamental) for a waveform's
/// ideal Fourier expansion, truncated to [_kHarmonics].
List<double> _harmonicSeries(Waveform w) {
  final a = List<double>.filled(_kHarmonics, 0.0);
  for (var i = 0; i < _kHarmonics; i++) {
    final n = i + 1;
    switch (w) {
      case Waveform.sine:
        a[i] = n == 1 ? 1.0 : 0.0;
      case Waveform.sawtooth:
        a[i] = 1.0 / n;
      case Waveform.square:
        a[i] = n.isOdd ? 1.0 / n : 0.0;
      case Waveform.triangle:
        a[i] = n.isOdd ? (n % 4 == 1 ? 1.0 : -1.0) / (n * n) : 0.0;
    }
  }
  return a;
}

/// L1-normalized magnitude series (so blending across waveforms is fair).
List<double> _normalizedSeries(Waveform w) {
  final a = _harmonicSeries(w);
  var sum = 0.0;
  for (final v in a) {
    sum += v.abs();
  }
  if (sum <= 0) return a;
  return <double>[for (final v in a) v / sum];
}

/// The average (per-harmonic) normalized series across all four waveforms — the
/// "mean timbre" that every waveform is morphed toward at maximum difficulty.
List<double> _meanSeries() {
  final acc = List<double>.filled(_kHarmonics, 0.0);
  for (final w in Waveform.values) {
    final s = _normalizedSeries(w);
    for (var i = 0; i < _kHarmonics; i++) {
      acc[i] += s[i] / Waveform.values.length;
    }
  }
  return acc;
}

/// Synthesizes a [waveform] tone at [freqHz], with a spectral-morph [similarity]
/// in [0, 1] toward the mean timbre (0 = pure waveform, 1 = indistinguishable
/// mean). Peak-normalized so it never clips or changes level.
List<double> waveformTone(
  Waveform waveform,
  double freqHz, {
  double similarity = 0.0,
  double seconds = 0.5,
  double amp = 0.24,
  int sampleRate = kSampleRate,
}) {
  final pure = _normalizedSeries(waveform);
  final mean = _meanSeries();
  final s = similarity.clamp(0.0, 1.0);
  final blended = <double>[
    for (var i = 0; i < _kHarmonics; i++) (1 - s) * pure[i] + s * mean[i],
  ];
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0.0);
  for (var h = 0; h < _kHarmonics; h++) {
    final ah = blended[h];
    if (ah == 0) continue;
    final f = freqHz * (h + 1);
    if (f > sampleRate / 2) break;
    for (var i = 0; i < n; i++) {
      out[i] += ah * sin(2 * pi * f * i / sampleRate);
    }
  }
  // Raised-cosine fades + peak-normalize.
  final fade = (0.01 * sampleRate).round().clamp(1, n ~/ 2);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    if (i < fade) {
      out[i] *= i / fade;
    } else if (i >= n - fade) {
      out[i] *= (n - 1 - i) / fade;
    }
    if (out[i].abs() > peak) peak = out[i].abs();
  }
  if (peak > 0) {
    final k = amp / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  return out;
}

/// A single timbre-discrimination trial (4AFC).
class TimbreTrial {
  const TimbreTrial({
    required this.target,
    required this.choices,
    required this.targetIndex,
    required this.similarity,
  });

  final Waveform target;
  final List<Waveform> choices;
  final int targetIndex;

  /// Spectral-morph amount in effect (0 = distinct, 1 = identical). Higher is
  /// harder.
  final double similarity;

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic timbre-trial generator (all four waveforms as the choice set).
class TimbreGenerator {
  TimbreGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  TimbreTrial next(double similarity) {
    final choices = List<Waveform>.of(Waveform.values)..shuffle(_rng);
    final targetIndex = _rng.nextInt(choices.length);
    return TimbreTrial(
      target: choices[targetIndex],
      choices: choices,
      targetIndex: targetIndex,
      similarity: similarity,
    );
  }
}

/// Adaptive timbre-training session (20 trials by default).
///
/// A 2-down / 1-up staircase on the spectral-morph amount: two correct answers
/// push the timbres closer together (harder); one wrong answer separates them
/// (easier). Reports accuracy and the highest similarity reliably discriminated.
class TimbreSession {
  TimbreSession({
    this.maxTrials = 20,
    this.step = 0.08,
    this.startSimilarity = 0.0,
    this.maxSimilarity = 0.85,
  });

  final int maxTrials;
  final double step;
  final double startSimilarity;
  final double maxSimilarity;

  late double similarity = startSimilarity;

  int _correct = 0;
  int _completed = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _consecutiveCorrect = 0;
  double _maxSimilarityCorrect = 0;
  final List<bool> results = <bool>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get correctCount => _correct;
  int get currentStreak => _streak;
  int get bestStreak => _bestStreak;
  bool get isComplete => _completed >= maxTrials;
  double get accuracy => _completed == 0 ? 0 : _correct / _completed;
  int get percent => (accuracy * 100).round();

  /// Highest similarity (closest timbres) answered correctly — larger = better
  /// timbre discrimination.
  double get bestSimilarity => _maxSimilarityCorrect;

  bool submit(TimbreTrial trial, int chosenIndex) {
    final correct = trial.isCorrect(chosenIndex);
    _completed++;
    if (correct) {
      _correct++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      _consecutiveCorrect++;
      if (trial.similarity > _maxSimilarityCorrect) {
        _maxSimilarityCorrect = trial.similarity;
      }
      if (_consecutiveCorrect >= 2) {
        _consecutiveCorrect = 0;
        similarity = (similarity + step).clamp(0.0, maxSimilarity);
      }
    } else {
      _streak = 0;
      _consecutiveCorrect = 0;
      similarity = (similarity - step).clamp(0.0, maxSimilarity);
    }
    results.add(correct);
    return correct;
  }
}
