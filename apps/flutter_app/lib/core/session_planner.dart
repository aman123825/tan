/// Automated session planner — analyses on-device session history and ranks
/// exercises by how much they need attention.
///
/// For each distinct exercise (module + group) in the history it computes the
/// most-recent score, a short-term trend, and how long since it was last
/// attempted, then a priority weight:
///
///   priority = (1 − lastScore) × 2 + daysSinceAttempt × 0.1 + (declining ? 1 : 0)
///
/// Higher priority = more in need of practice. This is a motivational study
/// aid — it never changes scoring, adaptation or master volume. The ranking
/// itself is pure logic and is unit-tested with plain [SessionRecord]s.
library;

import '../data/session_history.dart' show SessionRecord;

/// Short-term direction of an exercise's recent scores.
enum ExerciseTrend { improving, stable, declining }

/// Coarse mastery status used for the traffic-light indicator.
///   • needsWork  (red)    — low recent score or a declining trend
///   • improving  (yellow) — trending up but not yet mastered
///   • mastered   (green)  — high, non-declining recent score
enum ExerciseStatus { needsWork, improving, mastered }

/// One exercise's analysis and its computed practice priority.
class ExercisePriority {
  const ExercisePriority({
    required this.moduleId,
    required this.groupId,
    required this.title,
    required this.lastScore,
    required this.trend,
    required this.daysSinceAttempt,
    required this.attempts,
    required this.priority,
    required this.status,
    required this.reason,
  });

  final String moduleId;
  final String groupId;
  final String title;

  /// Accuracy (0..1) of the most recent attempt.
  final double lastScore;
  final ExerciseTrend trend;

  /// Whole days since the most recent attempt.
  final int daysSinceAttempt;
  final int attempts;

  /// Computed practice priority (higher = more in need of practice).
  final double priority;
  final ExerciseStatus status;

  /// Human-readable explanation of the priority (for the UI).
  final String reason;

  int get lastScorePercent => (lastScore * 100).round();
}

/// Analyses session history and ranks exercises by practice priority.
class SessionPlanner {
  /// Score-change threshold (fraction) that counts as improving/declining.
  static const double trendDelta = 0.05;

  /// Recent-score threshold at/above which an exercise counts as mastered.
  static const double masteredThreshold = 0.8;

  /// Ranks every distinct exercise in [records] by descending priority.
  ///
  /// [now] defaults to [DateTime.now]; pass it in tests for determinism.
  static List<ExercisePriority> analyze(
    List<SessionRecord> records, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();

    // Group by (moduleId, groupId).
    final byKey = <String, List<SessionRecord>>{};
    for (final r in records) {
      byKey.putIfAbsent('${r.moduleId}\u0000${r.groupId}', () => []).add(r);
    }

    final result = <ExercisePriority>[];
    byKey.forEach((_, sessions) {
      // Most-recent first.
      sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final latest = sessions.first;
      final lastScore = latest.accuracy.clamp(0.0, 1.0);
      final trend = _trendFor(sessions);
      final daysSince = clock.difference(latest.timestamp).inDays;
      final daysSinceNonNeg = daysSince < 0 ? 0 : daysSince;
      final declining = trend == ExerciseTrend.declining;

      final priority = (1 - lastScore) * 2 +
          daysSinceNonNeg * 0.1 +
          (declining ? 1.0 : 0.0);

      final status = _statusFor(lastScore, trend);
      result.add(
        ExercisePriority(
          moduleId: latest.moduleId,
          groupId: latest.groupId,
          title: latest.title,
          lastScore: lastScore.toDouble(),
          trend: trend,
          daysSinceAttempt: daysSinceNonNeg,
          attempts: sessions.length,
          priority: priority,
          status: status,
          reason: _reasonFor(
            lastScore: lastScore.toDouble(),
            trend: trend,
            daysSince: daysSinceNonNeg,
          ),
        ),
      );
    });

    result.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      // Tie-break deterministically by title so the ordering is stable.
      return a.title.compareTo(b.title);
    });
    return result;
  }

  /// The top [n] highest-priority exercises (fewer if history is small).
  static List<ExercisePriority> recommend(
    List<SessionRecord> records, {
    int n = 3,
    DateTime? now,
  }) {
    final ranked = analyze(records, now: now);
    return ranked.take(n).toList(growable: false);
  }

  static ExerciseTrend _trendFor(List<SessionRecord> sortedDesc) {
    if (sortedDesc.length < 2) return ExerciseTrend.stable;
    final recent = sortedDesc.first.accuracy;
    // Compare against the mean of the earlier attempts.
    final earlier = sortedDesc.skip(1).toList();
    final earlierMean =
        earlier.map((r) => r.accuracy).reduce((a, b) => a + b) / earlier.length;
    if (recent > earlierMean + trendDelta) return ExerciseTrend.improving;
    if (recent < earlierMean - trendDelta) return ExerciseTrend.declining;
    return ExerciseTrend.stable;
  }

  static ExerciseStatus _statusFor(num lastScore, ExerciseTrend trend) {
    if (trend == ExerciseTrend.declining || lastScore < 0.6) {
      return ExerciseStatus.needsWork;
    }
    if (lastScore >= masteredThreshold && trend != ExerciseTrend.declining) {
      return ExerciseStatus.mastered;
    }
    return ExerciseStatus.improving;
  }

  static String _reasonFor({
    required double lastScore,
    required ExerciseTrend trend,
    required int daysSince,
  }) {
    final parts = <String>['Last score ${(lastScore * 100).round()}%'];
    switch (trend) {
      case ExerciseTrend.improving:
        parts.add('improving');
      case ExerciseTrend.declining:
        parts.add('declining');
      case ExerciseTrend.stable:
        break;
    }
    if (daysSince <= 0) {
      parts.add('practised today');
    } else if (daysSince == 1) {
      parts.add('1 day since last attempt');
    } else {
      parts.add('$daysSince days since last attempt');
    }
    return parts.join(' · ');
  }
}
