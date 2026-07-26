/// Shared forced-choice primitives (pure Dart), reused by the interval-based
/// 3AFC tasks (gap detection, modulation detection).
library;

import 'dart:math';

/// A single 3AFC interval trial: which interval carries the target feature.
class ThreeIntervalTrial {
  ThreeIntervalTrial({required this.targetInterval, this.intervals = 3})
      : assert(targetInterval >= 0 && targetInterval < intervals);

  final int targetInterval;
  final int intervals;

  bool isCorrect(int chosenInterval) => chosenInterval == targetInterval;
}

/// Deterministic generator for which interval carries the target.
class ThreeIntervalGenerator {
  ThreeIntervalGenerator({int seed = 0, this.intervals = 3})
      : _rng = Random(seed);

  final int intervals;
  final Random _rng;

  ThreeIntervalTrial next() => ThreeIntervalTrial(
      targetInterval: _rng.nextInt(intervals), intervals: intervals);
}
