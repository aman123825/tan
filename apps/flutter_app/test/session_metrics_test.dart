// Tests for the real-results pipeline added 26 Jul 2026:
// session -> headline metric -> stored record -> report rows/narrative.
import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/interval_task.dart';
import 'package:hearbloom/core/protocol_engine.dart';
import 'package:hearbloom/core/session_summary.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/report/enhanced_report_page.dart';
import 'package:hearbloom/features/report/report_data.dart';

void main() {
  test('SessionRecord JSON round-trips every field including new metrics', () {
    final record = SessionRecord(
      timestamp: DateTime.parse('2026-07-26T10:00:00'),
      moduleId: 'auditory',
      groupId: 'gap',
      title: 'Gap',
      accuracy: 0.71,
      trials: 24,
      metric: '3.2 ms',
      metricValue: 3.2,
      metricUnit: 'ms',
      subScores: const {'left': 80, 'right': 90},
      trajectory: const [20, 16, 12, 8, 12, 8, 4, 8],
      trajectoryCorrect: const [
        true, true, true, false, true, true, false, true
      ],
      chanceLevel: 1 / 3,
      higherIsBetter: false,
      confidence: 7,
    );
    final back = SessionRecord.fromJson(record.toJson());
    expect(back.metric, '3.2 ms');
    expect(back.metricValue, 3.2);
    expect(back.metricUnit, 'ms');
    expect(back.subScores, const {'left': 80, 'right': 90});
    expect(back.trajectory, const [20, 16, 12, 8, 12, 8, 4, 8]);
    expect(back.trajectoryCorrect!.length, 8);
    expect(back.trajectoryCorrect![3], isFalse);
    expect(back.chanceLevel, closeTo(1 / 3, 1e-9));
    expect(back.higherIsBetter, isFalse);
    expect(back.confidence, 7);
  });

  test('legacy SessionRecord JSON (no metric fields) still parses', () {
    final back = SessionRecord.fromJson({
      'ts': '2026-07-01T09:00:00',
      'mod': 'noise',
      'grp': 'sentence_noise',
      'title': 'Sentence noise',
      'acc': 0.7,
      'n': 20,
    });
    expect(back.metric, isNull);
    expect(back.trajectory, isNull);
    expect(back.higherIsBetter, isNull);
    expect(back.confidence, isNull);
  });

  test('summarizeSession reports the staircase threshold, not accuracy', () {
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'gap',
      paramName: 'gap_ms',
      track: AdaptiveTrack(value: 16, min: 1, max: 40, step: 2),
      maxTrials: 200,
    );
    // Alternate two-correct/one-wrong so the track reverses repeatedly and
    // completes with a threshold.
    var i = 0;
    while (!session.isComplete) {
      final trial = ThreeIntervalTrial(targetInterval: 0);
      final correct = i % 3 != 2;
      session.submit(trial, correct ? 0 : 1, latencyMs: 500);
      i++;
    }
    final metric = summarizeSession(session)!;
    expect(session.threshold, isNotNull);
    expect(metric.value, session.threshold);
    expect(metric.unit, 'ms');
    expect(metric.higherIsBetter, isFalse);
    expect(metric.chanceLevel, closeTo(1 / 3, 1e-9));
    // The trajectory mirrors the per-trial presented parameter values.
    expect(metric.trajectory!.length, session.records.length);
    expect(metric.trajectory!.first, 16);
    // Unknown session types yield null (callers fall back to accuracy).
    expect(summarizeSession('not a session'), isNull);
  });

  test('reversalIndicesOf marks direction flips', () {
    // Falls to 6 (index 3), rises to 8 (4), falls to 4 (6), rises again:
    // extrema at indices 3 (trough), 4 (peak), 6 (trough).
    expect(reversalIndicesOf(const [12, 10, 8, 6, 8, 6, 4, 6]),
        const [3, 4, 6]);
    expect(reversalIndicesOf(const [5, 5, 5]), isEmpty);
    expect(reversalIndicesOf(const [1, 2, 3]), isEmpty);
  });

  test('buildReportData maps history to banded rows and narrative', () {
    final history = <SessionRecord>[
      SessionRecord(
        timestamp: DateTime.parse('2026-07-26T10:00:00'),
        moduleId: 'auditory',
        groupId: 'gap',
        title: 'Gap',
        accuracy: 0.7,
        trials: 24,
        metric: '4.0 ms',
        metricValue: 4.0,
        metricUnit: 'ms',
        trajectory: const [20, 12, 8, 4, 8, 4, 2, 4],
        trajectoryCorrect: const [
          true, true, true, true, false, true, false, true
        ],
        chanceLevel: 1 / 3,
        higherIsBetter: false,
      ),
      SessionRecord(
        timestamp: DateTime.parse('2026-07-25T10:00:00'),
        moduleId: 'auditory',
        groupId: 'dichotic_digits',
        title: 'Dichotic digits',
        accuracy: 0.85,
        trials: 20,
        metric: 'L 78% / R 92%',
        metricValue: 85,
        metricUnit: '%',
        subScores: const {'left': 78, 'right': 92},
      ),
      SessionRecord(
        timestamp: DateTime.parse('2026-07-24T10:00:00'),
        moduleId: 'music',
        groupId: 'mci',
        title: 'Melodic contour',
        accuracy: 0.9,
        trials: 10,
        metric: '90%',
        metricValue: 90,
        metricUnit: '%',
      ),
    ];
    final data = buildReportData(history, ageYears: 30)!;

    // Gap 4 ms is within the adult GIN band -> Normal.
    final gapRow = data.tests.singleWhere((t) => t.name == 'Gap Detection');
    expect(gapRow.status, ReportStatus.normal);
    expect(gapRow.score, '4.0 ms');

    // Dichotic left ear 78% is below the adult >= 90% cut-off.
    final left = data.tests
        .singleWhere((t) => t.name == 'Dichotic Digits — Left');
    expect(left.status, ReportStatus.below);
    final right = data.tests
        .singleWhere((t) => t.name == 'Dichotic Digits — Right');
    expect(right.status, ReportStatus.normal);

    // MCI has no defensible band here: recorded, never invented.
    final mci =
        data.tests.singleWhere((t) => t.name == 'Melodic contour');
    expect(mci.status, ReportStatus.info);

    // Narrative got the real measured inputs.
    expect(data.narrative.ginMs, 4.0);
    expect(data.narrative.ddtLeftPct, 78);
    expect(data.narrative.ddtRightPct, 92);

    // The most recent staircase run is surfaced for the plot + fit.
    expect(data.staircase, isNotNull);
    expect(data.staircase!.values.first, 20);
    expect(data.staircase!.chanceLevel, closeTo(1 / 3, 1e-9));
    expect(data.staircase!.threshold, 4.0);

    // Empty history -> no report (demo fallback is the caller's job).
    expect(buildReportData(const []), isNull);
  });
}
