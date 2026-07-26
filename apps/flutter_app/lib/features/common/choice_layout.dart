import 'package:flutter/material.dart';

/// Lays out [count] large, equally-sized choice cards that fill the space they
/// are given — the "big rectangular boxes" look shared by the interval-task
/// renderer (`Tone 1/2/3`) and the speech-in-noise 4AFC grid.
///
/// The column count is derived from [count] (3 → a single row of 3; 4 → a 2×2
/// grid; 5–6 → 3-wide; 7–9 → 3-wide; more → 4-wide) unless [columns] is given.
/// Each card is produced by [itemBuilder] and stretched to fill its cell, so
/// the boxes grow to use the full width and height available rather than
/// sitting as small fixed buttons.
///
/// Place this inside a bounded-height parent (e.g. an [Expanded]); it fills that
/// height by dividing it evenly between rows.
class ChoiceLayout extends StatelessWidget {
  const ChoiceLayout({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.columns,
    this.spacing = 12,
    this.maxWidth = 640,
  });

  /// Number of choice cards to lay out.
  final int count;

  /// Builds the card for choice [index]; the returned widget is stretched to
  /// fill its cell.
  final IndexedWidgetBuilder itemBuilder;

  /// Optional override for the automatic column count.
  final int? columns;

  /// Gap (logical px) between cards, horizontally and vertically.
  final double spacing;

  /// Caps how wide the grid grows on large screens (keeps cards a sensible
  /// size and centered).
  final double maxWidth;

  int _autoColumns() {
    if (count <= 1) return 1;
    if (count <= 3) return count; // 2 or 3 across, single row
    if (count == 4) return 2; // 2×2
    if (count <= 9) return 3; // 3-wide (covers 5, 6, 7, 8, 9)
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final cols = (columns ?? _autoColumns()).clamp(1, count);
    final rows = (count / cols).ceil();
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < cols; c++) ...[
                      if (c > 0) SizedBox(width: spacing),
                      Expanded(
                        child: (r * cols + c) < count
                            ? itemBuilder(context, r * cols + c)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
