/// Dichotic-digits protocol logic (pure Dart).
///
/// A different digit is presented to each ear at the same time; the listener
/// reports the digit in the cued ear. This is a binaural presentation with a
/// per-ear target, so results carry the target ear (left/right) — consistent
/// with the app's per-ear result separation. Master volume is never touched.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// The digit labels 0–9.
const List<String> kDichoticDigits = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9'
];

enum Ear { left, right }

/// How the listener is asked to respond in a dichotic-digits run.
///
/// - [cued] (default, backward-compatible): report only the digit in the cued
///   ear (a random ear each trial).
/// - [freeRecall]: report BOTH digits (order does not matter for scoring).
/// - [directed]: the cued ear is deliberately alternated trial-to-trial and the
///   listener reports only that ear; supports a Right-Ear-Advantage summary.
enum DichoticMode { cued, freeRecall, directed }

/// A single dichotic trial: a digit in each ear and which ear is cued.
class DichoticTrial {
  DichoticTrial({
    required this.leftDigit,
    required this.rightDigit,
    required this.targetEar,
  });

  final String leftDigit;
  final String rightDigit;
  final Ear targetEar;

  String get targetDigit => targetEar == Ear.left ? leftDigit : rightDigit;
  String get otherDigit => targetEar == Ear.left ? rightDigit : leftDigit;

  bool isCorrect(String response) => response == targetDigit;
}

/// Deterministic generator: two distinct digits and a random cued ear.
class DichoticGenerator {
  DichoticGenerator({int seed = 0, this.digits = kDichoticDigits})
      : assert(digits.length >= 2),
        _rng = Random(seed);

  final List<String> digits;
  final Random _rng;

  DichoticTrial next({Ear? forceEar}) {
    final l = _rng.nextInt(digits.length);
    var r = _rng.nextInt(digits.length);
    while (r == l) {
      r = _rng.nextInt(digits.length);
    }
    final ear = forceEar ?? (_rng.nextBool() ? Ear.left : Ear.right);
    return DichoticTrial(
      leftDigit: digits[l],
      rightDigit: digits[r],
      targetEar: ear,
    );
  }
}

/// Sequences and scores a dichotic-digits run, tracking per-ear accuracy.
class DichoticSession {
  DichoticSession({
    this.moduleId = 'auditory',
    this.groupId = 'dichotic_digits',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
    this.dichoticMode = DichoticMode.cued,
  });

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  /// Response paradigm (cued / free-recall / directed).
  final DichoticMode dichoticMode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  double _earAccuracy(String ear) {
    final ofEar = records.where((r) => r.parameters['ear'] == ear).toList();
    if (ofEar.isEmpty) return 0;
    return ofEar.where((r) => r.correct).length / ofEar.length;
  }

  /// Per-ear hit rate for free-recall (each trial contributes to both ears).
  double _freeEarAccuracy(String key) {
    if (records.isEmpty) return 0;
    final hits = records.where((r) => r.parameters[key] == true).length;
    return hits / records.length;
  }

  double get leftAccuracy => dichoticMode == DichoticMode.freeRecall
      ? _freeEarAccuracy('left_correct')
      : _earAccuracy('left');

  double get rightAccuracy => dichoticMode == DichoticMode.freeRecall
      ? _freeEarAccuracy('right_correct')
      : _earAccuracy('right');

  int get leftPercent => (leftAccuracy * 100).round();
  int get rightPercent => (rightAccuracy * 100).round();

  /// Right-Ear Advantage in percentage points (right% − left%). Positive is the
  /// typical direction for verbal dichotic material.
  double get rightEarAdvantage => rightAccuracy * 100 - leftAccuracy * 100;

  /// Cued/directed submit: the listener reported one digit for the cued ear.
  bool submit(
    DichoticTrial trial,
    String response, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(response);
    final ear = trial.targetEar == Ear.left ? 'left' : 'right';
    records.add(
      TrialRecord(
        target: trial.targetDigit,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'ear': ear,
          'other_digit': trial.otherDigit,
        },
      ),
    );
    return correct;
  }

  /// Free-recall submit: the listener reported BOTH digits (order-independent).
  /// Scores each ear separately and marks the trial correct only when both
  /// digits are recalled. Returns whether both were correct.
  bool submitFreeRecall(
    DichoticTrial trial,
    List<String> responses, {
    required int latencyMs,
    int replays = 0,
  }) {
    final leftHit = responses.contains(trial.leftDigit);
    final rightHit = responses.contains(trial.rightDigit);
    final correct = leftHit && rightHit;
    records.add(
      TrialRecord(
        target: '${trial.leftDigit}+${trial.rightDigit}',
        response: responses.join('+'),
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'response_mode': 'free_recall',
          'left_correct': leftHit,
          'right_correct': rightHit,
        },
      ),
    );
    return correct;
  }
}
