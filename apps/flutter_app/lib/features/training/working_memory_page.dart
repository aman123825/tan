import 'package:flutter/material.dart';

import '../../core/protocol_engine.dart';
import '../../core/training/working_memory.dart';
import '../common/trial_scaffold.dart';

/// Auditory Working-Memory training with two modes: digit Span (forward /
/// backward recall) and N-back. Load adapts (span length / N), never volume.
///
/// Digits are presented visually here (a spoken presentation can be layered on
/// later); the memory demand is identical.
class WorkingMemoryPage extends StatefulWidget {
  const WorkingMemoryPage({
    super.key,
    this.mode,
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.onCompleted,
  });

  /// If null, the page shows a mode chooser first.
  final WorkingMemoryMode? mode;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<WorkingMemoryPage> createState() => _WorkingMemoryPageState();
}

class _WorkingMemoryPageState extends State<WorkingMemoryPage> {
  WorkingMemoryMode? _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) {
      return _ModeChooser(onPick: (m) => setState(() => _mode = m));
    }
    if (mode == WorkingMemoryMode.span) {
      return _SpanRunner(
        maxTrials: widget.maxTrials,
        seed: widget.seed,
        onCompleted: widget.onCompleted,
      );
    }
    return _NBackRunner(
      maxTrials: widget.maxTrials,
      seed: widget.seed,
      onCompleted: widget.onCompleted,
    );
  }
}

class _ModeChooser extends StatelessWidget {
  const _ModeChooser({required this.onPick});

