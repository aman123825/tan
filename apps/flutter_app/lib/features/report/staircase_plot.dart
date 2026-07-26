import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A line chart of an adaptive staircase's parameter value over trials, with
/// reversals marked as dots and the estimated threshold (mean of the last N
/// reversals) drawn as a horizontal line.
///
/// It is theme-agnostic: pass the [values] the parameter took on each trial
/// (e.g. SNR in dB, gap in ms), the [reversalIndices] (trial indices where the
/// direction flipped) and the [threshold]. Purely presentational — it never
/// affects scoring or master volume.
class StaircasePlot extends StatelessWidget {
  const StaircasePlot({
    super.key,
    required this.values,
    this.reversalIndices = const <int>[],
    this.threshold,
    this.title = 'Adaptive staircase',
    this.unit = '',
    this.lineColor = const Color(0xff3b82f6),
    this.reversalColor = const Color(0xfffbbf24),
    this.thresholdColor = const Color(0xff22c55e),
    this.textColor = const Color(0xff94a3b8),
    this.height = 200,
  });

  /// The parameter value on each completed trial (x = trial index).
  final List<double> values;

  /// Trial indices (into [values]) that were reversals.
  final List<int> reversalIndices;

  /// The estimated threshold to draw as a horizontal reference line.
  final double? threshold;

  final String title;
  final String unit;
  final Color lineColor;
  final Color reversalColor;
  final Color thresholdColor;
  final Color textColor;
  final double height;

  /// A small demonstration staircase (used by the report and tests).
  factory StaircasePlot.demo({String title = 'Adaptive staircase (demo)'}) {
    return const StaircasePlot(
      values: <double>[12, 10, 8, 6, 8, 6, 4, 6, 4, 2, 4, 2, 3, 2, 3, 2],
      reversalIndices: <int>[4, 6, 9, 11, 12, 13, 14, 15],
      threshold: 2.5,
      title: 'Adaptive staircase (demo)',
      unit: 'dB SNR',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No adaptive trials to plot.',
              style: TextStyle(color: textColor, fontSize: 13)),
        ),
      );
    }

    final reversalSet = reversalIndices.toSet();
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    // Y range with a little padding (include the threshold if present).
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    if (threshold != null) {
      if (threshold! < minY) minY = threshold!;
      if (threshold! > maxY) maxY = threshold!;
    }
    final pad = ((maxY - minY).abs() * 0.15).clamp(0.5, double.infinity);
    minY -= pad;
    maxY += pad;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (values.length - 1).clamp(1, 1 << 30).toDouble(),
              minY: minY,
              maxY: maxY,
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 34),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('Trial',
                      style: TextStyle(color: textColor, fontSize: 11)),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _xInterval(values.length),
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${value.toInt() + 1}',
                          style: TextStyle(color: textColor, fontSize: 10)),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true),
              extraLinesData: threshold == null
                  ? const ExtraLinesData()
                  : ExtraLinesData(horizontalLines: [
                      HorizontalLine(
                        y: threshold!,
                        color: thresholdColor,
                        strokeWidth: 1.6,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: TextStyle(
                              color: thresholdColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                          labelResolver: (_) => 'threshold '
                              '${threshold!.toStringAsFixed(1)}'
                              '${unit.isEmpty ? '' : ' $unit'}',
                        ),
                      ),
                    ]),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: lineColor,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, bar) =>
                        reversalSet.contains(spot.x.toInt()),
                    getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                      radius: 4,
                      color: reversalColor,
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _legend(lineColor, 'Parameter${unit.isEmpty ? '' : ' ($unit)'}'),
            _legend(reversalColor, 'Reversal'),
            if (threshold != null) _legend(thresholdColor, 'Threshold'),
          ],
        ),
      ],
    );
  }

  static double _xInterval(int n) {
    if (n <= 10) return 1;
    return (n / 8).ceilToDouble();
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: textColor, fontSize: 11.5)),
        ],
      );
}
