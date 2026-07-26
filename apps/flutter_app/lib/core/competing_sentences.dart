/// Competing Sentences Test protocol logic (pure Dart).
///
/// A target sentence is presented to one ear while a different (competing)
/// sentence is presented to the other ear at the same time. The listener is
/// asked to repeat/identify the sentence in the cued (target) ear. This is a
/// dichotic-listening task, so results are tracked per ear (left/right) — the
/// clinical norm is ≥ 90% per ear.
///
/// This layer is Flutter-free and audio-free so it can be unit-tested
/// headlessly; presentation (stereo placeholder speech) lives in the page.
/// SAFETY: nothing here changes master volume — adaptation is not used.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Twenty short, syntactically simple sentences used as competing-speech
/// material. They are deliberately concrete and of similar length so no single
/// choice is obviously the odd one out.
const List<String> kCompetingSentencePool = <String>[
  'The dog ran across the road',
  'She opened the red door',
  'A boy kicked the round ball',
  'The cat sat on the warm mat',
  'We ate our lunch in the park',
  'He found a key on the floor',
  'The bird flew over the tall tree',
  'My sister likes to read books',
  'The rain fell all night long',
  'They drove the blue car home',
  'A fish swam in the clear pond',
  'The baby slept in the crib',
  'She wore a bright yellow hat',
  'The bus stopped at the corner',
  'He painted the old fence white',
  'We watched the moon at night',
  'The teacher wrote on the board',
  'A dog barked at the mailman',
  'She poured milk into the cup',
  'The train left the station early',
];

/// A single competing-sentences trial: the [target] sentence (cued ear) and a
/// different [distractor] sentence (other ear), plus the closed set of
/// [choices] the listener picks from (always contains [target]).
class CompetingSentenceTrial {
  CompetingSentenceTrial({
    required this.target,
    required this.distractor,
    required this.targetEar,
    required this.choices,
  }) : assert(target != distractor),
       assert(targetEar == 'left' || targetEar == 'right'),
       assert(choices.contains(target));

  /// Sentence presented in the cued ear (the one to report).
  final String target;

  /// Competing sentence presented in the other ear.
  final String distractor;

  /// 'left' or 'right' — the ear whose sentence must be reported.
  final String targetEar;

  /// Closed-set response options (typically 4), including [target].
  final List<String> choices;

  /// The ear NOT cued (where the distractor plays).
  String get otherEar => targetEar == 'left' ? 'right' : 'left';

  int get targetIndex => choices.indexOf(target);

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic generator: picks a target and a distinct distractor from the
/// pool, a cued ear, and a closed set of [choiceCount] options that includes
/// the target. Given the same seed it always yields the same trials.
class CompetingSentenceGenerator {
  CompetingSentenceGenerator({
    this.pool = kCompetingSentencePool,
    int seed = 0,
    this.choiceCount = 4,
  })  : assert(pool.length >= choiceCount),
        _rng = Random(seed);

  final List<String> pool;
  final int choiceCount;
  final Random _rng;

  CompetingSentenceTrial next() {
    final ti = _rng.nextInt(pool.length);
    var di = _rng.nextInt(pool.length);
    while (di == ti) {
      di = _rng.nextInt(pool.length);
    }
    final target = pool[ti];
    final distractor = pool[di];

    // Build the closed set: target + distinct distractor options.
    final choices = <String>[target];
    final available = List<int>.generate(pool.length, (i) => i)
      ..remove(ti)
      ..shuffle(_rng);
    for (final idx in available) {
      if (choices.length >= choiceCount) break;
      choices.add(pool[idx]);
    }
    choices.shuffle(_rng);

    final ear = _rng.nextBool() ? 'left' : 'right';
    return CompetingSentenceTrial(
      target: target,
      distractor: distractor,
      targetEar: ear,
      choices: choices,
    );
  }
}

/// Sequences and scores a competing-sentences run, tracking per-ear accuracy.
class CompetingSentenceSession {
  CompetingSentenceSession({
    this.moduleId = 'auditory',
    this.groupId = 'competing_sentences',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  double _earAccuracy(String ear) {
    final ofEar = records.where((r) => r.parameters['ear'] == ear).toList();
    if (ofEar.isEmpty) return 0;
    return ofEar.where((r) => r.correct).length / ofEar.length;
  }

  /// Whether any trials have been scored for [ear] yet.
  bool hasEar(String ear) =>
      records.any((r) => r.parameters['ear'] == ear);

  double get leftAccuracy => _earAccuracy('left');
  double get rightAccuracy => _earAccuracy('right');

  /// Records a response for [trial] and returns whether it was correct.
  bool submit(
    CompetingSentenceTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
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
          'ear': trial.targetEar,
          'distractor': trial.distractor,
        },
      ),
    );
    return correct;
  }
}
