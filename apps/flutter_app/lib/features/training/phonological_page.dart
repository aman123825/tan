import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/phonological.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Phonological-awareness games hub: Rhyming, Sound Blending, Sound Deletion.
/// Each game runs 15 trials and reports its own accuracy. Child-friendly (uses
/// the active kids theme). Training exercise — not a diagnosis.
class PhonologicalPage extends StatefulWidget {
  const PhonologicalPage({
    super.key,
    this.maxTrials = 15,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;
  final void Function(PhonologicalSession session)? onCompleted;

  @override
  State<PhonologicalPage> createState() => _PhonologicalPageState();
}

class _PhonologicalPageState extends State<PhonologicalPage> {
  final Map<PhonoGame, double> _scores = <PhonoGame, double>{};

  Future<void> _runGame(PhonoGame game) async {
    final session = await Navigator.of(context).push<PhonologicalSession>(
      MaterialPageRoute<PhonologicalSession>(
        builder: (_) => PhonoGameRunner(
          game: game,
          maxTrials: widget.maxTrials,
          seed: widget.seed,
          audioPort: widget.audioPort,
        ),
      ),
    );
    if (session != null) {
      if (mounted) setState(() => _scores[game] = session.accuracy);
      widget.onCompleted?.call(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Phonological games')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Play with sounds',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Three listening games. Each has 15 turns.',
                  style: TextStyle(color: Color(0xff94a3b8))),
              const SizedBox(height: 18),
              for (final g in PhonoGame.values)
                _gameCard(g),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameCard(PhonoGame g) {
    final score = _scores[g];
    final emoji = switch (g) {
      PhonoGame.rhyming => '🎵',
      PhonoGame.blending => '🧩',
      PhonoGame.deletion => '✂️',
    };
    final desc = switch (g) {
      PhonoGame.rhyming => 'Find the word that rhymes.',
      PhonoGame.blending => 'Blend the sounds into a word.',
      PhonoGame.deletion => 'Take a sound away.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: g.title,
        child: Material(
          color: const Color(0x1affffff),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _runGame(g),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33ffffff)),
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.title,
                            style: const TextStyle(
                                color: Color(0xffe2e8f0),
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(desc,
                            style: const TextStyle(
                                color: Color(0xff94a3b8), fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (score != null)
                    Text('${(score * 100).round()}%',
                        style: const TextStyle(
                            color: Color(0xff22c55e),
                            fontWeight: FontWeight.w800))
                  else
                    const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs a single phonological [game] with 3AFC choices.
class PhonoGameRunner extends StatefulWidget {
  const PhonoGameRunner({
    super.key,
    required this.game,
    this.maxTrials = 15,
    this.seed = 0,
    this.audioPort,
  });

  final PhonoGame game;
  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;

  @override
  State<PhonoGameRunner> createState() => _PhonoGameRunnerState();
}

class _PhonoGameRunnerState extends State<PhonoGameRunner> {
  late final PhonologicalSession _session =
      PhonologicalSession(game: widget.game, maxTrials: widget.maxTrials);
  late final PhonologicalGenerator _generator =
      PhonologicalGenerator(widget.game, seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  final Stopwatch _sw = Stopwatch()..start();
  PhonologicalTrial? _current;
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
      _current = _generator.next();
      _chosen = null;
      _answered = false;
      _lastCorrect = null;
      _shownAt = DateTime.now();
    });
  }

  Future<void> _playCue() async {
    // No phoneme audio is bundled; play a soft attention chime so the audio
    // transport is present. The prompt/sounds are shown as text.
    try {
      await _audio.playWav(encodeWav16(tone(seconds: 0.25, freqHz: 660, amp: 0.2)));
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
      setState(() => _finished = true);
      Navigator.of(context).pop(_session);
    } else {
      _next();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final trial = _current;
    if (trial == null || _finished) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TrialScaffold(
      title: widget.game.title,
      subtitle: 'Phonological game',
      instruction: trial.prompt,
      instructionIcon: Icons.hearing,
      enableShortcuts: false,
      pills: [
        MetaPill(
            icon: Icons.emoji_events,
            text: 'Score ${(_session.accuracy * 100).round()}%'),
      ],
      transport: [
        TransportAction(
          icon: Icons.volume_up,
          label: 'Play sound',
          color: TransportColors.play,
          onTap: _playCue,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: () => Navigator.of(context).pop(_session),
        ),
      ],
      statusLeft: 'Turn ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Time ${_fmt(_sw.elapsed)}',
      onStop: () => Navigator.of(context).pop(_session),
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainingFeedbackLine(
                    correct: _lastCorrect ?? false, answer: trial.answer),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See score' : 'Next'),
                ),
              ],
            )
          : null,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trial.speak.length > 1)
              Wrap(
                spacing: 10,
                children: [
                  for (final s in trial.speak)
                    Chip(label: Text('/$s/',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < trial.choices.length; i++)
                  SizedBox(
                    width: 150,
                    height: 84,
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
}
