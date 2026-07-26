import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// A compact horizontal row of level dots for multi-level modules:
///   ● done (green)   ◉ current (blue, pulsing)   ○ locked (grey)
///
/// Shown as a pill/bar below the title breadcrumb. Pure presentation — it never
/// affects scoring or master volume.
class LevelProgressMap extends StatelessWidget {
  const LevelProgressMap({
    super.key,
    required this.currentLevel,
    required this.totalLevels,
    required this.completedLevels,
    this.dotSize = 14,
  });

  /// Zero-based index of the current level.
  final int currentLevel;

  /// Total number of levels in the module.
  final int totalLevels;

  /// Count of levels already completed (levels `[0, completedLevels)` are done).
  final int completedLevels;

  final double dotSize;

  static const Color _done = Color(0xff22c55e);
  static const Color _current = Color(0xff3b82f6);
  static const Color _locked = Color(0xff475569);

  @override
  Widget build(BuildContext context) {
    if (totalLevels <= 0) return const SizedBox.shrink();
    final reduced = reduceMotionActive(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Level ${currentLevel + 1} of $totalLevels, '
                '$completedLevels completed',
            child: Text('Level ${currentLevel + 1}/$totalLevels',
                style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          for (var i = 0; i < totalLevels; i++) ...[
            if (i > 0)
              Container(
                width: 10,
                height: 2,
                color: i <= completedLevels
                    ? _done.withOpacity(0.5)
                    : const Color(0x33ffffff),
              ),
            _dotFor(i, reduced),
          ],
        ],
      ),
    );
  }

  Widget _dotFor(int i, bool reduced) {
    if (i < completedLevels) {
      return _StaticDot(size: dotSize, color: _done, filled: true, check: true);
    }
    if (i == currentLevel) {
      if (reduced) {
        // No pulse under reduced motion — a solid current-level dot.
        return _StaticDot(size: dotSize, color: _current, filled: true);
      }
      return _PulsingDot(size: dotSize, color: _current);
    }
    return _StaticDot(size: dotSize, color: _locked, filled: false);
  }
}

class _StaticDot extends StatelessWidget {
  const _StaticDot({
    required this.size,
    required this.color,
    required this.filled,
    this.check = false,
  });

  final double size;
  final Color color;
  final bool filled;
  final bool check;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      child: check
          ? Icon(Icons.check, size: size * 0.7, color: Colors.white)
          : null,
    );
  }
}

/// The current-level dot, gently pulsing to draw the eye.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; // 0..1
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.25 + 0.45 * t),
                blurRadius: 4 + 6 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
