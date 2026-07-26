/// Vowel-recognition *training* protocol logic (pure Dart).
///
/// The twelve English "h_d" vowels (heed, hid, head, …) are synthesized from a
/// standard three-formant table using additive synthesis — a labelled
/// demonstration proxy, NOT recorded speech and not validated clinical stimuli.
///
/// Five graded levels move from wide 3AFC vowel discrimination to 6AFC
/// identification of all twelve vowels, ending with identification in noise.
/// The listener must reach 70% on a level to unlock the next.
///
/// SAFETY: levels change the vowel set / noise SNR only, never master volume.
/// Flutter-free so it can be verified headlessly.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';
import 'consonant_training.dart' show TrainingMode;

/// One "h_d" vowel: display [word], IPA [ipa] and the first three formant
/// centre frequencies (Hz) used for additive synthesis.
class Vowel {
  const Vowel(this.id, this.word, this.ipa, this.f1, this.f2, this.f3);

  final String id;
  final String word;
  final String ipa;
  final double f1;
  final double f2;
  final double f3;
}

/// Standard adult "h_d" vowel formant table (approx. Peterson & Barney-style
/// centre frequencies). Ordered heed → hid → head → had → hod → hawed → hoed →
/// hood → who'd → hud → heard → hayed.
const List<Vowel> kVowels = <Vowel>[
  Vowel('heed', 'heed', 'i', 270, 2290, 3010),
  Vowel('hid', 'hid', 'ɪ', 390, 1990, 2550),
  Vowel('head', 'head', 'ɛ', 530, 1840, 2480),
  Vowel('had', 'had', 'æ', 660, 1720, 2410),
  Vowel('hod', 'hod', 'ɑ', 730, 1090, 2440),
  Vowel('hawed', 'hawed', 'ɔ', 570, 840, 2410),
  Vowel('hoed', 'hoed', 'o', 490, 910, 2460),
  Vowel('hood', 'hood', 'ʊ', 440, 1020, 2240),
  Vowel("who'd", "who'd", 'u', 300, 870, 2240),
  Vowel('hud', 'hud', 'ʌ', 640, 1190, 2390),
  Vowel('heard', 'heard', 'ɝ', 490, 1350, 1690),
  Vowel('hayed', 'hayed', 'e', 400, 2100, 2600),
];

Vowel vowelById(String id) =>
    kVowels.firstWhere((v) => v.id == id, orElse: () => kVowels.first);

/// Vowels at the corners of the vowel space — the easiest to tell apart. Used
/// for the 4AFC identification levels.
const List<String> kEasyVowelIds = <String>['heed', 'had', 'hod', "who'd"];

/// Wide (easy) 3AFC discrimination contrasts — vowels far apart in F1/F2 space.
const List<List<String>> kWideVowelContrasts = <List<String>>[
  ['heed', 'hod'],
  ['heed', 'had'],
  ["who'd", 'had'],
  ['heed', "who'd"],
  ['had', "who'd"],
  ['hod', 'heed'],
];

/// Close (hard) 3AFC discrimination contrasts — spectrally adjacent vowels.
const List<List<String>> kCloseVowelContrasts = <List<String>>[
  ['hid', 'head'],
  ['head', 'had'],
  ['hood', "who'd"],
  ['hod', 'hawed'],
  ['hawed', 'hoed'],
  ['hud', 'hod'],
  ['heed', 'hid'],
];

/// Additive-synthesis vowel: a low glottal fundamental plus three formant
/// sinusoids (F1 strongest), shaped by a raised-cosine amplitude envelope.
/// ~300 ms by default. A demonstration proxy, not recorded speech.
List<double> synthesizeVowel(
  Vowel v, {
  double seconds = 0.3,
  double f0 = 120,
  double amp = 0.22,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  if (n <= 0) return <double>[];
  final out = List<double>.filled(n, 0.0);
  // Formant weights: F1 loudest, higher formants progressively quieter.
  const w0 = 0.35; // fundamental "buzz"
  const w1 = 1.0;
  const w2 = 0.5;
  const w3 = 0.25;
  final norm = amp / (w0 + w1 + w2 + w3);
  final fade = (0.02 * sampleRate).round().clamp(1, n ~/ 2);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var s = w0 * sin(2 * pi * f0 * t) +
        w1 * sin(2 * pi * v.f1 * t) +
        w2 * sin(2 * pi * v.f2 * t) +
        w3 * sin(2 * pi * v.f3 * t);
    s *= norm;
    // Raised-cosine attack/decay to avoid clicks.
    if (i < fade) {
      s *= 0.5 * (1 - cos(pi * i / fade));
    } else if (i >= n - fade) {
      s *= 0.5 * (1 - cos(pi * (n - 1 - i) / fade));
    }
    out[i] = s;
  }
  return out;
}

