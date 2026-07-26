import 'package:flutter/material.dart';

import '../../core/fatigue.dart';

/// The optional post-session self-reports. All informational only — they
/// never change scoring, adaptation or master volume.
class PostSessionRatings {
  const PostSessionRatings({this.fatigue, this.confidence, this.label});

  /// 0–10 fatigue self-report, or null if skipped.
  final int? fatigue;

  /// 0–10 "how confident were you in your answers?" self-report, or null if
  /// not answered. A metacognition signal only.
  final int? confidence;

  /// Optional free-text session name ("after school, noisy room"), shown in
  /// the history and A/B comparison lists.
  final String? label;
}

/// Post-session prompt: fatigue (0–10) plus an optional confidence rating.
/// Returns the ratings, or null if the listener skips the sheet entirely.
/// Both values are informational only and never change scoring or volume.
Future<PostSessionRatings?> showFatigueSheet(BuildContext context,
    {int initial = 0}) {
  return showModalBottomSheet<PostSessionRatings>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xff1e293b),
    builder: (ctx) => FatigueSheet(
      initial: initial,
      askConfidence: true,
      askLabel: true,
      onSubmit: (_) {},
      onSubmitRatings: (r) => Navigator.of(ctx).pop(r),
      onSkip: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// The fatigue rating control. Kept as a standalone widget so it is testable
/// without a navigator.
class FatigueSheet extends StatefulWidget {
  const FatigueSheet({
    super.key,
    required this.onSubmit,
    this.onSubmitRatings,
    this.onSkip,
    this.initial = 0,
    this.askConfidence = false,
    this.askLabel = false,
  });

  final void Function(int rating) onSubmit;

  /// When provided, Save also reports the full [PostSessionRatings]
  /// (fatigue + optional confidence).
  final void Function(PostSessionRatings ratings)? onSubmitRatings;
  final VoidCallback? onSkip;
  final int initial;

  /// Whether to show the optional confidence question (off by default so the
  /// plain fatigue-only sheet stays unchanged).
  final bool askConfidence;

  /// Whether to show the optional session-name field.
  final bool askLabel;

  @override
  State<FatigueSheet> createState() => _FatigueSheetState();
}

class _FatigueSheetState extends State<FatigueSheet> {
  late int _rating = FatigueScale.clamp(widget.initial);

  /// Null until the listener chooses — confidence is opt-in per question.
  int? _confidence;

  final TextEditingController _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How tired do your ears and attention feel?',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'This is optional and never affects your scores. '
              'Fatigue is not failure.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8))),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = FatigueScale.min; i <= FatigueScale.max; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: _rating == i,
                  onSelected: (_) => setState(() => _rating = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('${FatigueScale.bucket(_rating)} ($_rating/10)',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (widget.askConfidence) ...[
            const SizedBox(height: 16),
            Text('How confident were you in your answers?',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Optional — 0 = guessing, 10 = certain.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
            const SizedBox(height: 12),
            Semantics(
              label: 'Confidence rating, 0 guessing to 10 certain',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i <= 10; i++)
                    ChoiceChip(
                      key: Key('confidence-$i'),
                      label: Text('$i'),
                      selected: _confidence == i,
                      onSelected: (sel) =>
                          setState(() => _confidence = sel ? i : null),
                    ),
                ],
              ),
            ),
          ],
          if (widget.askLabel) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('session-label'),
              controller: _label,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Name this session (optional)',
                hintText: 'e.g. after school, noisy room',
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onSkip != null)
                TextButton(onPressed: widget.onSkip, child: const Text('Skip')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onSubmit(_rating);
                  final label = _label.text.trim();
                  widget.onSubmitRatings?.call(PostSessionRatings(
                    fatigue: _rating,
                    confidence: _confidence,
                    label: label.isEmpty ? null : label,
                  ));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
