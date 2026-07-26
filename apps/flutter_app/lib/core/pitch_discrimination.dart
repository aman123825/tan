/// Pitch-discrimination (3AFC oddball) protocol logic (pure Dart).
///
/// Three tones play; two are a reference pitch and one (the oddball) is higher.
/// The listener picks the oddball. Difficulty adapts on the pitch difference in
/// semitones (smaller = harder) via a deterministic [AdaptiveTrack]. Master
/// volume is never touched.
library;

import 'audio/pcm_synth.dart';
import 'forced_choice.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

export 'forced_choice.dart' show ThreeIntervalTrial, ThreeIntervalGenerator;

/// Builds the three-tone sequence, with the [targetInterval] tone shifted up by
/// [deltaSemitones] from [referenceHz].
List<double> buildOddballSequence({
  required int targetInterval,
  required double referenceHz,
  required double deltaSemitones,
  int intervals = 3,
  double toneSeconds = 0.4,
  double gapBetweenSeconds = 0.2,
  double amp = 0.2,
}) {
  final oddHz = shiftSemitones(referenceHz, deltaSemitones);
  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(gapBetweenSeconds));
    parts.add(
      tone(
        seconds: toneSeconds,
        freqHz: i == targetInterval ? oddHz : referenceHz,
        amp: amp,
      ),
    );
  }
  return concat(parts);
}

/// Sequences and scores an adaptive pitch-discrimination run.
class PitchDiscriminationSession {
  PitchDiscriminationSession({
    this.moduleId = 'foundation',
    this.groupId = 'pure_tone',
    this.referenceHz = 440,
    AdaptiveTrack? track,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack.frequency();

  final String moduleId;
  final String groupId;
  final double referenceHz;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Pitch difference (semitones) at which the next trial will be presented.
  double get currentDeltaSemitones => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Threshold pitch difference (semitones): mean trailing reversals, or null.
  double? get thresholdSemitones => track.threshold;

  bool submit(
    ThreeIntervalTrial trial,
    int chosenInterval, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenInterval);
    final deltaAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: 'interval_${trial.targetInterval + 1}',
        response: 'interval_${chosenInterval + 1}',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'delta_semitones': deltaAtPresentation,
          'reference_hz': referenceHz,
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
