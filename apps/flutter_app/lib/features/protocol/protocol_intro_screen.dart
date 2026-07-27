import 'package:flutter/material.dart';

import '../../core/protocol_stage.dart';
import '../catalog/validation_badge.dart';

/// Introduction and familiarisation preview shown before a listening task.
///
/// Both stages are optional. A listener who already knows the task can start
/// immediately without stepping through the introduction.
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
  final VoidCallback onStart;

  @override
  State<ProtocolIntroScreen> createState() => _ProtocolIntroScreenState();
}

class _ProtocolIntroScreenState extends State<ProtocolIntroScreen> {
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
        actions: [
          TextButton.icon(
            key: const Key('protocol-intro-skip'),
            onPressed: widget.onStart,
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip to test'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _StageProgress(current: _controller.current),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isIntro ? Icons.menu_book_outlined : Icons.hearing,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          protocolStageLabel(_controller.current),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isIntro
                              ? 'Understand the task before any audio plays.'
                              : 'Preview the response format. Nothing is scored.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ValidationBadge(validationStatus: widget.validationStatus),
                ],
              ),
              const SizedBox(height: 20),
              if (isIntro) ...[
                Text(
                  widget.description,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 18),
                const _ResearchNotice(),
              ] else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    widget.exampleText,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _next,
                icon: Icon(
                    isIntro ? Icons.visibility_outlined : Icons.play_arrow),
                label: Text(isIntro ? 'See an example' : 'Begin training'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: widget.onStart,
                child: const Text('I know this task - start now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResearchNotice extends StatelessWidget {
  const _ResearchNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Research exercise only - not a diagnosis and not a dB HL '
              'measurement. You can stop at any time; fatigue is not failure.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageProgress extends StatelessWidget {
  const _StageProgress({required this.current});

  final ProtocolStage current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const stages = ProtocolStage.values;
    final currentIndex = stages.indexOf(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: (currentIndex + 1) / stages.length,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            for (var i = 0; i < stages.length; i++)
              Expanded(
                child: Text(
                  protocolStageLabel(stages[i]),
                  textAlign: i == 0
                      ? TextAlign.left
                      : i == stages.length - 1
                          ? TextAlign.right
                          : TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        i == currentIndex ? FontWeight.w800 : FontWeight.w600,
                    color: i <= currentIndex
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
