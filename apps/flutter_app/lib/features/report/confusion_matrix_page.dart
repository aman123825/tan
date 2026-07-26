import 'package:flutter/material.dart';

import '../../core/confusion_matrix.dart';

/// Colour palette for [ConfusionMatrixView] so it can render on the dark app
/// surface or inside the light "paper" report.
class ConfusionPalette {
  const ConfusionPalette({
    required this.ink,
    required this.muted,
    required this.border,
    required this.cellEmpty,
  });

  final Color ink;
  final Color muted;
  final Color border;
  final Color cellEmpty;

  static const ConfusionPalette dark = ConfusionPalette(
    ink: Color(0xffe2e8f0),
    muted: Color(0xff94a3b8),
    border: Color(0x33ffffff),
    cellEmpty: Color(0xff1e293b),
  );

  static const ConfusionPalette light = ConfusionPalette(
    ink: Color(0xff0f172a),
    muted: Color(0xff475569),
    border: Color(0xffcbd5e1),
    cellEmpty: Color(0xfff1f5f9),
  );
}

/// Renders a [ConfusionMatrix] as a colour-coded grid (rows = presented target,
/// columns = the listener's response). The diagonal is correct answers (green
/// intensity by count); off-diagonal cells are errors (red intensity). The
/// three most frequent confusions are outlined, and a plain-language summary is
/// shown above the grid.
class ConfusionMatrixView extends StatelessWidget {
  const ConfusionMatrixView({
    super.key,
    required this.matrix,
    this.palette = ConfusionPalette.dark,
  });

  final ConfusionMatrix matrix;
  final ConfusionPalette palette;

  static const Color _good = Color(0xff22c55e);
  static const Color _bad = Color(0xffef4444);

  @override
  Widget build(BuildContext context) {
    final labels = matrix.labels;
    if (labels.isEmpty) {
      return Text('No responses recorded yet.',
          style: TextStyle(color: palette.muted));
    }
    final top = matrix.topConfusions(3);
    final topSet = {for (final p in top) '${p.target}→${p.response}'};
    final maxCount = matrix.maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          matrix.summary(),
          style: TextStyle(
              color: palette.ink, fontWeight: FontWeight.w700, height: 1.35),
        ),
        const SizedBox(height: 6),
        Text(
          '${matrix.correct}/${matrix.total} correct · ${matrix.errorCount} errors. '
          'Rows = what was played, columns = what you chose.',
          style: TextStyle(color: palette.muted, fontSize: 12.5),
        ),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in top)
                _ConfusionChip(
                  text: '${p.target} → ${p.response}  ×${p.count}',
                  palette: palette,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: _grid(labels, topSet, maxCount),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<String> labels, Set<String> topSet, int maxCount) {
    const double cell = 40;
    const double head = 56;

    Widget headerCell(String text) => Container(
          width: cell,
          height: head,
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: palette.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ),
        );

    Widget rowLabel(String text) => Container(
          width: head,
          height: cell,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        );

    Widget dataCell(String target, String response) {
      final c = matrix.count(target, response);
      final diagonal = target == response;
      final intensity = maxCount == 0 ? 0.0 : c / maxCount;
      Color bg = palette.cellEmpty;
      if (c > 0) {
        final base = diagonal ? _good : _bad;
        bg = Color.alphaBlend(
            base.withValues(alpha: 0.15 + 0.65 * intensity), palette.cellEmpty);
      }
      final highlighted = topSet.contains('$target→$response');
      return Container(
        width: cell,
        height: cell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: highlighted ? _bad : palette.border,
            width: highlighted ? 2 : 0.5,
          ),
        ),
        child: Text(
          c == 0 ? '' : '$c',
          style: TextStyle(
            color: c == 0 ? palette.muted : palette.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column header row.
        Row(
          children: [
            const SizedBox(width: head, height: head),
            for (final resp in labels) headerCell(resp),
          ],
        ),
        for (final target in labels)
          Row(
            children: [
              rowLabel(target),
              for (final resp in labels) dataCell(target, resp),
            ],
          ),
      ],
    );
  }
}

class _ConfusionChip extends StatelessWidget {
  const _ConfusionChip({required this.text, required this.palette});

  final String text;
  final ConfusionPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x33ef4444),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x55ef4444)),
      ),
      child: Text(text,
          style: TextStyle(
              color: palette.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Full-screen dark-glass confusion-matrix report for an identification run.
class ConfusionMatrixPage extends StatelessWidget {
  const ConfusionMatrixPage({
    super.key,
    required this.matrix,
    this.title = 'Confusion matrix',
  });

  final ConfusionMatrix matrix;
  final String title;

  /// A representative sample matrix (for `?preview=confusion` and the report).
  static ConfusionMatrix sample() {
    final m = ConfusionMatrix();
    void add(String t, String r, int n) {
      for (var i = 0; i < n; i++) {
        m.record(t, r);
      }
    }
    add('b', 'b', 6);
    add('b', 'p', 4);
    add('p', 'p', 7);
    add('p', 'b', 3);
    add('d', 'd', 8);
    add('d', 't', 2);
    add('t', 't', 9);
    add('g', 'g', 7);
    add('g', 'k', 3);
    add('k', 'k', 8);
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x1affffff), Color(0x0dffffff)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x33ffffff)),
              ),
              child: ConfusionMatrixView(matrix: matrix),
            ),
            const SizedBox(height: 14),
            const Text(
              'Research summary only — not a diagnosis. Confusions reflect the '
              'demonstration stimuli on uncalibrated audio.',
              style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
