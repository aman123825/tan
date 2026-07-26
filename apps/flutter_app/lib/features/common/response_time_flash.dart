import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// A small "620 ms" chip that fades in then out (~1s) each time [latencyMs]
/// changes, shown next to the correct/incorrect feedback after an answer.
///
/// Informational only — response time is already recorded on the trial; this
/// just surfaces it briefly and never affects scoring or master volume.
class ResponseTimeFlash extends StatefulWidget {
  const ResponseTimeFlash({
    super.key,
    required this.latencyMs,
    this.visibleFor = const Duration(seconds: 1),
  });

  /// The response time to show, in milliseconds. Null renders nothing.
  final int? latencyMs;

  /// How long the chip stays fully visible before fading out.
  final Duration visibleFor;

  @override
  State<ResponseTimeFlash> createState() => _ResponseTimeFlashState();
}

class _ResponseTimeFlashState extends State<ResponseTimeFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.visibleFor + const Duration(milliseconds: 500),
  );

  late final Animation<double> _opacity =
      TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12),
    TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 58),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    if (widget.latencyMs != null) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(ResponseTimeFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.latencyMs != null && widget.latencyMs != oldWidget.latencyMs) {
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
    final ms = widget.latencyMs;
    if (ms == null) return const SizedBox.shrink();
    // Reduced motion: show the chip statically (it is replaced on the next
    // answer) instead of flashing in and out (WCAG 2.3.3).
    if (reduceMotionActive(context)) return _chip(ms);
    return FadeTransition(opacity: _opacity, child: _chip(ms));
  }

  Widget _chip(int ms) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22ffffff)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 13, color: Color(0xff8b9bb4)),
          const SizedBox(width: 5),
          Text('$ms ms',
              style: const TextStyle(
                  color: Color(0xff94a3b8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
