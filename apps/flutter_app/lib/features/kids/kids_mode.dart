import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import 'kids_theme.dart';

/// Whether Kids mode is currently active (a thin wrapper over [appSettings]).
bool get kidsModeActive => appSettings.value.kidsMode;

/// A friendly greeting card shown at the top of the home screen when Kids mode
/// is active: a big mascot and a playful "Hi there! Ready to play?" line
/// instead of clinical language.
///
/// Purely presentational — it never affects scoring or master volume.
class KidsModeBanner extends StatelessWidget {
  const KidsModeBanner({
    super.key,
    this.greeting = kKidsGreeting,
    this.mascot = kKidsMascot,
    this.subtitle = 'Pick a game and let\'s listen together!',
  });

  final String greeting;
  final String mascot;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$greeting $subtitle',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffffffff), Color(0xffe9fbef)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: KidsColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: KidsColors.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(mascot, style: const TextStyle(fontSize: 56)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    greeting,
                    style: const TextStyle(
                      color: KidsColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: KidsColors.inkSoft,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of reward stickers (⭐🌟🌈🏆) earned so far, used in Kids mode in place
/// of numeric points / streaks. [earned] stickers are bright; the rest are
/// faded placeholders to show what can still be won.
class KidsRewardRow extends StatelessWidget {
  const KidsRewardRow({
    super.key,
    required this.earned,
    this.total = 4,
    this.size = 34,
  });

  /// Number of stickers earned (0..[total]).
  final int earned;

  /// Total sticker slots to show.
  final int total;

  final double size;

  @override
  Widget build(BuildContext context) {
    final count = total <= 0 ? kRewardStickers.length : total;
    final got = earned.clamp(0, count);
    return Semantics(
      label: 'You have earned $got of $count stickers',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: i < got ? 1.0 : 0.25,
                child: Text(kidsSticker(i),
                    style: TextStyle(fontSize: size)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single celebratory sticker with a soft halo — shown on a correct answer in
/// Kids mode.
class KidsStickerReward extends StatelessWidget {
  const KidsStickerReward({super.key, required this.index, this.size = 64});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 1.4,
      height: size * 1.4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            KidsColors.accent.withValues(alpha: 0.35),
            KidsColors.accent.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Text(kidsSticker(index), style: TextStyle(fontSize: size)),
    );
  }
}
