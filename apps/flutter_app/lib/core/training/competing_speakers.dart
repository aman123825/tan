/// Competing Speakers *training* protocol logic (pure Dart).
///
/// Two "voices" speak at once (rendered in the page as tone-sequence speech
/// placeholders at different pitches). The listener is told to attend to the
/// HIGHER voice and then answers which sentence that voice said. The task is
/// made adaptively harder by shrinking the level difference between the target
/// (higher) voice and the competing (lower) voice: with a big level difference
/// the target stands out; as the difference approaches 0 dB the two voices are
/// equally loud and separation depends on selective attention alone.
///
/// SAFETY: adaptation moves the *between-voice* level difference (dB), never
/// master volume. Flutter-free / audio-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// Short, concrete sentences used as competing-speech material. Deliberately of
/// similar length so no single choice is obviously the odd one out.
const List<String> kCompetingSpeakersPool = <String>[
  'The dog ran across the road',
  'She opened the red door',
  'A boy kicked the round ball',
  'The cat sat on the warm mat',
  'We ate our lunch in the park',
  'He found a key on the floor',
  'The bird flew over the tree',
  'My sister likes to read books',
  'The rain fell all night long',
  'They drove the blue car home',
  'A fish swam in the clear pond',
  'The baby slept in the crib',
  'She wore a bright yellow hat',
  'The bus stopped at the corner',
  'He painted the old fence white',
  'We watched the moon at night',
];

/// A single competing-speakers trial: the [target] sentence (the HIGHER voice,
/// the one to report), a distinct [distractor] sentence (the lower voice) and a
/// closed set of [choices] (always contains [target]).
class CompetingSpeakersTrial {
  CompetingSpeakersTrial({
    required this.target,
    required this.distractor,
    required this.choices,
  })  : assert(target != distractor),
        assert(choices.contains(target));

  final String target;
  final String distractor;
  final List<String> choices;

  int get targetIndex => choices.indexOf(target);

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic generator: picks a target and a distinct distractor plus a
/// closed set of [choiceCount] options that includes the target. Given the same
/// seed it always yields the same trials.
class CompetingSpeakersGenerator {
  CompetingSpeakersGenerator({
    this.pool = kCompetingSpeakersPool,
    int seed = 0,
    this.choiceCount = 4,
  })  : assert(pool.length >= choiceCount),
        _rng = Random(seed);

  final List<String> pool;
  final int choiceCount;
  final Random _rng;

  CompetingSpeakersTrial next() {
    final ti = _rng.nextInt(pool.length);
    var di = _rng.nextInt(pool.length);
    while (di == ti) {
      di = _rng.nextInt(pool.length);
    }
    final target = pool[ti];
    final choices = <String>[target];
    final available = List<int>.generate(pool.length, (i) => i)
      ..remove(ti)
      ..shuffle(_rng);
    for (final idx in available) {
      if (choices.length >= choiceCount) break;
      choices.add(pool[idx]);
    }
    choices.shuffle(_rng);
    return CompetingSpeakersTrial(
      target: target,
      distractor: pool[di],
      choices: choices,
    );
  }
}

/// Sequences and scores a competing-speakers run. The level difference between
/// the two voices adapts on a 2-down/1-up staircase
/// (`AdaptiveTrack(value: 10, min: 0, max: 20, step: 2)`): two correct answers
/// shrink the difference (harder), one wrong answer widens it (easier).
class CompetingSpeakersSession {
  CompetingSpeakersSession({
    this.moduleId = 'auditory',
    this.groupId = 'competing_speakers',
    AdaptiveTrack? track,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack(value: 10, min: 0, max: 20, step: 2);

  final String moduleId;
  final String groupId;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Level difference (dB) at which the next trial will be presented.
  double get currentLevelDiffDb => track.value;

  /// Smallest (hardest) level difference presented so far, or null before the
  /// first trial.
  double? _minLevelDiff;
  double? get minLevelDiffDb => _minLevelDiff;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Records a response for [trial] and advances the level-difference staircase.
  /// Returns whether the response was correct.
  bool submit(
    CompetingSpeakersTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final levelAtPresentation = track.value;
    _minLevelDiff = _minLevelDiff == null
        ? levelAtPresentation
        : min(_minLevelDiff!, levelAtPresentation);
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
          'level_diff_db': levelAtPresentation,
          'distractor': trial.distractor,
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
