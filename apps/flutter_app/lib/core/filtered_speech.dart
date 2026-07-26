/// Low-Pass Filtered Speech Test protocol logic (pure Dart).
///
/// Speech is low-pass filtered (default 1000 Hz) to remove high-frequency
/// consonant cues, then presented monaurally (one ear at a time). The listener
/// types what they heard. Reduced closure/degraded-speech scores are associated
/// with central auditory processing difficulty. Scored per ear; typical adult
/// performance is ≥ 70% per ear (task-relative on uncalibrated audio).
///
/// This layer is Flutter-free so it can be unit-tested headlessly. The filter
/// is a second-order (Butterworth-Q) low-pass biquad — the same RBJ-cookbook
/// form already used by the MLD narrowband filter — applied as direct-form-I.
library;

import 'dart:math';

import 'audio/pcm_synth.dart' show kSampleRate;
import 'open_set.dart' show normalizeResponse;
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Applies a second-order low-pass biquad at [cutoffHz] to [samples].
///
/// [q] is the filter quality (0.7071 ≈ Butterworth, maximally flat). Returns a
/// new buffer the same length as the input. A non-positive/oversized cutoff
/// returns the input unchanged.
List<double> lowPassBiquad(
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

  final b0 = (1 - cosw0) / 2;
  final b1 = 1 - cosw0;
  final b2 = (1 - cosw0) / 2;
  final a0 = 1 + alpha;
  final a1 = -2 * cosw0;
  final a2 = 1 - alpha;

  return _applyBiquad(samples, b0, b1, b2, a0, a1, a2);
}

/// Direct-form-I biquad application (shared by low/high-pass filters).
List<double> _applyBiquad(
  List<double> x,
  double b0,
  double b1,
  double b2,
  double a0,
  double a1,
  double a2,
) {
  final out = List<double>.filled(x.length, 0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final x0 = x[i];
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

/// A single filtered-speech trial: the [word] to report and which [ear] it is
/// presented to ('left' or 'right').
class FilteredSpeechTrial {
  const FilteredSpeechTrial(this.word, this.ear)
      : assert(ear == 'left' || ear == 'right');

  final String word;
  final String ear;
}

/// Deterministic generator: cycles through [trialsPerEar] words for the right
/// ear, then [trialsPerEar] for the left ear (per-ear blocks), drawing words
/// from [pool].
class FilteredSpeechGenerator {
  FilteredSpeechGenerator({
    required this.pool,
    this.trialsPerEar = 25,
    int seed = 0,
  })  : assert(pool.isNotEmpty),
        _rng = Random(seed);

  final List<String> pool;
  final int trialsPerEar;
  final Random _rng;

  int _count = 0;

  int get totalTrials => trialsPerEar * 2;
  bool get isComplete => _count >= totalTrials;

  FilteredSpeechTrial next() {
    final ear = _count < trialsPerEar ? 'right' : 'left';
    final word = pool[_rng.nextInt(pool.length)];
    _count++;
    return FilteredSpeechTrial(word, ear);
  }
}

/// Sequences and scores a filtered-speech run, tracking per-ear percent correct
/// (whole-word, normalized comparison).
class FilteredSpeechSession {
  FilteredSpeechSession({
    this.moduleId = 'auditory',
    this.groupId = 'filtered_speech',
    this.trialsPerEar = 25,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;
  final int trialsPerEar;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get totalTrials => trialsPerEar * 2;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= totalTrials;

  double _earAccuracy(String ear) {
    final ofEar = records.where((r) => r.parameters['ear'] == ear).toList();
    if (ofEar.isEmpty) return 0;
    return ofEar.where((r) => r.correct).length / ofEar.length;
  }

  double get leftAccuracy => _earAccuracy('left');
  double get rightAccuracy => _earAccuracy('right');
  int get leftPercent => (leftAccuracy * 100).round();
  int get rightPercent => (rightAccuracy * 100).round();

  double get overallAccuracy => records.isEmpty
      ? 0
      : records.where((r) => r.correct).length / records.length;

  /// Records a typed [response] for [trial]; returns whether it matched (after
  /// normalization of case/whitespace/punctuation).
  bool submit(
    FilteredSpeechTrial trial,
    String response, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct =
        normalizeResponse(response) == normalizeResponse(trial.word);
    records.add(
      TrialRecord(
        target: trial.word,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{'ear': trial.ear},
      ),
    );
    return correct;
  }
}
