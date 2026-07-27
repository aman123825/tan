import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sequence_entry.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Sequence-entry (digit-span) renderer.
///
/// A sequence of digits is shown, then hidden; the listener recalls it by
/// typing. Scoring is exact ordered match; span length adapts via the
/// deterministic [SequenceEntrySession]. Presentation is visual for now —
/// spoken-digit audio awaits reviewed Indian-English speech assets.
class SequenceEntryPage extends StatefulWidget {
  const SequenceEntryPage({
    super.key,
    this.moduleId = 'openset',
    this.groupId = 'digit_span',
    this.comfortableLevel = 0,
    this.lengths = const [3, 5, 7],
    this.maxTrials = 15,
    this.seed = 0,
    this.recallOrder = RecallOrder.forward,
    this.validationStatus = 'unvalidated',
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final List<int> lengths;
  final int maxTrials;
  final int seed;
  final RecallOrder recallOrder;
  final String validationStatus;
  final void Function(SequenceEntrySession session)? onCompleted;

  @override
  State<SequenceEntryPage> createState() => _SequenceEntryPageState();
}

enum _Phase { show, recall, answered }

class _SequenceEntryPageState extends State<SequenceEntryPage> {
  late final SequenceEntrySession _session = SequenceEntrySession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    lengths: widget.lengths,
    maxTrials: widget.maxTrials,
    recallOrder: widget.recallOrder,
  );
  late final SequenceEntryGenerator _generator =
      SequenceEntryGenerator(seed: widget.seed);
  final TextEditingController _input = TextEditingController();

  List<String> _target = const [];
  _Phase _phase = _Phase.show;
  DateTime? _shownAt;
  bool? _lastCorrect;
  bool _finished = false;

  final Stopwatch _sessionSw = Stopwatch()..start();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _target = _generator.next(_session.currentLength);
      _phase = _Phase.show;
      _input.clear();
      _lastCorrect = null;
      _shownAt = null;
    });
  }

  void _ready() {
    setState(() {
      _phase = _Phase.recall;
      _shownAt = DateTime.now();
    });
  }

  void _submit() {
    final response =
        _input.text.split('').where((c) => c.trim().isNotEmpty).toList();
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(_target, response, latencyMs: latency);
    setState(() {
      _lastCorrect = correct;
      _phase = _Phase.answered;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digit sequence recall')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final instruction = switch (_phase) {
      _Phase.show => 'Remember these digits.',
      _Phase.recall => widget.recallOrder == RecallOrder.backward
          ? 'Type the digits in REVERSE order.'
          : 'Type the digits you saw, in order.',
      _Phase.answered => 'How did you do?',
    };
    return TrialScaffold(
      title: widget.recallOrder == RecallOrder.backward
          ? 'Digit span (backward)'
          : 'Digit sequence recall',
      subtitle: 'Working memory',
      instruction: instruction,
      instructionIcon: Icons.visibility,
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.tag, text: 'Span ${_session.currentLength}'),
      ],
      transport: const [],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _phase == _Phase.answered ? _footer() : null,
      child: _phaseArea(),
    );
  }

  Widget _phaseArea() {
    switch (_phase) {
      case _Phase.show:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _digits(_target),
              const SizedBox(height: 28),
              FilledButton(
                  onPressed: _ready, child: const Text("I'm ready")),
            ],
          ),
        );
      case _Phase.recall:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _input,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 314',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _submit, child: const Text('Submit')),
              ],
            ),
          ),
        );
      case _Phase.answered:
        return Center(child: _digits(_target));
    }
  }

  Widget _digits(List<String> digits) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final d in digits)
          CircleAvatar(
            radius: 26,
            child: Text(d,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  Widget _footer() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, target: _target.join()),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Accuracy', value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(
            label: 'Longest span recalled', value: '${_session.maxSpan}'),
        const SizedBox(height: 12),
        Text(
          'Research measurement only — not a diagnosis. Digits are shown '
          'visually pending reviewed speech assets.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct, required this.target});

  final bool correct;
  final String target;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(correct ? Icons.check_circle : Icons.cancel,
                color: correct
                    ? const Color(0xff22c55e)
                    : const Color(0xffef4444)),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('The sequence was $target',
              style: const TextStyle(color: Color(0xff94a3b8))),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
