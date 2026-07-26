/// Auditory Working-Memory *training* logic (pure Dart).
///
/// Two modes share this file:
///   • Span — a digit list is presented and recalled forward or backward. The
///     list length adapts (start 3, +1 after two correct, -1 after a miss).
///   • N-back — a stream of digits is presented and the listener flags each
///     item that matches the one N positions earlier. N adapts the same way.
///
/// SAFETY: adaptation changes memory load (span length / N), never master
/// volume. Flutter-free / audio-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// The two working-memory training modes.
enum WorkingMemoryMode { span, nBack }

// ---------------------------------------------------------------------- span --

/// A digit-span trial: the presented [digits] and whether recall is [backward].
class SpanTrial {
  const SpanTrial(this.digits, {required this.backward});

  final List<int> digits;
  final bool backward;

  int get length => digits.length;

  /// The order the listener must reproduce.
  List<int> get expected =>
      backward ? digits.reversed.toList(growable: false) : List<int>.of(digits);

  bool matches(List<int> recalled) {
    final want = expected;
    if (recalled.length != want.length) return false;
    for (var i = 0; i < want.length; i++) {
      if (recalled[i] != want[i]) return false;
    }
    return true;
  }
}

/// Sequences and scores a digit-span run with an adaptive list length.
class SpanSession {
  SpanSession({
    this.moduleId = 'auditory',
    this.groupId = 'working_memory',
    this.startLength = 3,
    this.minLength = 2,
    this.maxLength = 9,
    this.maxTrials = 20,
    int seed = 0,
    this.mode = ProtocolMode.training,
  })  : _length = startLength,
        _maxSpan = 0,
        _rng = Random(seed);

  final String moduleId;
  final String groupId;
  final int startLength;
  final int minLength;
  final int maxLength;
  final int maxTrials;
  final ProtocolMode mode;
  final Random _rng;

  final List<TrialRecord> records = <TrialRecord>[];
  int _length;
  int _maxSpan;
  int _consecutiveCorrect = 0;

  /// List length for the next trial.
  int get currentLength => _length;

  /// Longest span reproduced correctly.
  int get maxSpan => _maxSpan;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Builds the next trial (random digits, alternating forward/backward).
  SpanTrial next() {
    final digits = List<int>.generate(_length, (_) => _rng.nextInt(10));
    final backward = records.length.isOdd; // forward, backward, forward, …
    return SpanTrial(digits, backward: backward);
  }

  bool submit(
    SpanTrial trial,
    List<int> recalled, {
    required int latencyMs,
  }) {
    final correct = trial.matches(recalled);
    records.add(
      TrialRecord(
        target: trial.expected.join(),
        response: recalled.join(),
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'length': trial.length,
          'backward': trial.backward,
        },
      ),
    );
    if (correct) {
      if (trial.length > _maxSpan) _maxSpan = trial.length;
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _length = min(maxLength, _length + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _length = max(minLength, _length - 1);
    }
    return correct;
  }
}

// -------------------------------------------------------------------- n-back --

/// One N-back block: a [stream] of digits and the back-distance [n].
class NBackBlock {
  const NBackBlock(this.stream, this.n);

  final List<int> stream;
  final int n;

  int get length => stream.length;

  /// Positions (>= n) whose digit repeats the one n items earlier.
  Set<int> get targets {
    final t = <int>{};
    for (var i = n; i < stream.length; i++) {
      if (stream[i] == stream[i - n]) t.add(i);
    }
    return t;
  }

  /// Whether position [i] is a decision point (a match can occur there).
  bool isDecisionPosition(int i) => i >= n;
}

/// Sequences and scores an N-back run with adaptive N. Each block is one trial;
/// a block is correct only if the listener flags exactly the target positions.
class NBackSession {
  NBackSession({
    this.moduleId = 'auditory',
    this.groupId = 'working_memory',
    this.startN = 1,
    this.minN = 1,
    this.maxN = 6,
    this.decisionCount = 5,
    this.matchProbability = 0.4,
    this.maxTrials = 20,
    int seed = 0,
    this.mode = ProtocolMode.training,
  })  : _n = startN,
        _maxNReached = startN,
        _rng = Random(seed);

  final String moduleId;
  final String groupId;
  final int startN;
  final int minN;
  final int maxN;

  /// Number of decision positions after the initial N items.
  final int decisionCount;
  final double matchProbability;
  final int maxTrials;
  final ProtocolMode mode;
  final Random _rng;

  final List<TrialRecord> records = <TrialRecord>[];
  int _n;
  int _maxNReached;
  int _consecutiveCorrect = 0;

  /// N for the next block.
  int get currentN => _n;

  /// Highest N reached at full accuracy.
  int get maxNReached => _maxNReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Builds the next block: N seed digits then [decisionCount] decision items,
  /// a fraction ([matchProbability]) of which are deliberate matches.
  NBackBlock next() {
    final len = _n + decisionCount;
    final stream = <int>[];
    for (var i = 0; i < len; i++) {
      if (i < _n) {
        stream.add(_rng.nextInt(10));
      } else if (_rng.nextDouble() < matchProbability) {
        stream.add(stream[i - _n]); // deliberate match
      } else {
        // Deliberate non-match: any digit other than the n-back item.
        var d = _rng.nextInt(10);
        if (d == stream[i - _n]) d = (d + 1) % 10;
        stream.add(d);
      }
    }
    return NBackBlock(stream, _n);
  }

  /// Scores a block against the positions the listener [tapped]. Correct when
  /// the tapped set equals the target set exactly (no misses, no false alarms).
  bool submit(
    NBackBlock block,
    Set<int> tapped, {
    required int latencyMs,
  }) {
    final targets = block.targets;
    final correct = tapped.length == targets.length &&
        tapped.every(targets.contains);
    records.add(
      TrialRecord(
        target: targets.toList().join(','),
        response: (tapped.toList()..sort()).join(','),
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{'n': block.n},
      ),
    );
    if (correct) {
      if (block.n > _maxNReached) _maxNReached = block.n;
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _n = min(maxN, _n + 1);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _n = max(minN, _n - 1);
    }
    return correct;
  }
}
