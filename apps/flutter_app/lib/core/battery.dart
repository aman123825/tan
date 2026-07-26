/// Composite battery aggregation (pure Dart).
///
/// A battery runs several existing sub-tests in sequence; each contributes a
/// per-stage accuracy. The overall score is the mean of stage accuracies. This
/// is orchestration only — every sub-test keeps its own deterministic engine,
/// safety rules and per-condition persistence.
library;

class BatteryStageResult {
  const BatteryStageResult(this.label, this.accuracy);

  final String label;
  final double accuracy;
}

/// Overall battery score: mean of stage accuracies (0 when empty).
double batteryOverall(List<BatteryStageResult> results) {
  if (results.isEmpty) return 0;
  var sum = 0.0;
  for (final r in results) {
    sum += r.accuracy;
  }
  return sum / results.length;
}
