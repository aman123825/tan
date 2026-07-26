import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/prosody.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/encouragement.dart';
import '../common/spectrogram_widget.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Prosody training: tell apart question vs statement intonation, which word is
/// stressed, or the emotional tone of a synthesized utterance. 20 adaptive
/// trials per task; the prosodic cue shrinks as the listener improves.
///
/// Synthesized demonstration speech (`demo_only`), not validated clinical
/// stimuli. Adaptation changes only the cue salience, never master volume.
class ProsodyPage extends StatefulWidget {
  const ProsodyPage({
    super.key,
    this.audioPort,
    this.maxTrials = 20,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.onCompleted,
  });

  final AudioPort? audioPort;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final void Function(List<TrialRecord> records)? onCompleted;

  @override
  State<ProsodyPage> createState() => _ProsodyPageState();
}

enum _Stage { pick, training, results }

class _ProsodyPageState extends State<ProsodyPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  _Stage _stage = _Stage.pick;
  ProsodyTask _task = ProsodyTask.questionStatement;
  late ProsodySession _session;
  late ProsodyGenerator _generator;

  ProsodyTrial? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _isPlaying = false;
  int? _chosen;
  bool? _lastCorrect;
  String? _encouragement;
  List<double> _lastSamples = const <double>[];
  Timer? _autoPlayTimer;

  final List<TrialRecord> _records = <TrialRecord>[];
  final Stopwatch _sw = Stopwatch();

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _startTask(ProsodyTask task) {
    _task = task;
    _session = ProsodySession(task: task, maxTrials: widget.maxTrials);
    _generator = ProsodyGenerator(task: task, seed: widget.seed);
    _records.clear();
    _sw
      ..reset()
      ..start();
    setState(() => _stage = _Stage.training);
    _nextTrial();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next(_session.cue);
      _shownAt = DateTime.now();
      _played = false;
      _chosen = null;
      _lastCorrect = null;
    });
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_played) _play();
    });
  }

  Future<void> _play() async {
    final trial = _current;
    if (trial == null) return;
    setState(() {
      _played = true;
      _isPlaying = true;
    });
    try {
      final samples = synthesizeProsody(trial);
      _lastSamples = samples;
      await _audio.playWav(encodeWav16(samples));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null || !_played) return;
    final prior = _session.currentStreak;
    final correct = _session.submit(trial, index);
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _records.add(TrialRecord(
      target: trial.choices[trial.answerIndex],
      response: trial.choices[index],
      correct: correct,
      latencyMs: latency,
      parameters: <String, Object?>{
        'task': trial.task.name,
        'cue_semitones': trial.cueSemitones,
      },
    ));
    setState(() {
      _chosen = index;
      _lastCorrect = correct;
      _encouragement = Encouragement.forTrial(
        correct: correct,
        streakAfter: _session.currentStreak,
        priorStreak: prior,
        completed: _session.completedTrials,
        total: _session.maxTrials,
      );
    });
  }

  void _advance() {
    if (_session.isComplete) {
      widget.onCompleted?.call(List<TrialRecord>.of(_records));
      setState(() => _stage = _Stage.results);
    } else {
      _nextTrial();
    }
  }

  void _finishEarly() {
    widget.onCompleted?.call(List<TrialRecord>.of(_records));
    setState(() => _stage = _Stage.results);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.pick:
        return _buildPick();
      case _Stage.training:
        return _buildTraining();
      case _Stage.results:
        return _buildResults();
    }
  }

  Widget _buildPick() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Prosody training')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('Choose a listening game',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Prosody is the melody of speech — pitch, stress and emotion.',
                style: TextStyle(color: Color(0xff94a3b8)),
              ),
              const SizedBox(height: 20),
              for (final task in ProsodyTask.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton(
                    key: Key('prosody-task-${task.name}'),
                    onPressed: () => _startTask(task),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(task.label),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Synthesized demonstration speech — not validated clinical '
                'stimuli. Adaptation never changes master volume.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTraining() {
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Prosody training',
      subtitle: _task.label,
      instruction: _task.label,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      encouragement: _encouragement,
      showPlaybackControls: true,
      pills: [
        MetaPill(icon: Icons.forum, text: '${trial.choices.length}AFC'),
        MetaPill(
            icon: Icons.tune,
            text: 'Cue ${trial.cueSemitones.toStringAsFixed(1)} st'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: _played ? 'Replay' : 'Play',
          color: _played ? TransportColors.replay : TransportColors.play,
          onTap: !answered ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finishEarly,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${_session.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finishEarly,
      footer: answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TrainingFeedbackLine(
                    correct: _lastCorrect!,
                    answer: trial.choices[trial.answerIndex]),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ChoiceLayout(
              count: trial.choices.length,
              itemBuilder: (context, i) => TrainingChoiceTile(
                label: trial.choices[i],
                enabled: _played && !answered,
                state: _stateFor(i, trial),
                onTap: () => _choose(i),
              ),
            ),
          ),
          if (!_played)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Play the sound to enable the choices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xff94a3b8))),
            ),
          SpectrogramPanel(samples: _lastSamples),
        ],
      ),
    );
  }

  TrainingChoiceState _stateFor(int index, ProsodyTrial trial) {
    if (_chosen == null) return TrainingChoiceState.neutral;
    if (index == trial.answerIndex) return TrainingChoiceState.correct;
    if (index == _chosen) return TrainingChoiceState.wrong;
    return TrainingChoiceState.neutral;
  }

  Widget _buildResults() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Prosody training')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('${_task.label} — results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Trials completed',
                value: '${_session.completedTrials}'),
            TrainingSummaryRow(label: 'Accuracy', value: '${_session.percent}%'),
            TrainingSummaryRow(
                label: 'Best streak', value: '${_session.bestStreak}'),
            if (_session.bestCue != null)
              TrainingSummaryRow(
                  label: 'Finest cue heard',
                  value: '${_session.bestCue!.toStringAsFixed(1)} semitones'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _stage = _Stage.pick),
              child: const Text('Try another task'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _startTask(_task),
              child: const Text('Repeat this task'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
            const SizedBox(height: 12),
            Text(
              'Training exercise — not a diagnosis. Synthesized demonstration '
              'speech, not validated clinical stimuli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
        ),
      ),
    );
  }
}
