/// Interhemispheric-transfer training (pure Dart).
///
/// A short rhythm (2–4 elements, each SHORT or LONG) is presented to ONE ear;
/// the listener reproduces it by tapping short/long buttons with the OPPOSITE
/// hand. Crossing the ear-of-input to the hand-of-output engages the
/// corpus-callosum pathway (a target for integration-deficit remediation).
///
/// Pattern length adapts (climbs after two correct, drops after a miss). The
/// session scores both exact-trial and per-element accuracy. Flutter-free so it
/// can be unit-tested headlessly; the page routes the tone sequence to the cued
/// ear (stereo) and shows the opposite hand.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// A single rhythm element.
enum Beat { short, long }

/// Which ear the rhythm is presented to.
enum Ear { left, right }

extension EarInfo on Ear {
  String get label => this == Ear.left ? 'LEFT' : 'RIGHT';

  /// The hand the listener should reproduce with (opposite the input ear).
  String get oppositeHand => this == Ear.left ? 'RIGHT' : 'LEFT';
}

/// One interhemispheric trial: the [pattern] and the presentation [ear].
class InterhemisphericTrial {
  const InterhemisphericTrial({required this.pattern, required this.ear});

  final List<Beat> pattern;
  final Ear ear;

  int get length => pattern.length;

  /// Exact match of a reproduced [tapped] pattern.
  bool isCorrect(List<Beat> tapped) {
    if (tapped.length != pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (tapped[i] != pattern[i]) return false;
    }
    return true;
  }

  /// Count of element-wise matches (position by position).
  int matchingElements(List<Beat> tapped) {
    var m = 0;
    final n = min(tapped.length, pattern.length);
    for (var i = 0; i < n; i++) {
      if (tapped[i] == pattern[i]) m++;
    }
    return m;
  }
}

/// Builds mono tone samples for a rhythm [pattern]. SHORT and LONG differ in
/// tone duration; a fixed gap separates elements. The page routes these to the
/// cued ear.
List<double> rhythmSamples(
  List<Beat> pattern, {
  double freqHz = 1000,
  double shortSeconds = 0.12,
  double longSeconds = 0.34,
  double gapSeconds = 0.16,
  double amp = 0.3,
  int sampleRate = kSampleRate,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < pattern.length; i++) {
    parts.add(tone(
      seconds: pattern[i] == Beat.short ? shortSeconds : longSeconds,
      freqHz: freqHz,
      amp: amp,
      sampleRate: sampleRate,
    ));
    if (i < pattern.length - 1) {
      parts.add(silence(gapSeconds, sampleRate));
    }
  }
  return concat(parts);
}

/// Deterministic generator: builds a [level]-element pattern in a random ear.
class InterhemisphericGenerator {
  InterhemisphericGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  InterhemisphericTrial next(int level) {
    final len = level.clamp(2, 4);
    final pattern = <Beat>[
      for (var i = 0; i < len; i++)
        _rng.nextBool() ? Beat.long : Beat.short,
    ];
    final ear = _rng.nextBool() ? Ear.left : Ear.right;
    return InterhemisphericTrial(pattern: pattern, ear: ear);
  }
}

/// Sequences and scores an interhemispheric run with an adaptive pattern length.
class InterhemisphericSession {
  InterhemisphericSession({
    this.moduleId = 'auditory',
    this.groupId = 'interhemispheric',
    this.startLevel = 2,
    this.minLevel = 2,
    this.maxLevel = 4,
    this.maxTrials = 15,
    this.mode = ProtocolMode.training,
  })  : _level = startLevel,
        _maxLevelReached = startLevel;

  final String moduleId;
  final String groupId;
  final int startLevel;
  final int minLevel;
  final int maxLevel;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  int _level;
  int _maxLevelReached;
  int _consecutiveCorrect = 0;
  int _elementsCorrect = 0;
  int _elementsTotal = 0;

  int get currentLevel => _level;
  int get maxLevelReached => _maxLevelReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((r) => r.correct).length;

  /// Exact-trial accuracy.
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Per-element ("% rhythm correctly reproduced") accuracy.
  double get elementAccuracy =>
      _elementsTotal == 0 ? 0 : _elementsCorrect / _elementsTotal;

  bool submit(
    InterhemisphericTrial trial,
    List<Beat> tapped, {
    required int latencyMs,
  }) {
    final correct = trial.isCorrect(tapped);
    _elementsCorrect += trial.matchingElements(tapped);
    _elementsTotal += trial.pattern.length;
    records.add(
      TrialRecord(
        target: trial.pattern.map((b) => b.name).join('-'),
        response: tapped.map((b) => b.name).join('-'),
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'ear': trial.ear.name,
          'length': trial.pattern.length,
        },
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _level = min(maxLevel, _level + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _level = max(minLevel, _level - 1);
    }
    if (_level > _maxLevelReached) _maxLevelReached = _level;
    return correct;
  }
}
