import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/session_history.dart';
import 'report_data.dart';
import 'staircase_plot.dart';

/// Shows the report for one completed session.
///
/// The session has already been persisted before this sheet opens, so the
/// result remains available offline even if the user closes the app here.
Future<bool> showSessionResultSheet(
  BuildContext context, {
  required SessionRecord record,
  bool savedOffline = true,
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _SessionResultSheet(
          record: record,
          savedOffline: savedOffline,
        ),
      ) ??
      false;
}

class _SessionResultSheet extends StatelessWidget {
  const _SessionResultSheet({
    required this.record,
    required this.savedOffline,
  });

  final SessionRecord record;
  final bool savedOffline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = (record.accuracy * 100).round();
    final trajectory = record.trajectory;
    final hasTrajectory = trajectory != null && trajectory.length >= 2;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.assessment_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test report',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            record.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMd()
                                .add_jm()
                                .format(record.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close report',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _Metrics(record: record, accuracy: accuracy),
                const SizedBox(height: 24),
                Text(
                  hasTrajectory ? 'Adaptive progress' : 'Answer breakdown',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (hasTrajectory)
                  StaircasePlot(
                    values: trajectory,
                    reversalIndices: reversalIndicesOf(trajectory),
                    threshold: record.metricValue,
                    title: record.metricUnit == null
                        ? 'Parameter by trial'
                        : 'Parameter by trial (${record.metricUnit})',
                    unit: record.metricUnit ?? '',
                    height: 210,
                    textColor: theme.colorScheme.onSurfaceVariant,
                  )
                else
                  _AccuracyChart(record: record),
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      savedOffline
                          ? Icons.offline_pin_outlined
                          : Icons.privacy_tip_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            savedOffline
                                ? 'Saved on this device'
                                : 'Shown for this session only',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            savedOffline
                                ? (record.synced
                                    ? 'Available offline and synced online.'
                                    : 'Available offline now. Online sync '
                                        'remains optional and can be '
                                        'completed later.')
                                : 'Your privacy choice prevents local storage '
                                    'and online sync. Closing this report will '
                                    'discard it.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('session-result-view-reports'),
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.insights_outlined),
                        label: const Text('All reports'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Research measurement only. This result is not a diagnosis.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.record, required this.accuracy});

  final SessionRecord record;
  final int accuracy;

  @override
  Widget build(BuildContext context) {
    final metric = record.metric;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cells = <Widget>[
          _MetricCell(
            label: metric == null ? 'Accuracy' : 'Result',
            value: metric ?? '$accuracy%',
          ),
          _MetricCell(label: 'Accuracy', value: '$accuracy%'),
          _MetricCell(label: 'Trials', value: '${record.trials}'),
        ];
        if (constraints.maxWidth < 520) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cell in cells)
                SizedBox(width: (constraints.maxWidth - 8) / 2, child: cell),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cells[i]),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccuracyChart extends StatelessWidget {
  const _AccuracyChart({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final correct = (record.accuracy * record.trials).round();
    final incorrect = (record.trials - correct).clamp(0, record.trials);
    final theme = Theme.of(context);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: record.trials <= 0 ? 1 : record.trials.toDouble(),
          alignment: BarChartAlignment.spaceEvenly,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant,
              strokeWidth: 1,
            ),
          ),
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
                reservedSize: 34,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    value.toInt() == 0 ? 'Correct' : 'Incorrect',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [
                BarChartRodData(
                  toY: correct.toDouble(),
                  width: 42,
                  color: const Color(0xff2f9e75),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
            BarChartGroupData(
              x: 1,
              barRods: [
                BarChartRodData(
                  toY: incorrect.toDouble(),
                  width: 42,
                  color: const Color(0xffe76f51),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
