import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/session_history.dart';

/// Ordinary-least-squares slope of [ys] against [xs] (points per x-unit).
/// Returns 0 for degenerate inputs (fewer than two points or zero variance).
double linearRegressionSlope(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 2 || ys.length != n) return 0;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return den == 0 ? 0 : num / den;
}

/// Intercept of the OLS line for [ys] against [xs].
double linearRegressionIntercept(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n == 0 || ys.length != n) return 0;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  return my - linearRegressionSlope(xs, ys) * mx;
}

/// Trend direction from a slope expressed in accuracy-points per session.
/// A small band around zero is reported as "stable".
enum TrendDirection { improving, stable, declining }

extension TrendDirectionInfo on TrendDirection {
  String get label => switch (this) {
        TrendDirection.improving => 'Improving',
        TrendDirection.stable => 'Stable',
        TrendDirection.declining => 'Declining',
      };

  Color get color => switch (this) {
        TrendDirection.improving => const Color(0xff22c55e),
        TrendDirection.stable => const Color(0xff3b82f6),
        TrendDirection.declining => const Color(0xfffbbf24),
      };

  IconData get icon => switch (this) {
        TrendDirection.improving => Icons.trending_up,
        TrendDirection.stable => Icons.trending_flat,
        TrendDirection.declining => Icons.trending_down,
      };
}

/// Classifies a per-session slope (accuracy points/session) into a direction.
/// The default ±1 point/session dead-band avoids over-reading noise.
TrendDirection trendFromSlope(double slopePointsPerSession,
    {double band = 1.0}) {
  if (slopePointsPerSession > band) return TrendDirection.improving;
  if (slopePointsPerSession < -band) return TrendDirection.declining;
  return TrendDirection.stable;
}

/// Multi-session trend view: a per-test accuracy line chart over time with an
/// OLS trend line and an improving/stable/declining label.
///
/// Reads completed sessions from [SessionHistory]. Tests may inject [records]
/// directly to avoid the async SharedPreferences load.
class TrendPage extends StatefulWidget {
  const TrendPage({super.key, this.history, this.records});

  final SessionHistory? history;

  /// Optional pre-loaded records (bypasses [history] when provided).
  final List<SessionRecord>? records;

  @override
  State<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<TrendPage> {
  List<SessionRecord>? _records;

  @override
  void initState() {
    super.initState();
    if (widget.records != null) {
      _records = widget.records;
    } else {
      (widget.history ?? SessionHistory()).load().then((r) {
        if (mounted) setState(() => _records = r);
      });
    }
  }

  /// Groups records by test title, each list ordered oldest → newest.
  Map<String, List<SessionRecord>> _byTest(List<SessionRecord> records) {
    final map = <String, List<SessionRecord>>{};
    for (final r in records) {
      map.putIfAbsent(r.title, () => <SessionRecord>[]).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress trends')),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? _empty(theme)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Progress over time, per test',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        'Adaptive tests plot their measured threshold '
                        '(lower is better); other tests plot accuracy. Trend '
                        'line is an ordinary least-squares fit. Research '
                        'measurement only — not a diagnosis.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: const Color(0xff94a3b8))),
                    const SizedBox(height: 12),
                    for (final entry in _byTest(records).entries)
                      _TrendCard(title: entry.key, sessions: entry.value),
                  ],
                ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.show_chart,
                  size: 48, color: Color(0xff8b9bb4)),
              const SizedBox(height: 12),
              Text('No sessions recorded yet',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Complete a few exercises to see progress trends here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xff94a3b8))),
            ],
          ),
        ),
      );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.sessions});

  final String title;
  final List<SessionRecord> sessions;

  /// Prefer the stored headline metric (threshold, SNR…) when every session
  /// of this test carries one in the same unit — a staircase's *accuracy* is
  /// deliberately pinned near its target proportion and hides real progress.
  String? get _metricUnit {
    final unit = sessions.first.metricUnit;
    if (unit == null) return null;
    final allSame = sessions
        .every((s) => s.metricValue != null && s.metricUnit == unit);
    return allSame ? unit : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xs = <double>[
      for (var i = 0; i < sessions.length; i++) i.toDouble()
    ];
    final unit = _metricUnit;
    final ys = unit != null
        ? <double>[for (final s in sessions) s.metricValue!]
        : <double>[for (final s in sessions) s.accuracy * 100];
    final enoughForTrend = sessions.length >= 2;
    final slope = linearRegressionSlope(xs, ys);
    final intercept = linearRegressionIntercept(xs, ys);
    // For real metrics: classify progress on a mean-normalised slope
    // (%/session) and flip the sign when a SMALLER value is better (gap ms,
    // SNR dB…), so a falling threshold reads as "improving". Accuracy keeps
    // the original points-per-session classification.
    var classificationSlope = slope;
    if (unit != null) {
      final meanAbs =
          ys.map((y) => y.abs()).reduce((a, b) => a + b) / ys.length;
      classificationSlope =
          slope / (meanAbs < 1e-9 ? 1 : meanAbs) * 100;
      if (sessions.first.higherIsBetter == false) {
        classificationSlope = -classificationSlope;
      }
    }
    final direction = trendFromSlope(classificationSlope);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (enoughForTrend)
                  _TrendChip(direction: direction)
                else
                  const _MutedChip(text: 'Need ≥ 2 sessions'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                unit == null
                    ? '${sessions.length} session${sessions.length == 1 ? '' : 's'} · accuracy %'
                    : '${sessions.length} session${sessions.length == 1 ? '' : 's'} · threshold in $unit'
                        '${sessions.first.higherIsBetter == false ? ' (lower is better)' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: LineChart(
                  _chartData(xs, ys, slope, intercept, fixedScale: unit == null)),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _chartData(
      List<double> xs, List<double> ys, double slope, double intercept,
      {required bool fixedScale}) {
    final maxX = xs.length >= 2 ? (xs.length - 1).toDouble() : 1.0;
    // Accuracy plots keep the fixed 0–100 axis; metric plots (ms, dB…) fit
    // the data with a 10% pad so small threshold changes stay visible.
    double minY = 0, maxY = 100;
    if (!fixedScale) {
      final lo = ys.reduce((a, b) => a < b ? a : b);
      final hi = ys.reduce((a, b) => a > b ? a : b);
      final pad = (hi - lo).abs() < 1e-9 ? (hi.abs() * 0.2 + 1) : (hi - lo) * 0.2;
      minY = lo - pad;
      maxY = hi + pad;
    }
    final dataSpots = [
      for (var i = 0; i < xs.length; i++) FlSpot(xs[i], ys[i])
    ];
    final trendSpots = xs.length >= 2
        ? [
            FlSpot(0, intercept.clamp(minY, maxY).toDouble()),
            FlSpot(maxX, (intercept + slope * maxX).clamp(minY, maxY).toDouble()),
          ]
        : <FlSpot>[];

    return LineChartData(
      minX: 0,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 32),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${value.toInt() + 1}',
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: dataSpots,
          isCurved: false,
          color: const Color(0xff3b82f6),
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
        if (trendSpots.isNotEmpty)
          LineChartBarData(
            spots: trendSpots,
            isCurved: false,
            color: const Color(0xff8b5cf6),
            barWidth: 2,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
      ],
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.direction});

  final TrendDirection direction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: direction.color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        // ignore: deprecated_member_use
        border: Border.all(color: direction.color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(direction.icon, size: 14, color: direction.color),
          const SizedBox(width: 6),
          Text(direction.label,
              style: TextStyle(
                  color: direction.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1affffff),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xff94a3b8),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}
