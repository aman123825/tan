import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/speech_in_noise.dart';
import '../../core/training/scene_training.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Word pool for scene training (matches the bundled demo speech assets).
const List<String> kSceneWordPool = <String>[
  'bell', 'ball', 'bat', 'bag', 'pen', 'pin', 'cup', 'cap',
];

/// Real-world scene listening training hub: Restaurant, Classroom, Phone call.
/// Each scene mixes a target word into its background at an adaptive SNR and the
/// listener identifies the word from four choices (10 trials/scene). Training —
/// not a diagnosis; only SNR adapts, never master volume.
class ScenePage extends StatefulWidget {
  const ScenePage({
    super.key,
    this.comfortableLevel = 0.4,
    this.trialsPerScene = 10,
    this.seed = 0,
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int trialsPerScene;
  final int seed;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(SceneTrainingSession session)? onCompleted;

  @override
  State<ScenePage> createState() => _ScenePageState();
}

class _ScenePageState extends State<ScenePage> {
  final Map<TrainingScene, double?> _thresholds = <TrainingScene, double?>{};

  Future<void> _run(TrainingScene scene) async {
    final session = await Navigator.of(context).push<SceneTrainingSession>(
      MaterialPageRoute<SceneTrainingSession>(
        builder: (_) => SceneRunner(
          scene: scene,
          trials: widget.trialsPerScene,
          seed: widget.seed,
          audioPort: widget.audioPort,
          assetLoader: widget.assetLoader,
        ),
      ),
    );
    if (session != null) {
      if (mounted) setState(() => _thresholds[scene] = session.thresholdSnrDb);
      widget.onCompleted?.call(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Real-world scenes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Listen in real places',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Follow the talker in each scene. The noise adapts.',
                  style: TextStyle(color: Color(0xff94a3b8))),
              const SizedBox(height: 18),
              for (final s in TrainingScene.values) _sceneCard(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sceneCard(TrainingScene s) {
    final t = _thresholds[s];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: s.title,
        child: Material(
          color: const Color(0x1affffff),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _run(s),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33ffffff)),
              ),
              child: Row(
                children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: const TextStyle(
                                color: Color(0xffe2e8f0),
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(s.description,
                            style: const TextStyle(
                                color: Color(0xff94a3b8), fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (t != null)
                    Text('${t.toStringAsFixed(1)} dB',
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

/// Runs one scene: adaptive-SNR 4AFC word identification in the scene's noise.
class SceneRunner extends StatefulWidget {
  const SceneRunner({
    super.key,
    required this.scene,
    this.trials = 10,
    this.seed = 0,
    this.audioPort,
    this.assetLoader,
  });

  final TrainingScene scene;
  final int trials;
  final int seed;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;

  @override
  State<SceneRunner> createState() => _SceneRunnerState();
}

class _SceneRunnerState extends State<SceneRunner> {
  late final SceneTrainingSession _session =
      SceneTrainingSession(scene: widget.scene, maxTrials: widget.trials);
  late final FourAfcGenerator _generator =
      FourAfcGenerator(kSceneWordPool, seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  final Stopwatch _sw = Stopwatch()..start();
  FourAlternativeTrial? _current;
  int? _chosen;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
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
      final decoded =
          decodeWav16(await _loadAsset('assets/stimuli/speech/word_${trial.target}.wav'));
      final rate = decoded.sampleRate;
      final bg = sceneBackground(
        widget.scene,
        seconds: decoded.samples.length / rate,
        seed: widget.seed + _session.completedTrials,
        sampleRate: rate,
      );
      var mixed = mixAtSnr(decoded.samples, bg, _session.currentSnrDb);
      if (widget.scene == TrainingScene.phone) {
        mixed = bandPass(mixed, 300, 3200, rate);
      }
      await _audio.playWav(encodeWav16(mixed, sampleRate: rate));
    } catch (_) {
      // Missing asset / playback failure must not block the exercise.
    }
  }

  void _choose(int i) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
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
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TrialScaffold(
      title: widget.scene.title,
      subtitle: 'Scene training',
      instruction: _played
          ? 'Which word did you hear?'
          : 'Press play to hear the word in the ${widget.scene.title.toLowerCase()}.',
      instructionIcon: Icons.hearing,
      enableShortcuts: false,
      pills: [
        MetaPill(text: '${widget.scene.emoji} ${widget.scene.title}'),
        MetaPill(
            icon: Icons.graphic_eq,
            text: 'SNR ${_session.currentSnrDb.toStringAsFixed(0)} dB'),
        const MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_played && !_answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay',
          color: TransportColors.replay,
          onTap: (_played && !_answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: () => Navigator.of(context).pop(_session),
        ),
      ],
      statusLeft: 'Trial ${_session.trialNumber} of ${widget.trials}',
      statusRight: 'Time ${_fmt(_sw.elapsed)}',
      onStop: () => Navigator.of(context).pop(_session),
      footer: _answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainingFeedbackLine(
                    correct: _lastCorrect ?? false, answer: trial.target),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: Center(
        child: Wrap(
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
                  enabled: _played && !_answered,
                  state: !_answered
                      ? TrainingChoiceState.neutral
                      : (i == trial.targetIndex
                          ? TrainingChoiceState.correct
                          : (i == _chosen
                              ? TrainingChoiceState.wrong
                              : TrainingChoiceState.neutral)),
                  onTap: () => _choose(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
