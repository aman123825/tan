/// Time-Compressed Speech *training* protocol logic (pure Dart).
///
/// Sentences are presented at an adaptive playback speed. Two consecutive
/// correct responses speed the material up (0.1×, harder); one wrong response
/// slows it down (0.1×, easier), bounded to [minSpeed] .. [maxSpeed]. The
/// listener types what they heard and is scored by word accuracy. The maximum
/// speed reached is the headline training outcome.
///
/// SAFETY: adaptation changes playback *speed*, never master volume.
/// Flutter-free / audio-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../open_set.dart' show OpenSetScoreMode, scoreResponse;
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// Resamples [samples] so that, played back at the original sample rate, the
/// content sounds [speed]× faster (speed > 1 shortens, speed < 1 stretches).
///
/// Nearest-sample mapping: an output of `round(n / speed)` samples where output
/// index `i` reads input index `round(i * speed)`. `speed == 1` is a near
/// no-op; empty or non-positive speed returns a copy of the input.
List<double> timeScale(List<double> samples, double speed) {
  if (samples.isEmpty || speed <= 0 || speed == 1.0) {
    return List<double>.of(samples);
  }
  final outLen = max(1, (samples.length / speed).round());
  final out = List<double>.filled(outLen, 0);
  for (var i = 0; i < outLen; i++) {
    final src = (i * speed).round().clamp(0, samples.length - 1);
    out[i] = samples[src];
  }
  return out;
}

/// A single speed-training trial: the sentence [text] to report and the ordered
/// [assetPaths] whose audio is decoded/concatenated for presentation.
class SpeedTrainingTrial {
  const SpeedTrainingTrial(this.text, this.assetPaths);

  final String text;
  final List<String> assetPaths;
}

/// Deterministic generator drawing sentences from [corpus] (id -> text). The
/// asset path is `assets/stimuli/sentences/<id>.wav`.
class SpeedTrainingGenerator {
  SpeedTrainingGenerator({
    this.corpus = kSpeedSentenceCorpus,
    int seed = 0,
  })  : assert(corpus.isNotEmpty),
        _ids = corpus.keys.toList(growable: false),
        _rng = Random(seed);

  final Map<String, String> corpus;
  final List<String> _ids;
  final Random _rng;

  SpeedTrainingTrial next() {
    final id = _ids[_rng.nextInt(_ids.length)];
    return SpeedTrainingTrial(
      corpus[id]!,
      <String>['assets/stimuli/sentences/$id.wav'],
    );
  }
}

/// Everyday sentences with recorded/demo assets (mirrors the sentence corpus in
/// `content_pools.dart`). Multi-word so word-accuracy scoring is meaningful.
const Map<String, String> kSpeedSentenceCorpus = <String, String>{
  's1': 'the boy runs home',
  's2': 'she reads a book',
  's3': 'the dog is black',
  's4': 'we eat rice today',
  's5': 'open the red door',
  's6': 'birds fly very high',
  's7': 'he drinks cold water',
  's8': 'the sun is bright',
  's9': 'put the cup down',
  's10': 'they walk to school',
};

/// Sequences and scores an adaptive time-compressed-speech run.
class SpeedTrainingSession {
  SpeedTrainingSession({
    this.moduleId = 'auditory',
    this.groupId = 'speed_training',
    this.startSpeed = 1.0,
    this.minSpeed = 0.8,
    this.maxSpeed = 2.0,
    this.speedStep = 0.1,
    this.correctThreshold = 0.5,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  })  : assert(minSpeed <= startSpeed && startSpeed <= maxSpeed),
        _speed = startSpeed,
        _maxSpeedReached = startSpeed;

  final String moduleId;
  final String groupId;
  final double startSpeed;
  final double minSpeed;
  final double maxSpeed;
  final double speedStep;

  /// Word-accuracy at/above which a trial counts as correct for the staircase.
  final double correctThreshold;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  double _speed;
  double _maxSpeedReached;
  int _consecutiveCorrect = 0;
  double _scoreSum = 0;

  /// Playback speed for the next trial.
  double get currentSpeed => _speed;

  /// Fastest speed the listener sustained (rounded to the 0.1× grid).
  double get maxSpeedReached =>
      double.parse(_maxSpeedReached.toStringAsFixed(2));

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  /// Mean word accuracy across trials (0..1).
  double get meanAccuracy => records.isEmpty ? 0 : _scoreSum / records.length;
  int get meanAccuracyPercent => (meanAccuracy * 100).round();

  double _clampSpeed(double v) {
    final clamped = v.clamp(minSpeed, maxSpeed).toDouble();
    // Keep to the 0.1× grid to avoid floating drift accumulating.
    return double.parse(clamped.toStringAsFixed(2));
  }

  /// Records a typed [response] for [trial]; returns the word-accuracy score.
  /// Adapts the speed for the next trial (2-up on correct → faster, 1-down on
  /// wrong → slower).
  double submit(
    SpeedTrainingTrial trial,
    String response, {
    required int latencyMs,
    int replays = 0,
  }) {
    final score =
        scoreResponse(trial.text, response, OpenSetScoreMode.wordAccuracy);
    final correct = score >= correctThreshold;
    _scoreSum += score;
    final speedAtPresentation = _speed;
    records.add(
      TrialRecord(
        target: trial.text,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'speed': speedAtPresentation,
          'score': score,
        },
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _speed = _clampSpeed(_speed + speedStep);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _speed = _clampSpeed(_speed - speedStep);
    }
    if (_speed > _maxSpeedReached) _maxSpeedReached = _speed;
    return score;
  }
}
