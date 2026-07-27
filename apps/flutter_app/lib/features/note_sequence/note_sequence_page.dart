import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/sequence_entry.dart';
import '../catalog/validation_badge.dart';

/// Builds the audio for a symbol sequence (notes or instruments).
typedef SequenceSynth = List<double> Function(List<String> symbols);

/// Sequence-recall renderer over an arbitrary symbol set: a short sequence
/// plays (synthesized notes or instrument timbres); the listener reproduces it
/// by tapping the symbols in order. Span length adapts via the deterministic
/// [SequenceEntrySession].
class SymbolSequencePage extends StatefulWidget {
  const SymbolSequencePage({
    super.key,
    required this.moduleId,
    required this.groupId,
    required this.comfortableLevel,
    required this.symbols,
    required this.synth,
    this.labelFor,
    this.title = 'Sequence recall',
    this.playNoun = 'sequence',
    this.lengths = const [2, 3, 5, 7],
    this.maxTrials = 15,
    this.seed = 0,
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final List<String> symbols;
  final SequenceSynth synth;
  final String Function(String symbol)? labelFor;
  final String title;
  final String playNoun;
  final List<int> lengths;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(SequenceEntrySession session)? onCompleted;

  @override
  State<SymbolSequencePage> createState() => _SymbolSequencePageState();
}

class _SymbolSequencePageState extends State<SymbolSequencePage> {
  late final SequenceEntrySession _session = SequenceEntrySession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    lengths: widget.lengths,
    maxTrials: widget.maxTrials,
  );
  late final SymbolSequenceGenerator _generator =
      SymbolSequenceGenerator(widget.symbols, seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  List<String> _target = const [];
  final List<String> _entered = <String>[];
  DateTime? _shownAt;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  String _label(String symbol) =>
      widget.labelFor != null ? widget.labelFor!(symbol) : symbol;

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _target = _generator.next(_session.currentLength);
      _entered.clear();
      _played = false;
      _answered = false;
      _lastCorrect = null;
      _shownAt = null;
    });
  }

  Future<void> _play() async {
    setState(() {
      _played = true;
      _shownAt ??= DateTime.now();
    });
    await _audio.playWav(encodeWav16(widget.synth(_target)));
  }

  void _tap(String symbol) {
    if (!_played || _answered) return;
    setState(() => _entered.add(symbol));
  }

  void _undo() {
    if (_answered || _entered.isEmpty) return;
    setState(() => _entered.removeLast());
  }

  void _submit() {
    if (!_played || _answered || _entered.isEmpty) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(
      _target,
      List<String>.of(_entered),
      latencyMs: latency,
    );
    setState(() {
      _answered = true;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      if (!_finished) {
        setState(() => _finished = true);
        widget.onCompleted?.call(_session);
      }
    } else {
      _nextTrial();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Stop',
            onPressed: _finished
                ? null
                : () {
                    if (!_finished) {
                      setState(() => _finished = true);
                      widget.onCompleted?.call(_session);
                    }
                  },
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _finished ? _buildResults(context) : _buildTrial(context),
      ),
    );
  }

  Widget _buildTrial(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Chip(label: Text('Length ${_session.currentLength}')),
            const SizedBox(width: 8),
            Chip(
              avatar: const Icon(Icons.lock, size: 16),
              label: Text('Level $_levelPercent%'),
            ),
            const Spacer(),
            ValidationBadge(validationStatus: widget.validationStatus),
          ],
        ),
        const SizedBox(height: 6),
        Text('Trial ${_session.trialNumber} of ${widget.maxTrials}',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Text('Play the ${widget.playNoun}, then tap it back in the same order.',
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: Semantics(
            button: true,
            label: _played
                ? 'Replay ${widget.playNoun}'
                : 'Play ${widget.playNoun}',
            child: FilledButton.icon(
              onPressed: _play,
              icon: Icon(_played ? Icons.replay : Icons.play_arrow),
              label: Text(_played
                  ? 'Replay ${widget.playNoun}'
                  : 'Play ${widget.playNoun}'),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 40,
          child: Center(
            child: _entered.isEmpty
                ? Text('Your answer appears here',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white38))
                : Wrap(
                    spacing: 8,
                    children: [
                      for (final s in _entered)
                        Chip(
                            label: Text(_label(s)),
                            visualDensity: VisualDensity.compact),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final symbol in widget.symbols)
              Semantics(
                button: true,
                enabled: _played && !_answered,
                label: _label(symbol),
                child: FilledButton.tonal(
                  onPressed: _played && !_answered ? () => _tap(symbol) : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(_label(symbol),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_answered)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _entered.isNotEmpty && !_answered ? _undo : null,
                icon: const Icon(Icons.backspace_outlined),
                label: const Text('Undo'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _played && _entered.isNotEmpty ? _submit : null,
                child: const Text('Submit'),
              ),
            ],
          )
        else ...[
          if (_session.showsFeedback)
            _FeedbackLine(
                correct: _lastCorrect!, target: _target.map(_label).join(' ')),
          const SizedBox(height: 8),
          Center(
            child: FilledButton(
              onPressed: _advance,
              child: Text(_session.isComplete ? 'See results' : 'Next'),
            ),
          ),
        ],
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
            label: 'Longest sequence recalled', value: '${_session.maxSpan}'),
        const SizedBox(height: 12),
        Text('Research measurement only — not a diagnosis. Synthesized audio.',
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8))),
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
