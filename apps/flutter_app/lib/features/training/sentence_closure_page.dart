import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/sentence_closure.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Auditory-verbal sentence closure: a sentence is shown with its final word
/// masked (a noise burst plays where the word would be); the listener uses
/// context to pick the completing word (4AFC). Trains top-down linguistic
/// prediction. Training — not a diagnosis; master volume is never changed.
class SentenceClosurePage extends StatefulWidget {
  const SentenceClosurePage({
    super.key,
    this.comfortableLevel = 0.4,
    this.maxTrials = 20,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;
  final void Function(SentenceClosureSession session)? onCompleted;

  @override
  State<SentenceClosurePage> createState() => _SentenceClosurePageState();
}

class _SentenceClosurePageState extends State<SentenceClosurePage> {
  late final SentenceClosureSession _session =
      SentenceClosureSession(maxTrials: widget.maxTrials);
  late final SentenceClosureGenerator _generator =
      SentenceClosureGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  final Stopwatch _sw = Stopwatch()..start();
  SentenceClosureTrial? _current;
  int? _chosen;
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
      // The response-set size adapts 2-up/1-down (2 → 8 choices).
      _current = _generator.next(choiceCount: _session.currentChoiceCount);
      _chosen = null;
      _answered = false;
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  Future<void> _playMask() async {
    // The masked final word is represented by a short noise burst.
    try {
      await _audio
          .playWav(encodeWav16(whiteNoise(seconds: 0.5, amp: 0.2, seed: 3)));
    } catch (_) {}
  }

  void _choose(int i) {
    final trial = _current;
    if (trial == null || _answered) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(trial, i, latencyMs: latency);
    setState(() {
      _chosen = i;
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
      title: 'Sentence closure',
      subtitle: 'Language prediction',
      instruction: 'Pick the word that best completes the sentence.',
      instructionIcon: Icons.short_text,
      enableShortcuts: false,
      pills: [
        MetaPill(
            icon: Icons.emoji_events,
            text: 'Score ${(_session.accuracy * 100).round()}%'),
        MetaPill(
            icon: Icons.tune,
            text: 'Choices: ${trial.choices.length} (adaptive)'),
        const MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.volume_up,
          label: 'Play',
          color: TransportColors.play,
          onTap: _playMask,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainingFeedbackLine(
                    correct: _lastCorrect ?? false, answer: trial.answer),
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
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x1affffff), Color(0x0dffffff)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33ffffff)),
              ),
              child: Text(
                trial.maskedFrame,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < trial.choices.length; i++)
                  SizedBox(
                    width: 150,
                    height: 76,
                    child: TrainingChoiceTile(
                      label: trial.choices[i],
                      enabled: !_answered,
                      state: !_answered
                          ? TrainingChoiceState.neutral
                          : (i == trial.correctIndex
                              ? TrainingChoiceState.correct
                              : (i == _chosen
                                  ? TrainingChoiceState.wrong
                                  : TrainingChoiceState.neutral)),
                      onTap: () => _choose(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sentence closure')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Session summary',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Questions', value: '${_session.completedTrials}'),
            TrainingSummaryRow(
                label: 'Accuracy',
                value: '${(_session.accuracy * 100).round()}%'),
            TrainingSummaryRow(
                label: 'Largest response set reached',
                value: '${_session.maxChoicesReached} choices'),
            const SizedBox(height: 14),
            const Text(
                'Difficulty adapted on the number of answer choices '
                '(2 → 8). Training exercise — not a diagnosis.',
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
