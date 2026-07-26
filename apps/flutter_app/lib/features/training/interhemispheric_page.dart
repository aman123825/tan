import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/interhemispheric.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Interhemispheric-transfer training: a short/long rhythm is played to ONE ear
/// (stereo — wired headphones needed) and reproduced with the OPPOSITE hand by
/// tapping short/long buttons. Trains the corpus-callosum pathway. Training —
/// not a diagnosis; master volume is never changed.
class InterhemisphericPage extends StatefulWidget {
  const InterhemisphericPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.maxTrials = 15,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;
  final void Function(InterhemisphericSession session)? onCompleted;

  @override
  State<InterhemisphericPage> createState() => _InterhemisphericPageState();
}

class _InterhemisphericPageState extends State<InterhemisphericPage> {
  late final InterhemisphericSession _session =
      InterhemisphericSession(maxTrials: widget.maxTrials);
  late final InterhemisphericGenerator _generator =
      InterhemisphericGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  final Stopwatch _sw = Stopwatch()..start();
  InterhemisphericTrial? _current;
  final List<Beat> _tapped = <Beat>[];
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    setState(() {
      _current = _generator.next(_session.currentLevel);
      _tapped.clear();
      _played = false;
      _answered = false;
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() => _played = true);
    try {
      final mono = rhythmSamples(trial.pattern);
      final sil = List<double>.filled(mono.length, 0.0);
      final left = trial.ear == Ear.left ? mono : sil;
      final right = trial.ear == Ear.right ? mono : sil;
      await _audio.playWav(encodeWavStereo16(left, right));
    } catch (_) {
      // ignore playback failure
    }
  }

  void _tap(Beat b) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    setState(() => _tapped.add(b));
    if (_tapped.length >= trial.pattern.length) {
      _evaluate();
    }
  }

  void _undo() {
    if (_answered || _tapped.isEmpty) return;
    setState(() => _tapped.removeLast());
  }

  void _evaluate() {
    final trial = _current;
    if (trial == null || _answered) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, List<Beat>.of(_tapped), latencyMs: latency);
    setState(() {
      _answered = true;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
      _finish();
    } else {
      _next();
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _results(context);
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TrialScaffold(
      title: 'Interhemispheric transfer',
      subtitle: 'Integration training',
      instruction: _played
          ? 'Tap the rhythm with your ${trial.ear.oppositeHand} hand.'
          : 'Listen in your ${trial.ear.label} ear.',
      instructionIcon: Icons.hearing,
      enableShortcuts: false,
      pills: [
        MetaPill(icon: Icons.hearing, text: '${trial.ear.label} ear'),
        MetaPill(
            icon: Icons.back_hand, text: '${trial.ear.oppositeHand} hand'),
        MetaPill(icon: Icons.timeline, text: '${trial.pattern.length} beats'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play rhythm',
          color: TransportColors.play,
          onTap: _play,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Trial ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainingFeedbackLine(
                  correct: _lastCorrect ?? false,
                  answer: trial.pattern.map((b) => b.name).join(' – '),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tapped-so-far display.
            SizedBox(
              height: 40,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final b in _tapped)
                    Chip(
                      label: Text(b == Beat.short ? '•' : '▬',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _beatButton('Short  •', () => _tap(Beat.short)),
                const SizedBox(width: 16),
                _beatButton('Long  ▬', () => _tap(Beat.long)),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: (!_answered && _tapped.isNotEmpty) ? _undo : null,
              icon: const Icon(Icons.backspace_outlined),
              label: const Text('Undo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _beatButton(String label, VoidCallback onTap) => SizedBox(
        width: 140,
        height: 90,
        child: Semantics(
          button: true,
          label: label,
          child: FilledButton(
            onPressed: (_played && !_answered) ? onTap : null,
            child: Text(label, style: const TextStyle(fontSize: 18)),
          ),
        ),
      );

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Interhemispheric transfer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Session summary',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Trials completed',
                value: '${_session.completedTrials}'),
            TrainingSummaryRow(
                label: 'Rhythm reproduced',
                value: '${(_session.elementAccuracy * 100).round()}%'),
            TrainingSummaryRow(
                label: 'Exact patterns',
                value: '${(_session.accuracy * 100).round()}%'),
            TrainingSummaryRow(
                label: 'Longest pattern',
                value: '${_session.maxLevelReached} beats'),
            const SizedBox(height: 14),
            const Text('Training exercise — not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_session),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