/// Per-level configuration for the vowel-training staircase of difficulty.
class VowelLevel {
  const VowelLevel({
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

/// The five vowel-training levels.
const List<VowelLevel> kVowelLevels = <VowelLevel>[
  VowelLevel(
    level: 1,
    mode: TrainingMode.discrimination,
    choiceCount: 3,
    inNoise: false,
    snrDb: 0,
    description: 'Spot the odd one out — wide vowel contrasts (3AFC).',
  ),
  VowelLevel(
    level: 2,
    mode: TrainingMode.discrimination,
    choiceCount: 3,
    inNoise: false,
    snrDb: 0,
    description: 'Spot the odd one out — close vowel contrasts (3AFC).',
  ),
  VowelLevel(
    level: 3,
    mode: TrainingMode.identification,
    choiceCount: 4,
    inNoise: false,
    snrDb: 0,
    description: 'Name the vowel — easy vowels (4AFC).',
  ),
  VowelLevel(
    level: 4,
    mode: TrainingMode.identification,
    choiceCount: 6,
    inNoise: false,
    snrDb: 0,
    description: 'Name the vowel — all vowels (6AFC).',
  ),
  VowelLevel(
    level: 5,
    mode: TrainingMode.identification,
    choiceCount: 4,
    inNoise: true,
    snrDb: 5,
    description: 'Name the vowel in noise — easy vowels, +5 dB SNR (4AFC).',
  ),
];

VowelLevel vowelLevelConfig(int level) =>
    kVowelLevels[(level - 1).clamp(0, kVowelLevels.length - 1)];

/// The highest vowel-training level available.
const int kVowelMaxLevel = 5;

/// A single vowel-training trial. For discrimination, [sequence] holds the
/// three presented vowels and [oddIndex] the different one. For identification,
/// [target] is the presented vowel and [choices] the closed set.
class VowelTrial {
  VowelTrial.discrimination({
    required this.sequence,
    required this.oddIndex,
    this.inNoise = false,
    this.snrDb = 0,
  })  : mode = TrainingMode.discrimination,
        target = sequence[oddIndex],
        choices = const <Vowel>[],
        targetIndex = -1;

  VowelTrial.identification({
    required this.target,
    required this.choices,
    required this.targetIndex,
    this.inNoise = false,
    this.snrDb = 0,
  })  : mode = TrainingMode.identification,
        sequence = const <Vowel>[],
        oddIndex = -1;

  final TrainingMode mode;

  // Discrimination fields.
  final List<Vowel> sequence;
  final int oddIndex;

  // Identification fields.
  final List<Vowel> choices;
  final int targetIndex;

  /// The "answer" vowel (odd-one-out or presented vowel).
  final Vowel target;

  final bool inNoise;
  final double snrDb;

  bool get isDiscrimination => mode == TrainingMode.discrimination;

  bool isCorrect(int chosenIndex) =>
      isDiscrimination ? chosenIndex == oddIndex : chosenIndex == targetIndex;

  /// The vowels to synthesize, in presentation order.
  List<Vowel> get presentation => isDiscrimination ? sequence : <Vowel>[target];
}

/// Deterministic vowel-training trial generator.
class VowelTrainingGenerator {
  VowelTrainingGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  VowelTrial next(int level) {
    final cfg = vowelLevelConfig(level);
    if (cfg.mode == TrainingMode.discrimination) {
      return _discrimination(cfg);
    }
    return _identification(cfg);
  }

  VowelTrial _discrimination(VowelLevel cfg) {
    final contrasts =
        cfg.level <= 1 ? kWideVowelContrasts : kCloseVowelContrasts;
    final pair = contrasts[_rng.nextInt(contrasts.length)];
    final a = vowelById(pair[0]);
    final b = vowelById(pair[1]);
    // Two identical "standard" vowels + one "odd" vowel, at a random position.
    final standardIsA = _rng.nextBool();
    final standard = standardIsA ? a : b;
    final odd = standardIsA ? b : a;
    final oddIndex = _rng.nextInt(cfg.choiceCount);
    final seq = <Vowel>[
      for (var i = 0; i < cfg.choiceCount; i++) i == oddIndex ? odd : standard,
    ];
    return VowelTrial.discrimination(
      sequence: seq,
      oddIndex: oddIndex,
      inNoise: cfg.inNoise,
      snrDb: cfg.snrDb,
    );
  }

  VowelTrial _identification(VowelLevel cfg) {
    final List<Vowel> pool = cfg.choiceCount <= kEasyVowelIds.length
        ? <Vowel>[for (final id in kEasyVowelIds) vowelById(id)]
        : List<Vowel>.of(kVowels);
    final choices = List<Vowel>.of(pool)..shuffle(_rng);
    final set = choices.take(cfg.choiceCount).toList()..shuffle(_rng);
    final targetIndex = _rng.nextInt(set.length);
    return VowelTrial.identification(
      target: set[targetIndex],
      choices: set,
      targetIndex: targetIndex,
      inNoise: cfg.inNoise,
      snrDb: cfg.snrDb,
    );
  }
}

/// Sequences and scores one vowel-training level (25 trials by default). Pass
/// requires reaching [passThreshold] (70%).
class VowelTrainingSession {
  VowelTrainingSession({
    this.level = 1,
    this.maxTrials = 25,
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

  /// Whether the run met the pass bar (only meaningful once complete).
  bool get passed => accuracy >= passThreshold;

  /// Records a response; returns whether it was correct.
  bool submit(VowelTrial trial, int chosenIndex) {
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
