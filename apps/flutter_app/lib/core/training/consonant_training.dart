/// Consonant-recognition *training* protocol logic (pure Dart).
///
/// Uses the existing generated CV-syllable assets
/// (`assets/stimuli/phonemes/syl_*.wav`, `demo_only` demonstration speech, not
/// validated clinical stimuli). Four graded levels move from 2AFC voicing
/// minimal pairs to a 6AFC manner mix, ending with 4AFC identification in
/// noise. The listener must reach 70% on a level to unlock the next.
///
/// SAFETY: levels change the syllable set / noise SNR only, never master
/// volume. Flutter-free so it can be verified headlessly.
library;

import 'dart:math';

/// Whether a training level is a "spot the odd one out" discrimination task or
/// a "name what you heard" identification task. Shared with vowel training.
enum TrainingMode { discrimination, identification }

/// Broad manner-of-articulation class for a consonant (used to build the
/// manner-contrast level).
enum ConsonantManner { stop, fricative, nasal, approximant }

/// One CV syllable: [id]/[label] (e.g. "ba"), its articulatory [manner], a
/// [voiced] flag, and whether a generated audio [asset] exists for it.
class Consonant {
  const Consonant(
    this.id,
    this.manner,
    this.voiced, {
    this.hasAsset = true,
  });

  final String id;
  final ConsonantManner manner;
  final bool voiced;

  /// True when `assets/stimuli/phonemes/syl_<id>.wav` ships in the bundle.
  final bool hasAsset;

  String get label => id;
  String get assetPath => 'assets/stimuli/phonemes/syl_$id.wav';
}

/// The full 16-syllable inventory. Four (za/la/ra/wa) have no generated asset
/// yet and are excluded from playback; every shipped level only draws from the
/// twelve that do have assets.
const List<Consonant> kConsonants = <Consonant>[
  Consonant('ba', ConsonantManner.stop, true),
  Consonant('da', ConsonantManner.stop, true),
  Consonant('ga', ConsonantManner.stop, true),
  Consonant('ka', ConsonantManner.stop, false),
  Consonant('pa', ConsonantManner.stop, false),
  Consonant('ta', ConsonantManner.stop, false),
  Consonant('fa', ConsonantManner.fricative, false),
  Consonant('va', ConsonantManner.fricative, true),
  Consonant('sa', ConsonantManner.fricative, false),
  Consonant('za', ConsonantManner.fricative, true, hasAsset: false),
  Consonant('sha', ConsonantManner.fricative, false),
  Consonant('ma', ConsonantManner.nasal, true),
  Consonant('na', ConsonantManner.nasal, true),
  Consonant('la', ConsonantManner.approximant, true, hasAsset: false),
  Consonant('ra', ConsonantManner.approximant, true, hasAsset: false),
  Consonant('wa', ConsonantManner.approximant, true, hasAsset: false),
];

/// The syllables that actually have shipped audio assets.
final List<Consonant> kAvailableConsonants =
    kConsonants.where((c) => c.hasAsset).toList(growable: false);

Consonant consonantById(String id) =>
    kConsonants.firstWhere((c) => c.id == id, orElse: () => kConsonants.first);

/// Voicing minimal pairs for the 2AFC level (all have assets).
const List<List<String>> kVoicingPairs = <List<String>>[
  ['ba', 'pa'],
  ['da', 'ta'],
  ['ga', 'ka'],
];

/// Place-of-articulation contrast set for the 4AFC level.
const List<String> kPlaceContrastIds = <String>['ba', 'da', 'ga', 'ma'];

/// Manner-mix set for the 6AFC level (stops + fricatives + nasals).
const List<String> kMannerContrastIds = <String>[
  'ba', // stop
  'da', // stop
  'fa', // fricative
  'sa', // fricative
  'ma', // nasal
  'na', // nasal
];

/// Set used for the in-noise 4AFC level.
const List<String> kNoiseContrastIds = <String>['ba', 'da', 'sa', 'ma'];

/// Per-level configuration.
class ConsonantLevel {
  const ConsonantLevel({
    required this.level,
    required this.mode,
    required this.choiceCount,
    required this.inNoise,
    required this.snrDb,
    required this.description,
  });

  final int level;
  final TrainingMode mode;
  final int choiceCount;
  final bool inNoise;
  final double snrDb;
  final String description;
}