  final void Function(WorkingMemoryMode) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Working memory')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Choose a training mode',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                _ModeCard(
                  icon: Icons.format_list_numbered,
                  title: 'Digit span',
                  subtitle: 'Recall a sequence of digits, forward or backward.',
                  onTap: () => onPick(WorkingMemoryMode.span),
                ),
                const SizedBox(height: 14),
                _ModeCard(
                  icon: Icons.repeat,
                  title: 'N-back',
                  subtitle: 'Flag digits that match the one N steps earlier.',
                  onTap: () => onPick(WorkingMemoryMode.nBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: const Color(0xff1e293b),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x33ffffff)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, size: 30, color: const Color(0xff3b82f6)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(color: Color(0xff94a3b8))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- span --

class _SpanRunner extends StatefulWidget {
  const _SpanRunner({
    required this.maxTrials,
    required this.seed,
    this.onCompleted,
  });

  final int maxTrials;
  final int seed;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<_SpanRunner> createState() => _SpanRunnerState();
}

enum _SpanPhase { present, recall, feedback }

class _SpanRunnerState extends State<_SpanRunner> {
  late final SpanSession _session =
      SpanSession(maxTrials: widget.maxTrials, seed: widget.seed);

  SpanTrial? _current;
  _SpanPhase _phase = _SpanPhase.present;
  final List<int> _entry = <int>[];
  bool? _lastCorrect;
  bool _finished = false;
  final Stopwatch _sessionSw = Stopwatch()..start();
  DateTime? _shownAt;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _session.next();
      _phase = _SpanPhase.present;
      _entry.clear();
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  void _submit() {
    final trial = _current;
    if (trial == null || _phase != _SpanPhase.recall) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, List<int>.of(_entry), latencyMs: latency);
    setState(() {
      _phase = _SpanPhase.feedback;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session.records);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digit span')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _SummaryView(
            rows: <MapEntry<String, String>>[
              MapEntry('Trials completed', '${_session.completedTrials}'),
              MapEntry('Longest span', '${_session.maxSpan} digits'),
              MapEntry(
                  'Accuracy', '${(_session.accuracy * 100).round()}%'),
            ],
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final instruction = trial.backward
        ? 'Recall the digits in REVERSE order.'
        : 'Recall the digits in order.';
    return TrialScaffold(
      title: 'Digit span',
      subtitle: 'Working memory',
      instruction: _phase == _SpanPhase.present
          ? 'Remember these digits.'
          : instruction,
      instructionIcon: Icons.memory,
      enableShortcuts: false,
      pills: [
        MetaPill(icon: Icons.straighten, text: 'Length ${trial.length}'),
        MetaPill(
            icon: trial.backward ? Icons.swap_horiz : Icons.east,
            text: trial.backward ? 'Backward' : 'Forward'),
      ],
      transport: const [],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _phase == _SpanPhase.feedback ? _feedbackFooter() : null,
      child: _body(trial),
    );
  }

  Widget _body(SpanTrial trial) {
    switch (_phase) {
      case _SpanPhase.present:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                children: [
                  for (final d in trial.digits) _DigitChip('$d'),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _phase = _SpanPhase.recall),
                child: const Text('Recall'),
              ),
            ],
          ),
        );
      case _SpanPhase.recall:
      case _SpanPhase.feedback:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EntryDisplay(entry: _entry),
                const SizedBox(height: 16),
                _Keypad(
                  enabled: _phase == _SpanPhase.recall,
                  onDigit: (d) => setState(() => _entry.add(d)),
                  onBackspace: () => setState(() {
                    if (_entry.isNotEmpty) _entry.removeLast();
                  }),
                ),
                const SizedBox(height: 12),
                if (_phase == _SpanPhase.recall)
                  FilledButton(
                    onPressed: _entry.isEmpty ? null : _submit,
                    child: const Text('Submit'),
                  ),
              ],
            ),
          ),
        );
    }
  }

  Widget _feedbackFooter() {
    final trial = _current!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedbackLine(
            correct: _lastCorrect ?? false,
            answer: trial.expected.join(' ')),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- n-back --

class _NBackRunner extends StatefulWidget {
  const _NBackRunner({
    required this.maxTrials,
    required this.seed,
    this.onCompleted,
  });

  final int maxTrials;
  final int seed;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<_NBackRunner> createState() => _NBackRunnerState();
}

class _NBackRunnerState extends State<_NBackRunner> {
  late final NBackSession _session =
      NBackSession(maxTrials: widget.maxTrials, seed: widget.seed);

  NBackBlock? _current;
  int _index = 0;
  final Set<int> _tapped = <int>{};
  bool _blockDone = false;
  bool? _lastCorrect;
  bool _finished = false;
  final Stopwatch _sessionSw = Stopwatch()..start();
  DateTime? _shownAt;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _nextBlock();
  }

  void _nextBlock() {
    setState(() {
      _current = _session.next();
      _index = 0;
      _tapped.clear();
      _blockDone = false;
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  void _decide(bool isMatch) {
    final block = _current;
    if (block == null || _blockDone) return;
    if (isMatch) _tapped.add(_index);
    if (_index >= block.length - 1) {
      _scoreBlock();
    } else {
      setState(() => _index++);
    }
  }

  void _presentNext() {
    final block = _current;
    if (block == null || _blockDone) return;
    if (_index >= block.length - 1) {
      _scoreBlock();
    } else {
      setState(() => _index++);
    }
  }

  void _scoreBlock() {
    final block = _current!;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(block, Set<int>.of(_tapped), latencyMs: latency);
    setState(() {
      _blockDone = true;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      _finish();
    } else {
      _nextBlock();
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session.records);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('N-back')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _SummaryView(
            rows: <MapEntry<String, String>>[
              MapEntry('Blocks completed', '${_session.completedTrials}'),
              MapEntry('Highest N', '${_session.maxNReached}'),
              MapEntry(
                  'Accuracy', '${(_session.accuracy * 100).round()}%'),
            ],
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
    final block = _current;
    if (block == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isDecision = block.isDecisionPosition(_index);
    return TrialScaffold(
      title: 'N-back',
      subtitle: 'Working memory',
      instruction: isDecision
          ? 'Does this digit match the one ${block.n} step'
              '${block.n == 1 ? '' : 's'} back?'
          : 'Watch the digits.',
      instructionIcon: Icons.memory,
      enableShortcuts: false,
      pills: [
        MetaPill(icon: Icons.repeat, text: 'N = ${block.n}'),
        MetaPill(
            icon: Icons.tag, text: 'Item ${_index + 1} of ${block.length}'),
      ],
      transport: const [],
      statusLeft: 'Block ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _blockDone ? _feedbackFooter(block) : null,
      child: _body(block, isDecision),
    );
  }

  Widget _body(NBackBlock block, bool isDecision) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DigitChip('${block.stream[_index]}', big: true),
          const SizedBox(height: 28),
          if (!_blockDone)
            if (isDecision)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _decide(true),
                    icon: const Icon(Icons.check),
                    label: const Text('Match'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => _decide(false),
                    icon: const Icon(Icons.close),
                    label: const Text('No match'),
                  ),
                ],
              )
            else
              FilledButton(
                onPressed: _presentNext,
                child: const Text('Next'),
              ),
        ],
      ),
    );
  }

  Widget _feedbackFooter(NBackBlock block) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedbackLine(
          correct: _lastCorrect ?? false,
          answer: '${block.targets.length} match'
              '${block.targets.length == 1 ? '' : 'es'} in the block',
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next block'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- shared --

class _DigitChip extends StatelessWidget {
  const _DigitChip(this.text, {this.big = false});

  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: big ? 96 : 52,
      height: big ? 96 : 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(big ? 22 : 12),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: big ? 46 : 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xfff1f5f9))),
    );
  }
}

class _EntryDisplay extends StatelessWidget {
  const _EntryDisplay({required this.entry});

  final List<int> entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xff0f172a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: Text(
        entry.isEmpty ? '—' : entry.join(' '),
        style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final void Function(int digit) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback? onTap, {String? semantics}) {
      return Semantics(
        button: true,
        label: semantics ?? label,
        child: Material(
          color: const Color(0xff293548),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x33ffffff)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 64,
              height: 52,
              child: Center(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (var d = 1; d <= 9; d++) key('$d', () => onDigit(d)),
        key('0', () => onDigit(0)),
        key('⌫', onBackspace, semantics: 'Backspace'),
      ],
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct, required this.answer});

  final bool correct;
  final String answer;

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
        const SizedBox(height: 6),
        Text(answer, style: const TextStyle(color: Color(0xff94a3b8))),
      ],
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.rows, required this.onDone});

  final List<MapEntry<String, String>> rows;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(r.key, style: const TextStyle(color: Color(0xff94a3b8))),
                Text(r.value,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('Training exercise — not a diagnosis.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 20),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
