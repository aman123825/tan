/// Pitch-ranking training protocol logic (pure Dart, Flutter-free).
///
/// The listener hears 3–5 pure tones in a random order and must reorder them
/// from LOW → HIGH. Difficulty grows by using more tones and narrower spacing
/// (from 3 widely-spaced tones to 5 closely-spaced tones). Scoring is the
/// fraction of positions placed correctly.
///
/// Adaptation changes only the tone count and spacing — never master volume.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';

/// One difficulty rung: how many [toneCount] tones and their [spacingSemitones]
/// (smaller spacing = harder to rank).
class PitchRankingLevel {
  const PitchRankingLevel(this.toneCount, this.spacingSemitones);

  final int toneCount;
  final double spacingSemitones;

  String get description =>
      '$toneCount tones · ${spacingSemitones.toStringAsFixed(
          spacingSemitones.truncateToDouble() == spacingSemitones ? 0 : 1)} '
      'semitone spacing';
}

/// The difficulty ladder from easy (few, wide) to hard (many, close).
const List<PitchRankingLevel> kPitchRankingLevels = <PitchRankingLevel>[
  PitchRankingLevel(3, 7),
  PitchRankingLevel(3, 4),
  PitchRankingLevel(4, 4),
  PitchRankingLevel(4, 2),
  PitchRankingLevel(5, 2),
  PitchRankingLevel(5, 1),
];

int get kPitchRankingMaxLevel => kPitchRankingLevels.length - 1;

PitchRankingLevel pitchRankingLevelConfig(int level) =>
    kPitchRankingLevels[level.clamp(0, kPitchRankingMaxLevel)];

/// A single pitch-ranking trial: the tone [freqs] in *presentation* order and
/// the difficulty [level].
class PitchRankingTrial {
  const PitchRankingTrial({
    required this.freqs,
    required this.level,
  });

  /// Tone frequencies (Hz) in the order they are presented / displayed.
  final List<double> freqs;
  final int level;

  int get toneCount => freqs.length;

  /// The presentation indices sorted LOW → HIGH — the correct answer order.
  List<int> get correctOrder {
    final idx = List<int>.generate(freqs.length, (i) => i);
    idx.sort((a, b) => freqs[a].compareTo(freqs[b]));
    return idx;
  }

  /// Fraction of positions the [chosenOrder] (a sequence of presentation
  /// indices, low→high) places correctly, in [0, 1].
  double score(List<int> chosenOrder) {
    final correct = correctOrder;
    if (chosenOrder.length != correct.length || correct.isEmpty) return 0;
    var hits = 0;
    for (var i = 0; i < correct.length; i++) {
      if (chosenOrder[i] == correct[i]) hits++;
    }
    return hits / correct.length;
  }

  bool isFullyCorrect(List<int> chosenOrder) => score(chosenOrder) >= 1.0;
}

/// Synthesizes one ranking tone.
List<double> pitchRankingTone(
  double freqHz, {
  double seconds = 0.5,
  double amp = 0.22,
  int sampleRate = kSampleRate,
}) =>
    tone(seconds: seconds, freqHz: freqHz, amp: amp, sampleRate: sampleRate);

/// Deterministic pitch-ranking trial generator.
class PitchRankingGenerator {
  PitchRankingGenerator({this.baseHz = 262.0, int seed = 0})
      : _rng = Random(seed);

  final double baseHz;
  final Random _rng;

  PitchRankingTrial next(int level) {
    final cfg = pitchRankingLevelConfig(level);
    // Evenly-spaced ascending tones, then a small random anchor so runs differ.
    final anchor = _rng.nextInt(4).toDouble();
    final ascending = <double>[
      for (var k = 0; k < cfg.toneCount; k++)
        shiftSemitones(baseHz, anchor + k * cfg.spacingSemitones),
    ];
    // Present in a shuffled order.
    final present = List<double>.of(ascending)..shuffle(_rng);
    return PitchRankingTrial(freqs: present, level: level);
  }
}

/// Adaptive pitch-ranking session (15 trials by default).
///
/// A fully-correct trial advances the level (more/closer tones); a trial below
/// [dropThreshold] correct eases it. Reports the mean position accuracy and the
/// highest level reached. Adaptation changes only tone count / spacing.
class PitchRankingSession {
  PitchRankingSession({
    this.maxTrials = 15,
    this.startLevel = 0,
    this.dropThreshold = 0.5,
  });

  final int maxTrials;
  final int startLevel;
  final double dropThreshold;

  late int level = startLevel;

  int _completed = 0;
  int _fullyCorrect = 0;
  double _scoreSum = 0;
  int _consecutivePerfect = 0;
  int _maxLevelReached = 0;
  final List<bool> results = <bool>[]; // fully-correct per trial (for sparkline)
  final List<double> scores = <double>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get fullyCorrectCount => _fullyCorrect;
  int get maxLevelReached => _maxLevelReached;
  bool get isComplete => _completed >= maxTrials;

  /// Mean position accuracy across completed trials, in [0, 1].
  double get meanAccuracy => _completed == 0 ? 0 : _scoreSum / _completed;
  int get percent => (meanAccuracy * 100).round();

  /// Records a trial by its ordering [score] (0..1). Returns whether it was a
  /// perfect ordering.
  bool submit(PitchRankingTrial trial, List<int> chosenOrder) {
    final s = trial.score(chosenOrder);
    final perfect = s >= 1.0;
    _completed++;
    _scoreSum += s;
    scores.add(s);
    results.add(perfect);
    if (level > _maxLevelReached) _maxLevelReached = level;
    if (perfect) {
      _fullyCorrect++;
      _consecutivePerfect++;
      if (_consecutivePerfect >= 2) {
        _consecutivePerfect = 0;
        level = (level + 1).clamp(0, kPitchRankingMaxLevel);
      }
    } else {
      _consecutivePerfect = 0;
      if (s < dropThreshold) {
        level = (level - 1).clamp(0, kPitchRankingMaxLevel);
      }
    }
    return perfect;
  }
}
