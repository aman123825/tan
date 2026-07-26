import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// A ring that fills clockwise from 0° → 360° over [duration] (default 2s) to
/// reassure the listener that audio is *about* to play (rather than frozen).
///
/// Purely decorative — it never affects scoring, timing measurement or master
/// volume. When [duration] elapses [onComplete] fires once.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    this.duration = const Duration(seconds: 2),
    this.size = 68,
    this.strokeWidth = 6,
    this.color = const Color(0xff3b82f6),
    this.label = 'Get ready…',
    this.onComplete,
  });

  final Duration duration;
  final double size;
  final double strokeWidth;
  final Color color;

  /// Small caption shown beneath the ring (null hides it).
  final String? label;

  /// Fires once when the ring finishes filling.
  final VoidCallback? onComplete;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete?.call();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionActive(context);
    return Semantics(
      label: 'Audio starting soon',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: reduced
                ? CustomPaint(
                    painter: _RingPainter(
                      progress: 1.0,
                      color: widget.color,
                      strokeWidth: widget.strokeWidth,
                    ),
                    child: Center(
                      child: Icon(Icons.volume_up_rounded,
                          size: widget.size * 0.34, color: widget.color),
                    ),
                  )
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _RingPainter(
                        progress: _controller.value,
                        color: widget.color,
                        strokeWidth: widget.strokeWidth,
                      ),
                      child: Center(
                        child: Icon(Icons.volume_up_rounded,
                            size: widget.size * 0.34, color: widget.color),
                      ),
                    ),
                  ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 8),
            Text(widget.label!,
                style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress; // 0..1
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0x33ffffff);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    // Full background track.
    canvas.drawCircle(center, radius, track);
    // Filled arc, clockwise from the top (−90°).
    const start = -90 * 3.1415926535 / 180;
    final sweep = progress.clamp(0.0, 1.0) * 2 * 3.1415926535;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
