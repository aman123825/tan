import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/chord_identification.dart';
import '../catalog/validation_badge.dart';

/// Music chord identification renderer: a synthesized triad plays; choose its
/// quality (Major / Minor / Diminished / Augmented). Real additive-synth audio.
class ChordIdentificationPage extends StatefulWidget {
  const ChordIdentificationPage({
    super.key,
    this.moduleId = 'music',
    this.groupId = 'chord',
    required this.comfortableLevel,
    this.maxTrials = 25,
    this.seed = 0,
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(ChordSession session)? onCompleted;

  @override
  State<ChordIdentificationPage> createState() =>
      _ChordIdentificationPageState();
}

class _ChordIdentificationPageState extends State<ChordIdentificationPage> {
  late final ChordSession _session = ChordSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final ChordGenerator _generator = ChordGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  ChordTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosen = null;
      _lastCorrect = null;
    });
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      if (_played) {
        _replays++;
      } else {
        _played = true;
      }
    });
    await _audio.playWav(encodeWav16(trial.synth()));
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(
      trial,
      index,
      latencyMs: latency,
      replays: _replays,
    );
    setState(() {
      _chosen = index;
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
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chord identification'),
        actions: [
          IconButton(
            tooltip: 'Stop',
            onPressed: _finished ? null : _finish,
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
    final trial = _current;
    if (trial == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final answered = _chosen != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Chip(
              avatar: const Icon(Icons.lock, size: 16),
              label: Text('Level $_levelPercent%'),
            ),
            const Spacer(),
            ValidationBadge(validationStatus: widget.validationStatus),
          ],
        ),
        const SizedBox(height: 4),
        Text('Trial ${_session.trialNumber} of ${widget.maxTrials}',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Text('Play the chord, then choose its quality.',
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: Semantics(
            button: true,
            label: _played ? 'Replay chord' : 'Play chord',
            child: FilledButton.icon(
              onPressed: _play,
              icon: Icon(_played ? Icons.replay : Icons.play_arrow),
              label: Text(_played ? 'Replay chord' : 'Play chord'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < trial.choices.length; i++)
                _ChoiceButton(
                  label: trial.choices[i].label,
                  enabled: _played && !answered,
                  state: _choiceState(i, trial),
                  onTap: () => _choose(i),
                ),
            ],
          ),
        ),
        if (answered) ...[
          if (_session.showsFeedback) _FeedbackLine(correct: _lastCorrect!),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _advance,
            child: Text(_session.isComplete ? 'See results' : 'Next'),
          ),
        ] else if (!_played)
          Text('Play the chord to enable the choices.',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
              textAlign: TextAlign.center),
      ],
    );
  }

  _ChoiceState _choiceState(int index, ChordTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
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
        const SizedBox(height: 12),
        Text('Research measurement only — not a diagnosis. Synthesized chords.',
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

enum _ChoiceState { neutral, correct, wrong }

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color? bg = switch (state) {
      _ChoiceState.correct => const Color(0x3322c55e),
      _ChoiceState.wrong => const Color(0x33ef4444),
      _ChoiceState.neutral => null,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg ?? const Color(0xff293548),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: enabled || state != _ChoiceState.neutral
                    ? const Color(0xffe2e8f0)
                    : Colors.white38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct});

  final bool correct;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(correct ? Icons.check_circle : Icons.cancel,
            color: correct ? const Color(0xff22c55e) : const Color(0xffef4444)),
        const SizedBox(width: 8),
        Text(correct ? 'Correct' : 'Not quite'),
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
