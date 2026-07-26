/// HINT-style adaptive sentence-in-noise protocol logic (pure Dart).
///
/// Full sentences are presented in speech-shaped/4-talker babble (a white-noise
/// placeholder here). An adaptive SNR staircase (start +10 dB, 2 dB step,
/// 2-down/1-up) converges on the SNR supporting ~70.7% correct; the mean of the
/// trailing reversals is reported as the reception threshold for sentences
/// (SRT-50). Normal-hearing adults reach roughly −2.9 dB SNR (Nilsson, Soli &
/// Sullivan, 1994) — shown here as task-relative context on uncalibrated audio.
///
/// The listener types what they heard; word-accuracy scoring drives the
/// staircase. Flutter-free so it can be unit-tested headlessly.
/// SAFETY: adaptation only moves the SNR (dB); it never changes master volume.
library;

import 'dart:math';

import 'open_set.dart' show OpenSetScoreMode, scoreResponse;
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Twenty short declarative sentences for the sentence-in-noise task. They are
/// intentionally simple and of comparable length so word-accuracy scoring is
/// stable across trials.
const List<String> kHintSentencePool = <String>[
  'The boy ran home from school',
  'She bought fresh bread today',
  'The old clock is on the wall',
  'We planted flowers in the garden',
  'He drank a glass of cold water',
  'The children played in the yard',
  'A bird sang in the morning',
  'They walked along the sandy beach',
  'The kitchen smells of warm soup',
  'My father drives an old truck',
  'The lamp gives a soft light',
  'She wrote a long letter home',
  'The dog slept by the fire',
  'We took the early morning train',
  'The farmer fed the brown cows',
  'A small boat crossed the lake',
  'He fixed the broken window',
  'The river flows past the town',
  'She sang a happy little song',
  'The store closes at nine tonight',
];

/// Sequences and scores an adaptive HINT-style sentence-in-noise run.
///
/// The staircase adapts SNR; each trial is scored by word accuracy and counts
/// as "correct" (making the task harder) when the listener repeats at least
/// [correctThreshold] of the key words.
class HintSinSession {
  HintSinSession({
    this.moduleId = 'noise',
    this.groupId = 'hint_sin',
    AdaptiveTrack? track,
    this.maxTrials = 20,
    this.correctThreshold = 0.5,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack(value: 10, min: -20, max: 20, step: 2);

  final String moduleId;
  final String groupId;

  /// SNR staircase (start +10 dB, 2 dB step, 2-down/1-up by default).
  final AdaptiveTrack track;
  final int maxTrials;

  /// Word-accuracy fraction at/above which the sentence is scored "correct"
  /// for the staircase (default 0.5 = at least half the words repeated).
  final double correctThreshold;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  double _scoreSum = 0;

  /// SNR (dB) at which the next sentence will be presented.
  double get currentSnrDb => track.value;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  /// Mean word-accuracy across trials (0..1).
  double get meanWordAccuracy =>
      records.isEmpty ? 0 : _scoreSum / records.length;

  /// SRT-50 (dB): mean of the trailing reversals, or null if too few.
  double? get srtDb => track.threshold;

  /// Reversal-based standard deviation of the threshold (precision indicator).
  double? get srtSd => track.thresholdSd;

  /// Records a typed [response] for [target] and advances the SNR staircase.
  ///
  /// Returns the word-accuracy score (0..1). The trial is recorded at its
  /// presentation SNR (before adaptation); only SNR moves — never volume.
  double submit(String target, String response, {required int latencyMs}) {
    final score =
        scoreResponse(target, response, OpenSetScoreMode.wordAccuracy);
    final correct = score >= correctThreshold;
    final snrAtPresentation = track.value;
    _scoreSum += score;
    records.add(
      TrialRecord(
        target: target,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'snr_db': snrAtPresentation,
          'word_accuracy': score,
        },
      ),
    );
    track.submit(correct);
    return score;
  }
}

/// Deterministic sentence order for a run (shuffles the pool with [seed] and
/// cycles if more trials than sentences are requested).
class HintSentenceSequencer {
  HintSentenceSequencer({
    this.pool = kHintSentencePool,
    int seed = 0,
  }) : _order = List<String>.of(pool)..shuffle(Random(seed));

  final List<String> pool;
  final List<String> _order;

  String sentenceFor(int trialIndex) => _order[trialIndex % _order.length];
}
