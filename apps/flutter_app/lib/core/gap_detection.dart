/// Temporal gap-detection protocol logic (pure Dart).
///
/// A 3-alternative forced-choice task: three noise intervals are presented, one
/// of which ([ThreeIntervalTrial.targetInterval]) contains a brief silent gap.
/// Difficulty adapts on gap duration (ms) via the deterministic
/// [AdaptiveTrack.gap] staircase (2-down/1-up). Nothing here touches master
/// volume.
///
/// Temporal tasks are wired-headphone recommended and their thresholds must not
/// be pooled across output devices (enforced server-side in results).
library;

import 'audio/pcm_synth.dart';
import 'forced_choice.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

export 'forced_choice.dart' show ThreeIntervalTrial, ThreeIntervalGenerator;

/// Builds the audible three-interval sequence for a trial: noise bursts
/// separated by silence, with the [targetInterval] burst carrying the gap.
List<double> buildGapSequence({
  required int targetInterval,
  required double gapMs,
  int intervals = 3,
  double intervalSeconds = 0.4,
  double gapBetweenSeconds = 0.25,
  double amp = 0.2,
  int seed = 0,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(gapBetweenSeconds));
    parts.add(
      i == targetInterval
          ? noiseWithGap(
              seconds: intervalSeconds,
              gapMs: gapMs,
              amp: amp,
              seed: seed + i,
            )
          : whiteNoise(seconds: intervalSeconds, amp: amp, seed: seed + i),
    );
  }
  return concat(parts);
}

/// Sequences and scores an adaptive temporal gap-detection run.
class GapDetectionSession {
  GapDetectionSession({
    this.moduleId = 'auditory',
    this.groupId = 'gap',
    AdaptiveTrack? track,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack.gap();

  final String moduleId;
  final String groupId;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Gap duration (ms) at which the next trial will be presented.
  double get currentGapMs => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold gap (ms): mean of the trailing reversals, or null if too few.
  double? get thresholdGapMs => track.threshold;

  /// Records a response and advances the gap staircase. Only gap duration
  /// moves — never master volume.
  bool submit(
    ThreeIntervalTrial trial,
    int chosenInterval, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenInterval);
    final gapAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: 'interval_${trial.targetInterval + 1}',
        response: 'interval_${chosenInterval + 1}',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{'gap_ms': gapAtPresentation},
      ),
    );
    track.submit(correct);
    return correct;
  }
}
