import 'package:flutter/material.dart';

import '../../core/norms.dart';

export '../../core/norms.dart';

/// Renders a [NormResult] as a cited, colour-coded panel for a results screen.
///
/// Presentation only. It restates the module's research-only interpretation and
/// always shows the citation, so a result is never presented as a diagnosis.
class NormTile extends StatelessWidget {
  const NormTile(this.result, {super.key});

  final NormResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (result.isInsufficient) {
      return Row(
        children: [
          const Icon(Icons.hourglass_empty, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(result.detail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
        ],
      );
    }
    final (Color color, IconData icon) = switch (result.band) {
      NormBand.betterThanTypical => (const Color(0xff1b7f4b), Icons.trending_up),
      NormBand.withinTypical => (const Color(0xff1f7a8c), Icons.check_circle),
      NormBand.slightlyBelowTypical => (
          const Color(0xffb26a00),
          Icons.info_outline
        ),
      NormBand.belowTypical => (const Color(0xffb3261e), Icons.trending_down),
      NormBand.insufficient => (Colors.grey, Icons.hourglass_empty),
    };
    return Semantics(
      label: 'Research interpretation: ${result.label}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          // ignore: deprecated_member_use
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(result.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(result.detail, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text('Reference: ${result.citation}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
            const SizedBox(height: 2),
            Text(
              'Research-only, illustrative — not a diagnosis. Demonstration '
              'stimuli on uncalibrated audio.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}
