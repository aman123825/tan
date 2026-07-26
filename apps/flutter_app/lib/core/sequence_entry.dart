/// Sequence-entry (digit-span) protocol logic (pure Dart).
///
/// A recall task: a sequence of items is presented and the listener enters it
/// back; scoring is exact ordered match. Difficulty adapts on span length via a
/// discrete [SpanLadder] over the catalog's declared lengths (e.g. 3/5/7).
/// Nothing here touches master volume.
///
/// NOTE: this renderer presents the sequence visually. Spoken-digit
/// presentation awaits reviewed Indian-English speech assets (kept
/// `demo_only`), at which point the same session logic drives the audio path.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Deterministic generator of item sequences from an [alphabet].
class SequenceEntryGenerator {
  SequenceEntryGenerator({int seed = 0, this.alphabet = '0123456789'})
      : _rng = Random(seed);

  final String alphabet;
  final Random _rng;

  List<String> next(int length) => List<String>.generate(
      length, (_) => alphabet[_rng.nextInt(alphabet.length)]);
}

/// Discrete span staircase over an ordered list of [lengths]. Two consecutive
/// correct recalls step up (harder/longer); one error steps down.
class SpanLadder {
  SpanLadder({this.lengths = const [3, 5, 7], this.ruleCorrect = 2})
      : assert(lengths.isNotEmpty);

  final List<int> lengths;
  final int ruleCorrect;

  int _index = 0;
  int _streak = 0;
  int _lastDirection = 0;

  /// Longest span recalled correctly so far.
  int maxCorrectLength = 0;
  int reversals = 0;

  int get currentLength => lengths[_index];

  void submit(bool correct) {
    if (correct) {
      if (currentLength > maxCorrectLength) maxCorrectLength = currentLength;
      _streak++;
      if (_streak >= ruleCorrect) {
        _streak = 0;
        _step(1);
      }
    } else {
      _streak = 0;
      _step(-1);
    }
  }

  void _step(int direction) {
    final next = (_index + direction).clamp(0, lengths.length - 1);
    if (next != _index) {
      if (_lastDirection != 0 && direction != _lastDirection) reversals++;
      _lastDirection = direction;
      _index = next;
    }
  }
}

/// Recall order: forward (same order) or backward (reversed).
enum RecallOrder { forward, backward }

/// Sequences and scores an adaptive sequence-entry (digit-span) run.
class SequenceEntrySession {
  SequenceEntrySession({
    this.moduleId = 'openset',
    this.groupId = 'digit_span',
    List<int>? lengths,
    this.maxTrials = 15,
    this.mode = ProtocolMode.training,
    this.recallOrder = RecallOrder.forward,
    SpanLadder? ladder,
  }) : ladder = ladder ?? SpanLadder(lengths: lengths ?? const [3, 5, 7]);

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;
  final RecallOrder recallOrder;
  final SpanLadder ladder;

  final List<TrialRecord> records = <TrialRecord>[];

  int get currentLength => ladder.currentLength;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Highest span (length) recalled correctly.
  int get maxSpan => ladder.maxCorrectLength;

  bool submit(
    List<String> target,
    List<String> response, {
    required int latencyMs,
  }) {
    final expected = recallOrder == RecallOrder.backward
        ? target.reversed.toList()
        : target;
    final correct = _sequenceEquals(expected, response);
    records.add(
      TrialRecord(
        target: target.join(),
        response: response.join(),
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'length': target.length,
          'order': recallOrder.name,
        },
      ),
    );
    ladder.submit(correct);
    return correct;
  }

  static bool _sequenceEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Deterministic generator of token sequences from a list of [symbols]
/// (supports multi-character tokens like instrument names). For single-
/// character symbols it draws the same indices as [SequenceEntryGenerator].
class SymbolSequenceGenerator {
  SymbolSequenceGenerator(this.symbols, {int seed = 0})
      : assert(symbols.isNotEmpty),
        _rng = Random(seed);

  final List<String> symbols;
  final Random _rng;

  List<String> next(int length) => List<String>.generate(
      length, (_) => symbols[_rng.nextInt(symbols.length)]);
}
