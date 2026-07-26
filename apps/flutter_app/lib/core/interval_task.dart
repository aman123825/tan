/// Generic adaptive N-interval forced-choice session (pure Dart).
///
/// Reused by level/amplitude discrimination, tone detection (incl. forward
/// masking), and rhythm discrimination — every "play N intervals, pick the one
/// that differs, adapt one parameter" task. The adapted parameter's name and
/// staircase are injected so the same session serves each task.
///
/// SAFETY: adaptation moves the task parameter via [AdaptiveTrack]; it never
/// touches master volume.
library;

import 'forced_choice.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

export 'forced_choice.dart' show ThreeIntervalTrial, ThreeIntervalGenerator;

class IntervalTaskSession {
  IntervalTaskSession({
    required this.moduleId,
    required this.groupId,
    required this.paramName,
    required this.track,
    this.intervals = 3,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
    this.extraParameters = const <String, Object?>{},
  });

  final String moduleId;
  final String groupId;

  /// The trial-record key for the adapted parameter (e.g. 'delta_db').
  final String paramName;
  final AdaptiveTrack track;
  final int intervals;
  final int maxTrials;
  final ProtocolMode mode;
  final Map<String, Object?> extraParameters;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Current value of the adapted parameter for the next trial.
  double get currentParam => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold in the adapted parameter's units (mean trailing reversals).
  double? get threshold => track.threshold;

  bool submit(
    ThreeIntervalTrial trial,
    int chosenInterval, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenInterval);
    final valueAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: 'interval_${trial.targetInterval + 1}',
        response: 'interval_${chosenInterval + 1}',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          paramName: valueAtPresentation,
          ...extraParameters,
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
