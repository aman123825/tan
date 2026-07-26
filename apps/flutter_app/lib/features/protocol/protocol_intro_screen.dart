import 'package:flutter/material.dart';

import '../../core/protocol_stage.dart';
import '../catalog/validation_badge.dart';

/// Presents the first two workflow stages — Introduction and Preview — for any
/// protocol, then hands off to the renderer (Training → Test → Results) via
/// [onStart]. Progress through the five stages is driven by the deterministic
/// [ProtocolStageController]; the full stage strip is always shown so the user
/// sees where they are in the workflow.
class ProtocolIntroScreen extends StatefulWidget {
  const ProtocolIntroScreen({
    super.key,
    required this.title,
    required this.description,
    required this.exampleText,
    required this.onStart,
    this.validationStatus = 'unvalidated',
  });

  final String title;
  final String description;
  final String exampleText;
  final String validationStatus;

  /// Invoked when the user finishes Preview and begins Training.
  final VoidCallback onStart;

  @override
  State<ProtocolIntroScreen> createState() => _ProtocolIntroScreenState();
}

class _ProtocolIntroScreenState extends State<ProtocolIntroScreen> {
  // This screen owns the first two stages; the renderer owns the rest.
  final ProtocolStageController _controller = ProtocolStageController(
    stages: const [ProtocolStage.introduction, ProtocolStage.preview],
  );

  void _next() {
    if (_controller.isLast) {
      widget.onStart();
    } else {
      setState(_controller.advance);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIntro = _controller.current == ProtocolStage.introduction;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: Chip(label: Text('RESEARCH ONLY')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _StageStrip(current: _controller.current),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                protocolStageLabel(_controller.current),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              ValidationBadge(validationStatus: widget.validationStatus),
            ],
          ),
          const SizedBox(height: 12),
          if (isIntro) ...[
            Text(widget.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            const _ResearchNotice(),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xffeaf3ff),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(widget.exampleText, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: 12),
            Text(
              'This is a preview for familiarisation — nothing is scored.',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _next,
            icon: Icon(isIntro ? Icons.visibility_outlined : Icons.play_arrow),
            label: Text(isIntro ? 'See an example' : 'Begin training'),
          ),
        ],
      ),
    );
  }
}

class _ResearchNotice extends StatelessWidget {
  const _ResearchNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffdf0dc),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xff8a5300)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Research exercise only — not a diagnosis and not a dB HL '
              'measurement. You can stop at any time; fatigue is not failure.',
              style: TextStyle(color: Color(0xff8a5300)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal strip showing all five workflow stages with the current one
/// highlighted.
class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.current});

  final ProtocolStage current;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    const stages = ProtocolStage.values;
    final currentIndex = stages.indexOf(current);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < stages.length; i++)
          _StageChip(
            label: protocolStageLabel(stages[i]),
            index: i,
            done: i < currentIndex,
            active: i == currentIndex,
            primary: primary,
          ),
      ],
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.index,
    required this.done,
    required this.active,
    required this.primary,
  });

  final String label;
  final int index;
  final bool done;
  final bool active;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    const good = Color(0xff1b7f4b);
    final Color bg = active
        ? primary
        : (done ? const Color(0x3322c55e) : const Color(0xff293548));
    final Color fg = active ? Colors.white : (done ? good : const Color(0xff94a3b8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: active ? Colors.transparent : const Color(0x33ffffff)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            const Icon(Icons.check, size: 12, color: good)
          else
            Text('${index + 1}',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
