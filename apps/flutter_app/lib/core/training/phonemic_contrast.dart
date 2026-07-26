/// Phonemic-Contrast *training* protocol logic (pure Dart).
///
/// The listener hears one word of a minimal pair and, in a 2-alternative
/// forced choice, picks which of the pair they heard. Pairs are graded by
/// contrast difficulty (tier 1 stop-voicing … tier 3 place/manner). The task
/// starts on the easiest tier and adapts: two correct answers climb a tier
/// (harder contrasts), one wrong answer drops a tier (easier).
///
/// SAFETY: adaptation only changes which contrast tier is drawn, never master
/// volume. Flutter-free / audio-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// A minimal pair and its contrast [tier] (1 = easiest … 3 = hardest).
class MinimalPair {
  const MinimalPair(this.a, this.b, this.tier, this.contrast);

  final String a;
  final String b;
  final int tier;

  /// Short human-readable contrast label (e.g. "voicing", "place").
  final String contrast;

  List<String> get words => <String>[a, b];
}

/// Minimal-pair pool. Stop-voicing contrasts are easiest (tier 1), fricative
/// voicing is intermediate (tier 2), and the place/manner contrast is hardest
/// (tier 3).
const List<MinimalPair> kMinimalPairs = <MinimalPair>[
  MinimalPair('bat', 'pat', 1, 'voicing'),
  MinimalPair('cap', 'cab', 1, 'voicing'),
  MinimalPair('pig', 'big', 1, 'voicing'),
  MinimalPair('ten', 'den', 1, 'voicing'),
  MinimalPair('pear', 'bear', 1, 'voicing'),
  MinimalPair('coat', 'goat', 1, 'voicing'),
  MinimalPair('fan', 'van', 2, 'voicing'),
  MinimalPair('sip', 'zip', 2, 'voicing'),
  MinimalPair('fine', 'vine', 2, 'voicing'),
  MinimalPair('sin', 'shin', 3, 'place'),
];

/// The tiers present in [kMinimalPairs], ascending.
const List<int> kContrastTiers = <int>[1, 2, 3];

/// A single phonemic-contrast trial: the minimal [pair], the two ordered
/// [choices] shown to the listener, and which of them was actually presented
/// ([targetIndex]).
class PhonemicContrastTrial {
  PhonemicContrastTrial({
    required this.pair,
    required this.choices,
    required this.targetIndex,
  }) : assert(targetIndex == 0 || targetIndex == 1);

  final MinimalPair pair;
  final List<String> choices;
  final int targetIndex;

  String get target => choices[targetIndex];
  int get tier => pair.tier;

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic generator that draws a pair from a requested [tier] (falling
/// back to the nearest available tier), randomizes which word is presented and
/// the left/right order of the two choices.
class PhonemicContrastGenerator {
  PhonemicContrastGenerator({
    this.pool = kMinimalPairs,
    int seed = 0,
  })  : assert(pool.isNotEmpty),
        _rng = Random(seed);

  final List<MinimalPair> pool;
  final Random _rng;

  /// Returns the pairs on [tier], or the nearest non-empty tier if none exist.
  List<MinimalPair> _pairsForTier(int tier) {
    for (var span = 0; span < kContrastTiers.length; span++) {
      for (final t in <int>[tier - span, tier + span]) {
        final matches = pool.where((p) => p.tier == t).toList();
        if (matches.isNotEmpty) return matches;
      }
    }
    return pool;
  }

  PhonemicContrastTrial next(int tier) {
    final candidates = _pairsForTier(tier);
    final pair = candidates[_rng.nextInt(candidates.length)];
    // Randomize display order of the two words.
    final choices = List<String>.of(pair.words);
    final swap = _rng.nextBool();
    if (swap) {
      final tmp = choices[0];
      choices[0] = choices[1];
      choices[1] = tmp;
    }
    // Randomize which of the two words is actually presented.
    final presented = pair.words[_rng.nextInt(2)];
    return PhonemicContrastTrial(
      pair: pair,
      choices: choices,
      targetIndex: choices.indexOf(presented),
    );
  }
}

/// Sequences and scores a phonemic-contrast run with tier adaptation.
class PhonemicContrastSession {
  PhonemicContrastSession({
    this.moduleId = 'auditory',
    this.groupId = 'phonemic_contrast',
    this.startTier = 1,
    this.maxTrials = 30,
    this.mode = ProtocolMode.training,
  })  : _tier = startTier,
        _maxTierReached = startTier;

  final String moduleId;
  final String groupId;
  final int startTier;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  int _tier;
  int _maxTierReached;
  int _consecutiveCorrect = 0;

  static final int _minTier = kContrastTiers.first;
  static final int _maxTier = kContrastTiers.last;

  /// Contrast tier for the next trial (1 = easiest … 3 = hardest).
  int get currentTier => _tier;

  /// Hardest tier the listener climbed to.
  int get maxTierReached => _maxTierReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  int get percent => (accuracy * 100).round();

  bool submit(
    PhonemicContrastTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final tierAtPresentation = _tier;
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(
      TrialRecord(
        target: trial.target,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'tier': tierAtPresentation,
          'contrast': trial.pair.contrast,
        },
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _tier = min(_maxTier, _tier + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _tier = max(_minTier, _tier - 1);
    }
    if (_tier > _maxTierReached) _maxTierReached = _tier;
    return correct;
  }
}
