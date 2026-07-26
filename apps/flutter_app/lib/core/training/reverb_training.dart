/// Reverberation-training protocol logic (pure Dart, Flutter-free).
///
/// A word is presented with synthetic reverberation and identified from a
/// four-alternative closed set. Reverberation is added with a simple
/// feedback comb filter:
///
///   output[n] = input[n] + gain * output[n - delay]
///
/// where `gain` is derived from a simulated RT60 (the time for the reverb tail
/// to decay 60 dB). The RT60 grows on a correct streak (0.3 → 0.5 → 0.8 →
/// 1.2 s), making the room "wetter" and identification harder.
///
/// The word tokens are synthesized vowel nuclei — a labelled demonstration
/// proxy, NOT recorded speech and not validated clinical stimuli. Adaptation
/// only changes the reverberation amount, never master volume.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';
import 'vowel_training.dart' show synthesizeVowel, vowelById;

/// Applies a feedback comb-filter reverb to [input].
///
/// [rt60Seconds] is the simulated 60 dB decay time; [delaySeconds] is the comb
/// delay (a single early-reflection spacing). The feedback [gain] is chosen so
/// the tail decays 60 dB over [rt60Seconds] (`gain = 10^(-3*delay/rt60)`), then
/// the wet output is peak-normalized so it never clips or changes level.
List<double> combReverb(
  List<double> input, {
  required double rt60Seconds,
  double delaySeconds = 0.04,
  int sampleRate = kSampleRate,
  double tailSeconds = 0.6,
}) {
  if (input.isEmpty || rt60Seconds <= 0) return List<double>.of(input);
  final delay = max(1, (delaySeconds * sampleRate).round());
  final gain = pow(10, -3 * delaySeconds / rt60Seconds).toDouble().clamp(0.0, 0.99);
  // Extend the buffer so the decaying tail is audible past the dry word.
  final n = input.length + (tailSeconds * sampleRate).round();
  final out = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    final dry = i < input.length ? input[i] : 0.0;
    final fb = i >= delay ? out[i - delay] * gain : 0.0;
    out[i] = dry + fb;
  }
  // Peak-normalize (never boost level on the listener).
  var mx = 0.0;
  for (final v in out) {
    if (v.abs() > mx) mx = v.abs();
  }
  if (mx > 0.9) {
    final k = 0.9 / mx;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  return out;
}

/// The RT60 ladder from a nearly-dry room (easy) to a very reverberant hall
/// (hard). Index 0 is easiest.
const List<double> kReverbRt60Ladder = <double>[0.3, 0.5, 0.8, 1.2];

/// Highest (hardest) reverb level index.
int get kReverbMaxLevel => kReverbRt60Ladder.length - 1;

/// RT60 (seconds) for a 0-based ladder [level] (clamped).
double reverbRt60ForLevel(int level) =>
    kReverbRt60Ladder[level.clamp(0, kReverbMaxLevel)];

/// A closed-set word token: a real monosyllabic [label] whose vowel nucleus
/// (identified by [vowelId]) is synthesized for the demonstration.
class ReverbWord {
  const ReverbWord(this.label, this.vowelId);

  final String label;
  final String vowelId;
}

/// The eight closed-set words (distinct vowel nuclei so they stay audibly
/// separable even under heavy reverb).
const List<ReverbWord> kReverbWords = <ReverbWord>[
  ReverbWord('bee', 'heed'),
  ReverbWord('bad', 'had'),
  ReverbWord('bar', 'hod'),
  ReverbWord('boo', "who'd"),
  ReverbWord('bay', 'hayed'),
  ReverbWord('bird', 'heard'),
  ReverbWord('bought', 'hawed'),
  ReverbWord('book', 'hood'),
];

/// Synthesizes a dry word token (its vowel nucleus).
List<double> synthesizeReverbWord(
  ReverbWord word, {
  double seconds = 0.34,
  int sampleRate = kSampleRate,
}) =>
    synthesizeVowel(vowelById(word.vowelId),
        seconds: seconds, sampleRate: sampleRate);

/// A single reverb-training trial: the [target] word, the 4AFC [choices] and
/// their [targetIndex], plus the [rt60Seconds] in effect.
class ReverbTrial {
  const ReverbTrial({
    required this.target,
    required this.choices,
    required this.targetIndex,
    required this.rt60Seconds,
    required this.level,
  });

  final ReverbWord target;
  final List<ReverbWord> choices;
  final int targetIndex;
  final double rt60Seconds;
  final int level;

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic reverb-trial generator (4AFC).
class ReverbGenerator {
  ReverbGenerator({int seed = 0, this.choiceCount = 4}) : _rng = Random(seed);

  final int choiceCount;
  final Random _rng;

  ReverbTrial next(int level) {
    final pool = List<ReverbWord>.of(kReverbWords)..shuffle(_rng);
    final set = pool.take(choiceCount).toList()..shuffle(_rng);
    final targetIndex = _rng.nextInt(set.length);
    return ReverbTrial(
      target: set[targetIndex],
      choices: set,
      targetIndex: targetIndex,
      rt60Seconds: reverbRt60ForLevel(level),
      level: level,
    );
  }
}

/// Adaptive reverb-training session (20 trials by default).
///
/// Two consecutive correct answers raise the RT60 level (harder); a wrong
/// answer lowers it (easier). Reports accuracy and the highest RT60 (most
/// reverberant room) reliably identified. Adaptation changes only the reverb
/// amount, never master volume.
class ReverbSession {
  ReverbSession({this.maxTrials = 20, this.startLevel = 0});

  final int maxTrials;
  final int startLevel;

  late int level = startLevel;

  int _correct = 0;
  int _completed = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _consecutiveCorrect = 0;
  int _maxLevelReached = 0;
  final List<bool> results = <bool>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get correctCount => _correct;
  int get currentStreak => _streak;
  int get bestStreak => _bestStreak;
  int get maxLevelReached => _maxLevelReached;
  bool get isComplete => _completed >= maxTrials;
  double get accuracy => _completed == 0 ? 0 : _correct / _completed;
  int get percent => (accuracy * 100).round();

  /// Highest RT60 (seconds) reached — the most reverberant room handled.
  double get maxRt60 => reverbRt60ForLevel(_maxLevelReached);

  bool submit(ReverbTrial trial, int chosenIndex) {
    final correct = trial.isCorrect(chosenIndex);
    _completed++;
    if (correct) {
      _correct++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      _consecutiveCorrect++;
      if (level > _maxLevelReached) _maxLevelReached = level;
      if (_consecutiveCorrect >= 2) {
        _consecutiveCorrect = 0;
        level = (level + 1).clamp(0, kReverbMaxLevel);
      }
    } else {
      _streak = 0;
      _consecutiveCorrect = 0;
      level = (level - 1).clamp(0, kReverbMaxLevel);
    }
    results.add(correct);
    return correct;
  }
}
