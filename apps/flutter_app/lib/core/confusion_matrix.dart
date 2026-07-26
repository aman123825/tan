/// Confusion-matrix aggregation for identification tasks (pure Dart).
///
/// Tabulates how often each presented target was reported as each response, so
/// systematic error patterns (e.g. confusing /b/ with /p/) surface after a
/// vowel, consonant or closed-set identification run. Flutter-free so it can be
/// unit-tested headlessly; the grid view lives in
/// `features/report/confusion_matrix_page.dart`.
library;

import 'protocol_engine.dart';

/// A single off-diagonal confusion: [target] was reported as [response],
/// [count] times.
class ConfusionPair {
  const ConfusionPair(this.target, this.response, this.count);

  final String target;
  final String response;
  final int count;
}

/// target → {response → count}. Diagonal entries (target == response) are the
/// correct answers; every other cell is an error.
class ConfusionMatrix {
  ConfusionMatrix();

  /// Builds a matrix from completed [records] (uses each record's target and
  /// response labels). An optional [relabel] maps stored ids to display labels.
  factory ConfusionMatrix.fromRecords(
    Iterable<TrialRecord> records, {
    String Function(String id)? relabel,
  }) {
    final m = ConfusionMatrix();
    String map(String s) => relabel == null ? s : relabel(s);
    for (final r in records) {
      // A blank response (e.g. a stopped/timed-out trial) is skipped.
      if (r.response.isEmpty) continue;
      m.record(map(r.target), map(r.response));
    }
    return m;
  }

  final Map<String, Map<String, int>> counts = <String, Map<String, int>>{};

  /// Records one presentation of [target] answered as [response].
  void record(String target, String response) {
    final row = counts.putIfAbsent(target, () => <String, int>{});
    row[response] = (row[response] ?? 0) + 1;
  }

  /// Count for a specific cell (0 if never seen).
  int count(String target, String response) =>
      counts[target]?[response] ?? 0;

  /// The number of times [target] was presented (its row total).
  int rowTotal(String target) {
    final row = counts[target];
    if (row == null) return 0;
    return row.values.fold(0, (a, b) => a + b);
  }

  /// Sorted union of all target and response labels — the axis order for the
  /// grid (rows and columns share it so the diagonal is correct answers).
  List<String> get labels {
    final set = <String>{};
    for (final entry in counts.entries) {
      set.add(entry.key);
      set.addAll(entry.value.keys);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Largest single count in any cell (for colour scaling); 0 when empty.
  int get maxCount {
    var mx = 0;
    for (final row in counts.values) {
      for (final c in row.values) {
        if (c > mx) mx = c;
      }
    }
    return mx;
  }

  /// Total presentations recorded.
  int get total {
    var t = 0;
    for (final row in counts.values) {
      for (final c in row.values) {
        t += c;
      }
    }
    return t;
  }

  /// Total correct (diagonal) presentations.
  int get correct {
    var t = 0;
    for (final entry in counts.entries) {
      t += entry.value[entry.key] ?? 0;
    }
    return t;
  }

  /// Total errors (off-diagonal presentations).
  int get errorCount => total - correct;

  /// The [n] most frequent off-diagonal confusions, descending by count.
  List<ConfusionPair> topConfusions([int n = 3]) {
    final pairs = <ConfusionPair>[];
    for (final entry in counts.entries) {
      final target = entry.key;
      for (final resp in entry.value.entries) {
        if (resp.key == target) continue; // skip correct
        pairs.add(ConfusionPair(target, resp.key, resp.value));
      }
    }
    pairs.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      // Stable, deterministic tie-break by label.
      final byTarget = a.target.compareTo(b.target);
      if (byTarget != 0) return byTarget;
      return a.response.compareTo(b.response);
    });
    return pairs.take(n).toList();
  }

  /// A one-line human summary of the most common confusion, or a positive
  /// message when there are no errors. Errors are expressed as a percentage of
  /// all errors (e.g. "You often confuse b with p (40% of errors).").
  String summary() {
    if (total == 0) return 'No responses recorded yet.';
    if (errorCount == 0) {
      return 'No confusions — every response was correct.';
    }
    final top = topConfusions(1);
    if (top.isEmpty) return 'No confusions — every response was correct.';
    final t = top.first;
    final pct = (t.count / errorCount * 100).round();
    return 'You often confuse ${t.target} with ${t.response} '
        '($pct% of errors).';
  }
}