/// The four consonant-training levels.
const List<ConsonantLevel> kConsonantLevels = <ConsonantLevel>[
  ConsonantLevel(
    level: 1,
    mode: TrainingMode.identification,
    choiceCount: 2,
    inNoise: false,
    snrDb: 0,
    description: 'Voicing minimal pairs — ba/pa, da/ta, ga/ka (2AFC).',
  ),
  ConsonantLevel(
    level: 2,
    mode: TrainingMode.identification,
    choiceCount: 4,
    inNoise: false,
    snrDb: 0,
    description: 'Place contrasts — ba/da/ga/ma (4AFC).',
  ),
  ConsonantLevel(
    level: 3,
    mode: TrainingMode.identification,
    choiceCount: 6,
    inNoise: false,
    snrDb: 0,
    description: 'Manner contrasts — stops, fricatives and nasals (6AFC).',
  ),
  ConsonantLevel(
    level: 4,
    mode: TrainingMode.identification,
    choiceCount: 4,
    inNoise: true,
    snrDb: 5,
    description: 'Identify the syllable in noise — +5 dB SNR (4AFC).',
  ),
];

ConsonantLevel consonantLevelConfig(int level) =>
    kConsonantLevels[(level - 1).clamp(0, kConsonantLevels.length - 1)];

/// The highest consonant-training level available.
const int kConsonantMaxLevel = 4;

/// A single consonant-training trial (always identification): the presented
/// [target] and the closed [choices] set.
class ConsonantTrial {
  ConsonantTrial({
    required this.target,
    required this.choices,
    required this.targetIndex,
    this.inNoise = false,
    this.snrDb = 0,
  });

  final Consonant target;
  final List<Consonant> choices;
  final int targetIndex;
  final bool inNoise;
  final double snrDb;

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic consonant-training trial generator.
class ConsonantTrainingGenerator {
  ConsonantTrainingGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  ConsonantTrial next(int level) {
    final cfg = consonantLevelConfig(level);
    if (cfg.level == 1) {
      // 2AFC: pick a voicing minimal pair, present one of the two.
      final pair = kVoicingPairs[_rng.nextInt(kVoicingPairs.length)];
      final set = <Consonant>[
        consonantById(pair[0]),
        consonantById(pair[1]),
      ]..shuffle(_rng);
      final targetIndex = _rng.nextInt(set.length);
      return ConsonantTrial(
        target: set[targetIndex],
        choices: set,
        targetIndex: targetIndex,
        inNoise: cfg.inNoise,
        snrDb: cfg.snrDb,
      );
    }
    final ids = switch (cfg.level) {
      2 => kPlaceContrastIds,
      3 => kMannerContrastIds,
      _ => kNoiseContrastIds,
    };
    final set = <Consonant>[for (final id in ids) consonantById(id)]
      ..shuffle(_rng);
    final choices = set.take(cfg.choiceCount).toList()..shuffle(_rng);
    final targetIndex = _rng.nextInt(choices.length);
    return ConsonantTrial(
      target: choices[targetIndex],
      choices: choices,
      targetIndex: targetIndex,
      inNoise: cfg.inNoise,
      snrDb: cfg.snrDb,
    );
  }
}

/// Sequences and scores one consonant-training level (30 trials by default).
class ConsonantTrainingSession {
  ConsonantTrainingSession({
    this.level = 1,
    this.maxTrials = 30,
    this.passThreshold = 0.7,
  });

  final int level;
  final int maxTrials;
  final double passThreshold;

  int _correct = 0;
  int _completed = 0;
  int _streak = 0;
  int _bestStreak = 0;
  final List<bool> results = <bool>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get correctCount => _correct;
  int get currentStreak => _streak;
  int get bestStreak => _bestStreak;

  bool get isComplete => _completed >= maxTrials;
  double get accuracy => _completed == 0 ? 0 : _correct / _completed;
  int get percent => (accuracy * 100).round();
  bool get passed => accuracy >= passThreshold;

  bool submit(ConsonantTrial trial, int chosenIndex) {
    final correct = trial.isCorrect(chosenIndex);
    _completed++;
    if (correct) {
      _correct++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
    } else {
      _streak = 0;
    }
    results.add(correct);
    return correct;
  }
}
