/// Time-Compressed Speech Test protocol logic (pure Dart).
///
/// Speech is time-compressed (played faster without changing pitch of the
/// sample rate we play at) by resampling — we keep every `1/(1-ratio)`-th
/// sample so the buffer plays in less time when rendered at the original rate.
/// A compression of 0.4 keeps ~60% of the duration (a common clinical setting).
/// The listener types what they heard; reduced scores are associated with
/// central auditory processing difficulty. Typical performance ≥ 70%
/// (task-relative on uncalibrated audio).
///
/// Flutter-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import 'open_set.dart' show normalizeResponse;
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Time-compresses [samples] by [ratio] (0..0.9): the returned buffer keeps a
/// fraction `(1 - ratio)` of the samples via linear-index decimation, so when
/// played at the original sample rate it lasts `(1 - ratio)` of the original
/// duration (i.e. ratio 0.4 → ~60% duration → ~1.67× speed).
///
/// Uses nearest-sample resampling (take every `1/(1-ratio)`-th sample), which
/// is the "drop samples" decimation described for a simple compressor. A ratio
/// of 0 returns the input unchanged.
List<double> timeCompress(List<double> samples, double ratio) {
  final r = ratio.clamp(0.0, 0.9);
  if (r <= 0 || samples.isEmpty) return List<double>.of(samples);
  final keep = 1.0 - r; // fraction of samples retained
  final outLen = max(1, (samples.length * keep).round());
  final step = samples.length / outLen; // > 1 → we skip samples
  final out = List<double>.filled(outLen, 0);
  for (var i = 0; i < outLen; i++) {
    final src = (i * step).floor().clamp(0, samples.length - 1);
    out[i] = samples[src];
  }
  return out;
}

/// A single compressed-speech trial: the [word] to report.
class CompressedSpeechTrial {
  const CompressedSpeechTrial(this.word);

  final String word;
}

/// Deterministic generator drawing target words from [pool].
class CompressedSpeechGenerator {
  CompressedSpeechGenerator({
    required this.pool,
    this.maxTrials = 25,
    int seed = 0,
  })  : assert(pool.isNotEmpty),
        _rng = Random(seed);

  final List<String> pool;
  final int maxTrials;
  final Random _rng;

  int _count = 0;
  bool get isComplete => _count >= maxTrials;

  CompressedSpeechTrial next() {
    _count++;
    return CompressedSpeechTrial(pool[_rng.nextInt(pool.length)]);
  }
}

/// Sequences and scores a time-compressed-speech run (whole-word, normalized).
class CompressedSpeechSession {
  CompressedSpeechSession({
    this.moduleId = 'auditory',
    this.groupId = 'compressed_speech',
    this.compressionRatio = 0.4,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;

  /// Fraction of duration removed (0.4 → 60% duration retained).
  final double compressionRatio;
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
    CompressedSpeechTrial trial,
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
        parameters: <String, Object?>{'compression_ratio': compressionRatio},
      ),
    );
    return correct;
  }
}
