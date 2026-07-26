/// Generic audio-identification protocol logic (pure Dart).
///
/// A stimulus plays and the listener identifies it from a closed choice set.
/// The audio source is supplied by the renderer (synthesized instruments,
/// melodies, sound effects, or recorded assets), so one session/generator
/// serves every identification task. Scoring is exact choice; master volume is
/// never touched.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// A choice: an [id] (also the synthesis/asset key), a [label], and optional
/// [emoji] / [swatchArgb] / [assetPath] for presentation.
class IdentificationChoice {
  const IdentificationChoice({
    required this.id,
    required this.label,
    this.emoji,
    this.swatchArgb,
    this.assetPath,
  });

  final String id;
  final String label;
  final String? emoji;
  final int? swatchArgb;
  final String? assetPath;
}

class IdentificationTrial {
  IdentificationTrial({required this.target, required this.choices});

  final IdentificationChoice target;
  final List<IdentificationChoice> choices;

  int get targetIndex => choices.indexWhere((c) => c.id == target.id);

  bool isCorrect(int chosenIndex) =>
      chosenIndex >= 0 &&
      chosenIndex < choices.length &&
      choices[chosenIndex].id == target.id;
}

/// Deterministic generator: picks a target and (choiceCount-1) distractors,
/// then shuffles the displayed order.
class IdentificationGenerator {
  IdentificationGenerator({
    required this.pool,
    this.choiceCount = 4,
    int seed = 0,
  })  : assert(pool.length >= 2),
        _rng = Random(seed);

  final List<IdentificationChoice> pool;
  final int choiceCount;
  final Random _rng;

  IdentificationTrial next() {
    final n = min(choiceCount, pool.length);
    final target = pool[_rng.nextInt(pool.length)];
    final distractors = pool.where((c) => c.id != target.id).toList()
      ..shuffle(_rng);
    final choices = <IdentificationChoice>[target, ...distractors.take(n - 1)]
      ..shuffle(_rng);
    return IdentificationTrial(target: target, choices: choices);
  }
}

/// Sequences and scores an identification run.
class IdentificationSession {
  IdentificationSession({
    required this.moduleId,
    required this.groupId,
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

  bool submit(
    IdentificationTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex].id
        : '';
    records.add(
      TrialRecord(
        target: trial.target.id,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{'choices': trial.choices.length},
      ),
    );
    return correct;
  }
}
