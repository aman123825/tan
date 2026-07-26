/// Environmental-to-Speech Continuum *training* logic (pure Dart).
///
/// A five-level ladder that walks the listener from simple pitch discrimination
/// up to speech recognition in heavy noise:
///   1. pick the odd tone of three (pitch-discrimination warm-up)
///   2. identify an environmental sound (4AFC)
///   3. identify a spoken word in quiet (4AFC)
///   4. identify a spoken word in mild noise (SNR +10 dB)
///   5. identify a spoken word in heavy noise (SNR +3 dB)
/// Each level runs [trialsPerLevel] trials; the listener must reach
/// [passThreshold] (default 80%) to advance. The highest level reached is the
/// headline outcome.
///
/// SAFETY: level 4/5 difficulty comes from the speech-to-noise ratio, never
/// master volume. Flutter-free / audio-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../audio/timbre.dart' show kSfx;
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// What a continuum trial asks the listener to do.
enum ContinuumTrialKind { toneOddball, environment, word }

/// Words with demo assets (`assets/stimuli/words/word_<w>.wav`).
const List<String> kContinuumWordPool = <String>[
  'bell',
  'ball',
  'bat',
  'bag',
  'pen',
  'pin',
  'cup',
  'cap',
];

/// The highest continuum level.
const int kContinuumMaxLevel = 5;

/// A single continuum trial. Carries everything the page needs to render audio
/// for the current level; irrelevant fields are null.
class ContinuumTrial {
  const ContinuumTrial({
    required this.level,
    required this.kind,
    required this.choices,
    required this.targetIndex,
    this.baseFreqHz,
    this.oddFreqHz,
    this.sfxId,
    this.word,
    this.snrDb,
  });

  final int level;
  final ContinuumTrialKind kind;

  /// Labels shown as the closed-set choices.
  final List<String> choices;
  final int targetIndex;

  // Level 1 (tone oddball):
  final double? baseFreqHz;
  final double? oddFreqHz;

  // Level 2 (environmental sound):
  final String? sfxId;

  // Levels 3–5 (spoken word):
  final String? word;

  /// Speech-to-noise ratio in dB (levels 4/5); null means quiet (level 3).
  final double? snrDb;

  String get target => choices[targetIndex];

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Sequences a continuum run and owns level progression. Produces the
/// appropriate trial for the current level via [nextTrial]; [submit] scores it
/// and, at the end of each level's block, either advances or ends the run.
class ContinuumSession {
  ContinuumSession({
    this.moduleId = 'learning',
    this.groupId = 'continuum',
    this.trialsPerLevel = 5,
    this.passThreshold = 0.8,
    this.wordPool = kContinuumWordPool,
    this.sfxPool = kSfx,
    int seed = 0,
    this.mode = ProtocolMode.training,
  })  : assert(wordPool.length >= 4),
        assert(sfxPool.length >= 4),
        _rng = Random(seed);

  final String moduleId;
  final String groupId;
  final int trialsPerLevel;
  final double passThreshold;
  final List<String> wordPool;
  final List<String> sfxPool;
  final ProtocolMode mode;
  final Random _rng;

  final List<TrialRecord> records = <TrialRecord>[];

  int _level = 1;
  int _highestLevel = 1;
  int _correctInLevel = 0;
  int _trialsInLevel = 0;
  bool _complete = false;
  bool _passedAll = false;

  /// Level of the next trial (1..5).
  int get currentLevel => _level;

  /// Highest level the listener reached (attempted).
  int get highestLevel => _highestLevel;

  /// Whether level 5 was passed (the whole ladder completed).
  bool get passedAll => _passedAll;

  /// 1-based trial number within the current level.
  int get levelTrialNumber => _trialsInLevel + 1;

  int get completedTrials => records.length;
  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => _complete;

  int get correctInLevel => _correctInLevel;
  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Builds the trial for the current level.
  ContinuumTrial nextTrial() {
    switch (_level) {
      case 1:
        final target = _rng.nextInt(3);
        final base = 800.0 + _rng.nextInt(5) * 100; // 800..1200
        // A clearly-audible upward shift (4 semitones) for the odd tone.
        final odd = base * pow(2, 4 / 12).toDouble();
        return ContinuumTrial(
          level: 1,
          kind: ContinuumTrialKind.toneOddball,
          choices: const <String>['First', 'Second', 'Third'],
          targetIndex: target,
          baseFreqHz: base,
          oddFreqHz: odd,
        );
      case 2:
        final target = sfxPool[_rng.nextInt(sfxPool.length)];
        final labels = _closedSet(sfxPool, target).map(_capitalize).toList();
        return ContinuumTrial(
          level: 2,
          kind: ContinuumTrialKind.environment,
          choices: labels,
          targetIndex: labels.indexOf(_capitalize(target)),
          sfxId: target,
        );
      default:
        final target = wordPool[_rng.nextInt(wordPool.length)];
        final choices = _closedSet(wordPool, target);
        final snr = _level == 4
            ? 10.0
            : _level >= 5
                ? 3.0
                : null;
        return ContinuumTrial(
          level: _level,
          kind: ContinuumTrialKind.word,
          choices: choices,
          targetIndex: choices.indexOf(target),
          word: target,
          snrDb: snr,
        );
    }
  }

  /// A shuffled 4-item closed set from [pool] that always contains [target].
  List<String> _closedSet(List<String> pool, String target, {int size = 4}) {
    final choices = <String>[target];
    final available = List<String>.of(pool)
      ..remove(target)
      ..shuffle(_rng);
    for (final item in available) {
      if (choices.length >= size) break;
      choices.add(item);
    }
    choices.shuffle(_rng);
    return choices;
  }

  /// Records a response for [trial]; returns whether it was correct. At the end
  /// of a level's block it advances (>= [passThreshold]) or ends the run.
  bool submit(
    ContinuumTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    if (_complete) return false;
    final correct = trial.isCorrect(chosenIndex);
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
          'level': trial.level,
          if (trial.snrDb != null) 'snr_db': trial.snrDb,
        },
      ),
    );
    _trialsInLevel++;
    if (correct) _correctInLevel++;

    if (_trialsInLevel >= trialsPerLevel) {
      final passed = _correctInLevel / trialsPerLevel >= passThreshold;
      if (passed && _level >= kContinuumMaxLevel) {
        _passedAll = true;
        _complete = true;
      } else if (passed) {
        _level++;
        _highestLevel = _level;
        _correctInLevel = 0;
        _trialsInLevel = 0;
      } else {
        // Did not reach threshold: the run ends at this level.
        _complete = true;
      }
    }
    return correct;
  }
}
