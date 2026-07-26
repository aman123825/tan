/// Closed-set identification protocol logic (pure Dart).
///
/// A recorded item plays (optionally in noise at a fixed SNR); the listener
/// picks it from a closed choice set (target + distractors). Used for word,
/// number, letter, phoneme, sentence and color identification. Scoring is exact
/// choice. Master volume is never touched (any noise adapts SNR only).
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// A closed-set item: what to show and where its audio asset lives.
class ClosedSetItem {
  const ClosedSetItem({
    required this.id,
    required this.label,
    required this.assetPath,
    this.swatchArgb,
  });

  final String id;
  final String label;
  final String assetPath;

  /// Optional color (0xAARRGGBB) for swatch-choice tasks (e.g. colors).
  final int? swatchArgb;
}

/// A single trial: the target plus the displayed choices (incl. the target).
class ClosedSetTrial {
  ClosedSetTrial({required this.target, required this.choices});

  final ClosedSetItem target;
  final List<ClosedSetItem> choices;

  int get targetIndex => choices.indexWhere((c) => c.id == target.id);

  bool isCorrect(int chosenIndex) =>
      chosenIndex >= 0 &&
      chosenIndex < choices.length &&
      choices[chosenIndex].id == target.id;
}

/// Deterministic generator: picks a target and (choiceCount-1) distractors from
/// [pool], then shuffles the displayed order.
class ClosedSetGenerator {
  ClosedSetGenerator({required this.pool, this.choiceCount = 4, int seed = 0})
      : assert(pool.length >= 2),
        _rng = Random(seed);

  final List<ClosedSetItem> pool;
  final int choiceCount;
  final Random _rng;

  ClosedSetTrial next() {
    final n = min(choiceCount, pool.length);
    final target = pool[_rng.nextInt(pool.length)];
    final distractors = pool.where((c) => c.id != target.id).toList()
      ..shuffle(_rng);
    final choices = <ClosedSetItem>[target, ...distractors.take(n - 1)]
      ..shuffle(_rng);
    return ClosedSetTrial(target: target, choices: choices);
  }
}

/// Sequences and scores a closed-set identification run.
class ClosedSetSession {
  ClosedSetSession({
    this.moduleId = 'foundation',
    this.groupId = 'word',
    this.snrDb,
    this.snrTrack,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;

  /// Fixed SNR (dB) if presented in steady noise; null means quiet.
  final double? snrDb;

  /// Optional adaptive-noise staircase. When provided, the item is presented in
  /// noise at [currentSnrDb] and the SNR adapts 2-down/1-up on correctness
  /// (two correct answers lower the SNR = noisier = harder). This makes
  /// recognition difficulty track *the noise* rather than the item, mirroring
  /// adaptive speech-in-noise. Master volume is never touched — only the SNR.
  final AdaptiveTrack? snrTrack;

  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// SNR (dB) at which the next item is presented: the adaptive track's value
  /// when adapting, else the fixed [snrDb] (null = quiet).
  double? get currentSnrDb => snrTrack?.value ?? snrDb;

  /// Adaptive speech-in-noise threshold (dB) — mean of trailing reversals —
  /// when noise is adapting; null otherwise or if too few reversals.
  double? get thresholdSnrDb => snrTrack?.threshold;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete =>
      records.length >= maxTrials || (snrTrack?.complete ?? false);

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    ClosedSetTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex].id
        : '';
    final snrAtPresentation = currentSnrDb;
    records.add(
      TrialRecord(
        target: trial.target.id,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'choices': trial.choices.length,
          if (snrAtPresentation != null) 'snr_db': snrAtPresentation,
        },
      ),
    );
    snrTrack?.submit(correct);
    return correct;
  }
}
