/// Binaural Fusion Test protocol logic (pure Dart).
///
/// A word is split spectrally: the low band (< ~1000 Hz) is sent to one ear and
/// the high band (> ~1000 Hz) to the other. Neither band is intelligible alone;
/// the listener must fuse the two ears centrally to identify the word from a
/// closed set. Reduced fusion is associated with brainstem binaural-integration
/// difficulty. Typical performance ≥ 70% (task-relative on uncalibrated audio).
///
/// Flutter-free so it can be unit-tested headlessly. Reuses the low-pass biquad
/// from [filtered_speech] and adds the complementary high-pass biquad.
library;

import 'dart:math';

import 'audio/pcm_synth.dart' show kSampleRate;
import 'filtered_speech.dart' show lowPassBiquad;
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Applies a second-order high-pass biquad at [cutoffHz] to [samples]
/// (Butterworth-Q by default). Complements [lowPassBiquad] so the two bands
/// sum back toward the original signal. A non-positive/oversized cutoff returns
/// the input unchanged.
List<double> highPassBiquad(
  List<double> samples,
  double cutoffHz, {
  int sampleRate = kSampleRate,
  double q = 0.70710678,
}) {
  if (samples.isEmpty) return List<double>.of(samples);
  if (cutoffHz <= 0 || cutoffHz >= sampleRate / 2) {
    return List<double>.of(samples);
  }
  final w0 = 2 * pi * cutoffHz / sampleRate;
  final cosw0 = cos(w0);
  final sinw0 = sin(w0);
  final alpha = sinw0 / (2 * q);

  final b0 = (1 + cosw0) / 2;
  final b1 = -(1 + cosw0);
  final b2 = (1 + cosw0) / 2;
  final a0 = 1 + alpha;
  final a1 = -2 * cosw0;
  final a2 = 1 - alpha;

  final out = List<double>.filled(samples.length, 0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final x0 = samples[i];
    final y0 = (b0 / a0) * x0 +
        (b1 / a0) * x1 +
        (b2 / a0) * x2 -
        (a1 / a0) * y1 -
        (a2 / a0) * y2;
    out[i] = y0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }
  return out;
}

/// Which ear receives the LOW band ('left' means low→left, high→right).
enum LowBandEar { left, right }

/// A single binaural-fusion trial: the [word] to identify, which ear carries
/// the low band, and the closed set of [choices] (always contains [word]).
class BinauralFusionTrial {
  BinauralFusionTrial({
    required this.word,
    required this.lowBandEar,
    required this.choices,
  }) : assert(choices.contains(word));

  final String word;
  final LowBandEar lowBandEar;
  final List<String> choices;

  int get targetIndex => choices.indexOf(word);
  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic generator: picks a target word, which ear gets the low band,
/// and a closed set of [choiceCount] options including the target.
class BinauralFusionGenerator {
  BinauralFusionGenerator({
    required this.pool,
    int seed = 0,
    this.choiceCount = 4,
  })  : assert(pool.length >= choiceCount),
        _rng = Random(seed);

  final List<String> pool;
  final int choiceCount;
  final Random _rng;

  BinauralFusionTrial next() {
    final ti = _rng.nextInt(pool.length);
    final word = pool[ti];
    final choices = <String>[word];
    final available = List<int>.generate(pool.length, (i) => i)
      ..remove(ti)
      ..shuffle(_rng);
    for (final idx in available) {
      if (choices.length >= choiceCount) break;
      choices.add(pool[idx]);
    }
    choices.shuffle(_rng);
    final lowEar = _rng.nextBool() ? LowBandEar.left : LowBandEar.right;
    return BinauralFusionTrial(
      word: word,
      lowBandEar: lowEar,
      choices: choices,
    );
  }
}

/// Splits [samples] into low/high spectral bands around [crossoverHz] and
/// returns `(left, right)` channels, routing the low band to the ear indicated
/// by [lowBandEar]. Used by the page to build a stereo (dichotic) stimulus.
({List<double> left, List<double> right}) splitBands(
  List<double> samples,
  LowBandEar lowBandEar, {
  double crossoverHz = 1000,
  int sampleRate = kSampleRate,
}) {
  final low = lowPassBiquad(samples, crossoverHz, sampleRate: sampleRate);
  final high = highPassBiquad(samples, crossoverHz, sampleRate: sampleRate);
  if (lowBandEar == LowBandEar.left) {
    return (left: low, right: high);
  }
  return (left: high, right: low);
}

/// Sequences and scores a binaural-fusion run (closed-set % correct).
class BinauralFusionSession {
  BinauralFusionSession({
    this.moduleId = 'auditory',
    this.groupId = 'binaural_fusion',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  int get percent => (accuracy * 100).round();

  bool submit(
    BinauralFusionTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(
      TrialRecord(
        target: trial.word,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'low_band_ear': trial.lowBandEar == LowBandEar.left ? 'left' : 'right',
        },
      ),
    );
    return correct;
  }
}
