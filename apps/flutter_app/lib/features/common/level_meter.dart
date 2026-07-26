import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// A small presentation-only stimulus level meter: sweeps through the
/// pre-computed per-frame [envelope] of the stimulus that just started
/// playing, lighting segment bars by level. Purely decorative — it reflects
/// the generated buffer, never microphone input, and cannot change level.
/// Static (peak view) under reduced motion.
class StimulusLevelMeter extends StatefulWidget {
  const StimulusLevelMeter({
    super.key,
    required this.envelope,
    required this.duration,
    this.playToken = 0,
  });

  /// Per-frame level 0..1 (see `levelEnvelope`).
  final List<double> envelope;

  /// Playback duration of the whole buffer.
  final Duration duration;

  /// Bump to restart the sweep (e.g. on every play/replay).
  final int playToken;

  @override
  State<StimulusLevelMeter> createState() => _StimulusLevelMeterState();
}

class _StimulusLevelMeterState extends State<StimulusLevelMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(StimulusLevelMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playToken != widget.playToken ||
        oldWidget.envelope != widget.envelope) {
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.envelope.isEmpty) return const SizedBox.shrink();
    // Reduced motion: show the static peak profile instead of a sweep.
    if (reduceMotionActive(context)) {
      return _bar(widget.envelope.reduce((a, b) => a > b ? a : b));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final i = (_controller.value * (widget.envelope.length - 1)).round();
        final level = _controller.isCompleted ? 0.0 : widget.envelope[i];
        return _bar(level);
      },
    );
  }

  Widget _bar(double level) {
    const segments = 8;
    final lit = (level * segments).round();
    return Semantics(
      label: 'Stimulus level meter',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x1affffff), Color(0x0dffffff)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.equalizer,
                size: 14, color: Color(0xff94a3b8)),
            const SizedBox(width: 6),
            for (var s = 0; s < segments; s++)
              Container(
                width: 4,
                height: 6.0 + s * 1.4,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: s < lit
                      ? (s >= segments - 2
                          ? const Color(0xfffbbf24)
                          : const Color(0xff22c55e))
                      : const Color(0x33ffffff),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
