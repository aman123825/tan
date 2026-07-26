import 'package:flutter/material.dart';

/// A compact live accuracy sparkline for use during a session.
///
/// Given the running list of per-trial correct/incorrect [results], it draws a
/// running-average line (green→red gradient by level) with a coloured dot at
/// each trial — green for a correct answer, red for a wrong one. Fixed 40px
/// tall; fills the available width. Purely informational.
class LiveChart extends StatelessWidget {
  const LiveChart({super.key, required this.results, this.height = 40});

  /// One entry per completed trial: true = correct, false = wrong.
  final List<bool> results;
  final double height;

  static const Color _good = Color(0xff22c55e);
  static const Color _bad = Color(0xffef4444);
  static const Color _line = Color(0xff3b82f6);
  static const Color _border = Color(0x33ffffff);

  @override
  Widget build(BuildContext context) {
    final pct = results.isEmpty
        ? null
        : (results.where((r) => r).length / results.length * 100).round();
    return Semantics(
      label: pct == null
          ? 'Accuracy chart, no trials yet'
          : 'Accuracy chart, $pct percent over ${results.length} trials',
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x1affffff), Color(0x0dffffff)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Expanded(
              child: results.isEmpty
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: _SparklinePainter(results),
                      size: Size.infinite,
                    ),
            ),
            if (pct != null) ...[
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: Color(0xffe2e8f0),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.results);

  final List<bool> results;

  @override
  void paint(Canvas canvas, Size size) {
    final n = results.length;
    if (n == 0) return;
    final w = size.width;
    final h = size.height;

    // Running-average trajectory, mapped so 100% = top, 0% = bottom.
    final points = <Offset>[];
    var correct = 0;
    for (var i = 0; i < n; i++) {
      if (results[i]) correct++;
      final avg = correct / (i + 1);
      final x = n == 1 ? w / 2 : w * i / (n - 1);
      final y = h - avg * h;
      points.add(Offset(x, y));
    }

    if (points.length > 1) {
      final linePaint = Paint()
        ..color = LiveChart._line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Cap the number of dots drawn so a long run stays legible.
    final dotEvery = (n / 40).ceil();
    for (var i = 0; i < n; i++) {
      if (n > 40 && i % dotEvery != 0 && i != n - 1) continue;
      final dot = Paint()
        ..color = results[i] ? LiveChart._good : LiveChart._bad
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points[i], 2.4, dot);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.results.length != results.length;
}
