import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/gamification.dart';
import '../../core/settings/app_settings.dart';
import '../../data/gamification_store.dart';
import '../../data/just_audio_player.dart';

/// A compact home-screen widget showing current points, the practice streak and
/// progress toward the daily goal. Rebuilds reactively when
/// [GamificationStore.listenable] changes.
class GamificationOverlay extends StatefulWidget {
  const GamificationOverlay({super.key, this.store});

  /// Injected store (tests); defaults to a real [GamificationStore].
  final GamificationStore? store;

  @override
  State<GamificationOverlay> createState() => _GamificationOverlayState();
}

class _GamificationOverlayState extends State<GamificationOverlay> {
  late final GamificationStore _store = widget.store ?? GamificationStore();

  @override
  void initState() {
    super.initState();
    // Populate the shared notifier from disk (fire-and-forget; failures are
    // swallowed inside the store so the UI simply shows the empty state).
    _store.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GamificationState>(
      valueListenable: GamificationStore.listenable,
      builder: (context, state, _) => _OverlayCard(state: state),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({required this.state});

  final GamificationState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.local_fire_department_rounded,
              iconColor: const Color(0xfff97316),
              value: '${state.currentStreak}',
              label: 'day streak',
            ),
          ),
          _divider(),
          Expanded(
            child: _Stat(
              icon: Icons.stars_rounded,
              iconColor: const Color(0xfffbbf24),
              value: '${state.points}',
              label: 'points',
            ),
          ),
          _divider(),
          Expanded(
            child: _DailyGoal(
              progress: state.dailyProgress,
              goal: kDailyGoal,
              met: state.dailyGoalMet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: const Color(0x22ffffff),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xfff1f5f9))),
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xff94a3b8))),
      ],
    );
  }
}

class _DailyGoal extends StatelessWidget {
  const _DailyGoal({
    required this.progress,
    required this.goal,
    required this.met,
  });

  final int progress;
  final int goal;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final value = goal <= 0 ? 0.0 : (progress / goal).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 4,
                  backgroundColor: const Color(0x33ffffff),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      met ? const Color(0xff22c55e) : const Color(0xff3b82f6)),
                ),
              ),
              met
                  ? const Icon(Icons.check, size: 18, color: Color(0xff22c55e))
                  : Text('$progress',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xfff1f5f9))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('$progress/$goal today',
            style: const TextStyle(fontSize: 11.5, color: Color(0xff94a3b8))),
      ],
    );
  }
}

/// A short, quiet level-up arpeggio (C5–E5–G5) for badge celebrations.
/// Fixed low amplitude — decorative feedback only, never tied to any level
/// control.
List<double> levelUpChime() => concat(<List<double>>[
      tone(seconds: 0.09, freqHz: 523.25, amp: 0.14),
      tone(seconds: 0.09, freqHz: 659.26, amp: 0.14),
      tone(seconds: 0.16, freqHz: 783.99, amp: 0.14),
    ]);

/// Shows a celebratory bottom sheet for a newly-earned [badge], with a simple
/// confetti-like burst and a short level-up chime. Completes when dismissed.
Future<void> showBadgeCelebration(
  BuildContext context,
  GamificationBadge badge, {
  AudioPort? audioPort,
}) {
  // Level-up sound: fire-and-forget; the celebration never blocks on audio
  // and playback failures (headless tests, missing plugin) are swallowed.
  try {
    unawaited((audioPort ?? JustAudioPort())
        .playWav(encodeWav16(levelUpChime()))
        .catchError((_) {}));
  } catch (_) {}
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff1e293b),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _BadgeCelebrationSheet(badge: badge),
  );
}

class _BadgeCelebrationSheet extends StatelessWidget {
  const _BadgeCelebrationSheet({required this.badge});

  final GamificationBadge badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x33ffffff),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(child: _ConfettiBurst()),
                Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff3b82f6), Color(0xff8b5cf6)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff3b82f6).withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(badge.emoji,
                      style: const TextStyle(fontSize: 52)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Badge unlocked!',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: const Color(0xff94a3b8), letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(badge.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(badge.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: const Color(0xff94a3b8))),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nice!'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight, one-shot confetti burst of animated coloured dots.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  late final List<_Particle> _particles = _buildParticles();

  static const List<Color> _palette = <Color>[
    Color(0xff3b82f6),
    Color(0xff8b5cf6),
    Color(0xff22c55e),
    Color(0xfffbbf24),
    Color(0xffef4444),
    Color(0xff06b6d4),
  ];

  List<_Particle> _buildParticles() {
    final rng = Random(7);
    return List<_Particle>.generate(28, (i) {
      final angle = rng.nextDouble() * 2 * pi;
      final speed = 60 + rng.nextDouble() * 90;
      return _Particle(
        angle: angle,
        speed: speed,
        color: _palette[i % _palette.length],
        size: 5 + rng.nextDouble() * 6,
        wobble: rng.nextDouble() * 2 * pi,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: no confetti (the badge card itself is celebration
    // enough) — WCAG 2.3.3.
    if (reduceMotionActive(context)) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(_particles, _controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.wobble,
  });

  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double wobble;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      // Outward travel eases out; a little gravity pulls the dots down.
      final dist = p.speed * (1 - (1 - t) * (1 - t));
      final dx = cos(p.angle) * dist + sin(t * 6 + p.wobble) * 4;
      final dy = sin(p.angle) * dist + 40 * t * t;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      paint.color = p.color.withOpacity(opacity);
      canvas.drawCircle(center + Offset(dx, dy), p.size * (1 - t * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
