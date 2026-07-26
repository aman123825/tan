/// Spatial-hearing / sound-localization training — pure Dart DSP + an adaptive
/// session controller.
///
/// A broadband noise burst is placed at a simulated azimuth using the two main
/// binaural cues:
///   • Interaural Time Difference (ITD): the far ear is delayed by
///     `ITD = (d / c) · sin θ`, with head width d = 0.17 m and c = 343 m/s.
///   • Interaural Level Difference (ILD): the far ear is attenuated by
///     `ILD = 10 · |sin θ|` dB (a simplified high-frequency approximation).
/// The result is a stereo pair — wired headphones are required for the cues to
/// be separable. This is an illustrative demonstration on uncalibrated audio,
/// NOT a validated spatial-audio (HRTF) renderer or clinical stimulus.
///
/// SAFETY: difficulty adapts by *which angles are presented* (their spacing),
/// never master volume. Flutter-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../audio/pcm_synth.dart' show kSampleRate;
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// Head width (m) used for the ITD geometry.
const double kHeadWidthM = 0.17;

/// Speed of sound (m/s).
const double kSpeedOfSoundMps = 343.0;

/// The seven simulated azimuths, left (−) to right (+), in degrees.
const List<int> kSpatialAngles = <int>[-90, -60, -30, 0, 30, 60, 90];

/// Progressive difficulty: each level adds finer/closer positions. Level 0 is
/// the easy extremes (±90°); the final level uses all seven positions.
const List<List<int>> kSpatialLevels = <List<int>>[
  <int>[-90, 90],
  <int>[-90, -60, 60, 90],
  <int>[-90, -60, -30, 30, 60, 90],
  <int>[-90, -60, -30, 0, 30, 60, 90],
];

/// Interaural time difference (seconds) for a source at [angleDeg].
/// Positive angles (right) yield a positive ITD (right ear leads).
double itdSeconds(
  double angleDeg, {
  double headWidthM = kHeadWidthM,
  double speedOfSoundMps = kSpeedOfSoundMps,
}) =>
    (headWidthM / speedOfSoundMps) * sin(angleDeg * pi / 180.0);

/// Interaural level difference (dB) for a source at [angleDeg] — a simplified
/// `10 · |sin θ|` high-frequency approximation (≈ 10 dB at ±90°).
double ildDb(double angleDeg) => 10.0 * sin(angleDeg * pi / 180.0).abs();

/// Spatializes a mono [samples] buffer to a `(left, right)` stereo pair for a
/// source at [angleDeg], applying the ITD delay and ILD attenuation to the far
/// ear. The near ear is unchanged; the far ear is delayed and attenuated.
({List<double> left, List<double> right}) spatialize(
  List<double> samples,
  double angleDeg, {
  int sampleRate = kSampleRate,
}) {
  final n = samples.length;
  final left = List<double>.filled(n, 0);
  final right = List<double>.filled(n, 0);

  final itd = itdSeconds(angleDeg);
  final delaySamples = (itd.abs() * sampleRate).round();
  final farGain = pow(10, -ildDb(angleDeg) / 20).toDouble();

  // angle > 0 → source on the right: right ear is near, left ear is far.
  final rightIsNear = angleDeg >= 0;
  for (var i = 0; i < n; i++) {
    final s = samples[i];
    final delayedIndex = i - delaySamples;
    final delayed = delayedIndex >= 0 ? samples[delayedIndex] : 0.0;
    if (rightIsNear) {
      right[i] = s; // near ear: on time, full level
      left[i] = delayed * farGain; // far ear: delayed + attenuated
    } else {
      left[i] = s;
      right[i] = delayed * farGain;
    }
  }
  return (left: left, right: right);
}

/// A single localization trial: the presented [angleDeg] and the [choices]
/// (the angles offered on the display for this difficulty level).
class SpatialTrial {
  const SpatialTrial({required this.angleDeg, required this.choices});

  final int angleDeg;
  final List<int> choices;

  bool isCorrect(int chosenAngle) => chosenAngle == angleDeg;

  /// Absolute angular error (degrees) of a chosen angle.
  int errorFor(int chosenAngle) => (chosenAngle - angleDeg).abs();
}

/// Deterministic generator that draws a target angle from the active level's
/// position set (all seven positions are always shown/clickable).
class SpatialGenerator {
  SpatialGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  SpatialTrial next(int level) {
    final active = kSpatialLevels[level.clamp(0, kSpatialLevels.length - 1)];
    final angle = active[_rng.nextInt(active.length)];
    return SpatialTrial(angleDeg: angle, choices: kSpatialAngles);
  }
}

/// Sequences and scores a localization run, adapting difficulty by level.
///
/// Two correct answers advance a level (more, closer positions); one wrong
/// answer drops a level. Reports percent correct, the mean absolute angular
/// error, and the hardest level reached.
class SpatialSession {
  SpatialSession({
    this.moduleId = 'auditory',
    this.groupId = 'spatial',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
    this.ruleCorrect = 2,
    this.startLevel = 0,
  })  : _level = startLevel,
        _maxLevelReached = startLevel;

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;
  final int ruleCorrect;
  final int startLevel;

  final List<TrialRecord> records = <TrialRecord>[];
  final List<int> _errors = <int>[];

  int _level;
  int _maxLevelReached;
  int _consecutiveCorrect = 0;

  static final int _maxLevel = kSpatialLevels.length - 1;

  /// Current difficulty level (0 = easy extremes … last = all seven).
  int get currentLevel => _level;

  /// Number of active positions at the current level.
  int get activePositions => kSpatialLevels[_level].length;

  /// Hardest level the listener reached.
  int get maxLevelReached => _maxLevelReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  int get percent => (accuracy * 100).round();

  /// Mean absolute angular error (degrees) across all answered trials.
  double get meanAngularError => _errors.isEmpty
      ? 0
      : _errors.reduce((a, b) => a + b) / _errors.length;

  /// Records a response (the chosen angle) and adapts the difficulty level.
  ///
  /// SAFETY: only the difficulty level changes — never master volume.
  bool submit(
    SpatialTrial trial,
    int chosenAngle, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenAngle);
    _errors.add(trial.errorFor(chosenAngle));
    records.add(
      TrialRecord(
        target: '${trial.angleDeg}',
        response: '$chosenAngle',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'angle_deg': trial.angleDeg,
          'level': _level,
          'angular_error_deg': trial.errorFor(chosenAngle),
        },
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= ruleCorrect) {
        _level = min(_maxLevel, _level + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _level = max(0, _level - 1);
    }
    if (_level > _maxLevelReached) _maxLevelReached = _level;
    return correct;
  }
}
