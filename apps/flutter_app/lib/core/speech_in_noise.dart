/// Speech-in-noise adaptive-SNR 4AFC protocol logic (pure Dart).
///
/// The deterministic [AdaptiveTrack] owns SNR adaptation; this file adds the
/// 4-alternative-forced-choice trial model, a reproducible trial generator, and
/// a session controller that sequences trials, scores them and applies the stop
/// rule.
///
/// SAFETY: difficulty is adapted purely on SNR (dB). Nothing here can change
/// master volume — there is no volume field, by design (ANSD precaution).
library;

import 'dart:math';

import 'protocol_engine.dart';

/// The five-stage protocol workflow.
enum ProtocolMode { introduction, preview, training, test, results }

/// A 4-alternative forced-choice trial: four response labels, exactly one of
/// which ([targetIndex]) is the presented target.
class FourAlternativeTrial {
  FourAlternativeTrial({required this.choices, required this.targetIndex})
      : assert(targetIndex >= 0 && targetIndex < choices.length);

  final List<String> choices;
  final int targetIndex;

  String get target => choices[targetIndex];

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic 4AFC trial generator drawn from an item [pool].
///
/// Given the same seed it always yields the same trials, which matters for
/// reproducible research runs.
class FourAfcGenerator {
  FourAfcGenerator(this.pool, {int seed = 0, this.choices = 4})
      : assert(pool.length >= choices),
        _rng = Random(seed);

  final List<String> pool;
  final int choices;
  final Random _rng;

  FourAlternativeTrial next() {
    final shuffled = List<String>.of(pool)..shuffle(_rng);
    final selected = shuffled.take(choices).toList(growable: false);
    final targetIndex = _rng.nextInt(choices);
    return FourAlternativeTrial(choices: selected, targetIndex: targetIndex);
  }
}

/// Sequences and scores an adaptive speech-in-noise run.
class SpeechInNoiseSession {
  SpeechInNoiseSession({
    required this.moduleId,
    required this.groupId,
    AdaptiveTrack? track,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack.snr();

  final String moduleId;
  final String groupId;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// SNR (dB) at which the next trial will be presented.
  double get currentSnrDb => track.value;

  /// 1-based number of the trial currently in progress (for display).
  int get trialNumber => records.length + 1;

  int get completedTrials => records.length;

  /// Feedback is shown only during training — never during a locked test
  /// measurement.
  bool get showsFeedback => mode == ProtocolMode.training;

  /// Stop rule: enough reversals OR the trial budget is exhausted.
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;

  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold SNR (dB): mean of the trailing reversals, or null if too few.
  double? get thresholdSnrDb => track.threshold;

  /// Records a response for [trial] and advances the SNR staircase.
  ///
  /// The trial is recorded at its *presentation* SNR (before adaptation); the
  /// staircase then moves for the next trial. Returns whether the response was
  /// correct. SAFETY: only SNR moves here — never master volume.
  bool submit(
    FourAlternativeTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final snrAtPresentation = track.value;
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
        parameters: <String, Object?>{'snr_db': snrAtPresentation},
      ),
    );
    track.submit(correct);
    return correct;
  }
}
