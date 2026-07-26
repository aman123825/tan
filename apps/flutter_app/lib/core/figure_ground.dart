/// SCAN-style auditory figure-ground test at FIXED SNRs (pure Dart).
///
/// Unlike the adaptive word-in-noise staircase, this normed-style variant
/// presents word-recognition blocks at three fixed signal-to-noise ratios
/// (+8, 0, −8 dB — cf. the SCAN-3 Auditory Figure-Ground subtests at +8/0/−8
/// dB; Keith, 2009) and scores percent correct per SNR, so performance decay
/// with decreasing SNR is directly visible.
///
/// SAFETY: SNRs are fixed constants; nothing here adapts level or touches
/// master volume.
library;

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show FourAlternativeTrial, ProtocolMode;

/// The fixed test SNRs, in presentation order (easy → hard).
const List<double> kFigureGroundSnrsDb = <double>[8, 0, -8];

/// Sequences and scores a fixed-SNR figure-ground run.
class FigureGroundSession {
  FigureGroundSession({
    this.moduleId = 'noise',
    this.groupId = 'figure_ground',
    this.trialsPerSnr = 8,
    this.mode = ProtocolMode.test,
  });

  final String moduleId;
  final String groupId;
  final int trialsPerSnr;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get totalTrials => trialsPerSnr * kFigureGroundSnrsDb.length;
  int get completedTrials => records.length;
  int get trialNumber => records.length + 1;
  bool get isComplete => records.length >= totalTrials;

  /// Feedback is shown only in training mode (fixed-SNR test defaults to no
  /// feedback like other locked measurements).
  bool get showsFeedback => mode == ProtocolMode.training;

  /// SNR (dB) of the block the next trial belongs to.
  double get currentSnrDb =>
      kFigureGroundSnrsDb[(records.length ~/ trialsPerSnr)
          .clamp(0, kFigureGroundSnrsDb.length - 1)];

  /// 1-based trial number within the current block.
  int get trialInBlock => records.length % trialsPerSnr + 1;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy =>
      records.isEmpty ? 0 : correctCount / records.length;

  /// Records a response at the current fixed SNR.
  bool submit(
    FourAlternativeTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final snr = currentSnrDb;
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(TrialRecord(
      target: trial.target,
      response: response,
      correct: correct,
      latencyMs: latencyMs,
      replays: replays,
      parameters: <String, Object?>{'snr_db': snr, 'fixed_snr': true},
    ));
    return correct;
  }

  /// Percent correct (0–100) at [snrDb]; null when that block has no trials.
  double? percentFor(double snrDb) {
    final at = records
        .where((r) => (r.parameters['snr_db'] as num?)?.toDouble() == snrDb)
        .toList();
    if (at.isEmpty) return null;
    return at.where((r) => r.correct).length / at.length * 100;
  }
}
