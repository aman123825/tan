import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// A small "music equalizer" animation: five vertical bars that bounce at
/// different rates while audio is playing. Green while [active], grey when idle
/// (bars settle to a short resting height). Fixed 30×50 by default.
class AudioWaveAnimation extends StatefulWidget {
  const AudioWaveAnimation({
    super.key,
    this.active = true,
    this.width = 50,
    this.height = 30,
    this.color = const Color(0xff22c55e),
    this.idleColor = const Color(0xff8b9bb4),
  });

  final bool active;
  final double width;
  final double height;
  final Color color;
  final Color idleColor;

  @override
  State<AudioWaveAnimation> createState() => _AudioWaveAnimationState();
}

class _AudioWaveAnimationState extends State<AudioWaveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Per-bar rate + phase so the five bars move independently.
  static const List<double> _rates = <double>[1.0, 1.6, 1.25, 1.9, 1.4];
  static const List<double> _phases = <double>[0.0, 0.9, 1.8, 0.4, 1.3];
  static const int _bars = 5;

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(AudioWaveAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionActive(context);
    final color = widget.active ? widget.color : widget.idleColor;
    final barWidth = widget.width / (_bars * 2 - 1);
    if (reduced) {
      // Reduced motion: no repeating animation — a static equalizer silhouette.
      if (_controller.isAnimating) _controller.stop();
      const staticFracs = <double>[0.5, 0.85, 0.65, 0.95, 0.55];
      return Semantics(
        label: widget.active ? 'Audio playing' : 'Audio idle',
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _bars; i++)
                Container(
                  width: barWidth,
                  height: widget.height * (widget.active ? staticFracs[i] : 0.3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: widget.active ? 'Audio playing' : 'Audio idle',
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _bars; i++)
                  _bar(i, barWidth, color),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bar(int i, double barWidth, Color color) {
    double frac;
    if (widget.active) {
      final t = _controller.value * 2 * pi * _rates[i] + _phases[i];
      frac = 0.35 + 0.65 * (0.5 + 0.5 * sin(t)); // 0.35 … 1.0
    } else {
      frac = 0.3; // resting height when idle
    }
    return Container(
      width: barWidth,
      height: widget.height * frac,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(barWidth / 2),
      ),
    );
  }
}
