/// Modulation-rate discrimination (3AFC oddball) protocol logic (pure Dart).
///
/// Three amplitude-modulated noises play; two flutter at a reference rate and
/// one (the oddball) flutters faster. The listener picks the odd one out.
/// Difficulty adapts on the rate ratio (closer to 1.0 = harder) via a
/// deterministic [AdaptiveTrack]. Reuses the AM synth; master volume is never
/// touched.
library;

import 'audio/pcm_synth.dart';
import 'forced_choice.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

export 'forced_choice.dart' show ThreeIntervalTrial, ThreeIntervalGenerator;

/// Builds the three-interval sequence; the [targetInterval] is modulated at
/// `referenceRateHz * ratio`, the others at `referenceRateHz`.
List<double> buildRateOddballSequence({
  required int targetInterval,
  required double referenceRateHz,
  required double ratio,
  double depthDb = -3,
  int intervals = 3,
  double intervalSeconds = 0.5,
  double gapBetweenSeconds = 0.25,
  double amp = 0.2,
  int seed = 0,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(gapBetweenSeconds));
    final rate =
        i == targetInterval ? referenceRateHz * ratio : referenceRateHz;
    parts.add(
      amNoise(
        seconds: intervalSeconds,
        rateHz: rate,
        depthDb: depthDb,
        amp: amp,
        seed: seed + i,
      ),
    );
  }
  return concat(parts);
}

/// Sequences and scores an adaptive modulation-rate-discrimination run.
class ModulationRateSession {
  ModulationRateSession({
    this.moduleId = 'auditory',
    this.groupId = 'modulation_rate',
    this.referenceRateHz = 20,
    AdaptiveTrack? track,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack(value: 2, min: 1.05, max: 4, step: 0.2);

  final String moduleId;
  final String groupId;
  final double referenceRateHz;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Rate ratio (oddball/reference) at which the next trial is presented.
  double get currentRatio => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold rate ratio: mean of trailing reversals, or null.
  double? get thresholdRatio => track.threshold;

  bool submit(
    ThreeIntervalTrial trial,
    int chosenInterval, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenInterval);
    final ratioAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: 'interval_${trial.targetInterval + 1}',
        response: 'interval_${chosenInterval + 1}',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'rate_ratio': ratioAtPresentation,
          'reference_rate_hz': referenceRateHz,
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
