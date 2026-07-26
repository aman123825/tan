/// Amplitude-modulation-detection protocol logic (pure Dart).
///
/// A 3AFC task: three noise intervals play; one is amplitude-modulated and the
/// listener chooses which. Difficulty adapts on modulation depth (dB) via the
/// deterministic [AdaptiveTrack.modulation] staircase (2-down/1-up; smaller /
/// more-negative dB = shallower modulation = harder). Nothing here touches
/// master volume.
library;

import 'audio/pcm_synth.dart';
import 'forced_choice.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

export 'forced_choice.dart' show ThreeIntervalTrial, ThreeIntervalGenerator;

/// Builds the three-interval sequence: steady noise bursts separated by
/// silence, with the [targetInterval] burst amplitude-modulated at [depthDb].
List<double> buildModulationSequence({
  required int targetInterval,
  required double depthDb,
  double rateHz = 20,
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
          ? amNoise(
              seconds: intervalSeconds,
              rateHz: rateHz,
              depthDb: depthDb,
              amp: amp,
              seed: seed + i,
            )
          : whiteNoise(seconds: intervalSeconds, amp: amp, seed: seed + i),
    );
  }
  return concat(parts);
}

/// Sequences and scores an adaptive amplitude-modulation-detection run.
class ModulationDetectionSession {
  ModulationDetectionSession({
    this.moduleId = 'auditory',
    this.groupId = 'modulation_depth',
    this.rateHz = 20,
    AdaptiveTrack? track,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack.modulation();

  final String moduleId;
  final String groupId;
  final double rateHz;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Modulation depth (dB) at which the next trial will be presented.
  double get currentDepthDb => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold modulation depth (dB): mean of trailing reversals, or null.
  double? get thresholdDepthDb => track.threshold;

  bool submit(
    ThreeIntervalTrial trial,
    int chosenInterval, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenInterval);
    final depthAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: 'interval_${trial.targetInterval + 1}',
        response: 'interval_${chosenInterval + 1}',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'depth_db': depthAtPresentation,
          'rate_hz': rateHz
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
