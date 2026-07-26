import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/music_emotion.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/encouragement.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Emotion-in-music training: a short synthesized melody is played in one of
/// four affective styles (happy / sad / tense / calm) and identified in a 4AFC.
/// 20 trials.
///
/// Synthesized melodies (`demo_only`), not validated clinical stimuli. Nothing
/// here changes master volume.
class MusicEmotionPage extends StatefulWidget {
  const MusicEmotionPage({
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
  State<MusicEmotionPage> createState() => _MusicEmotionPageState();
}

enum _Stage { training, results }

class _MusicEmotionPageState extends State<MusicEmotionPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late MusicEmotionSession _session =
      MusicEmotionSession(maxTrials: widget.maxTrials);
  late MusicEmotionGenerator _generator =
      MusicEmotionGenerator(seed: widget.seed);

  _Stage _stage = _Stage.training;
  MusicEmotionTrial? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _isPlaying = false;
  int? _chosen;
  bool? _lastCorrect;
  String? _encouragement;
  Timer? _autoPlayTimer;

  final List<TrialRecord> _records = <TrialRecord>[];
  final Stopwatch _sw = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
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
      await _audio.playWav(encodeWav16(trial.synthesize()));
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
      target: trial.choices[trial.targetIndex].label,
      response: trial.choices[index].label,
      correct: correct,
      latencyMs: latency,
      parameters: <String, Object?>{'notes': trial.noteCount},
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
  Widget build(BuildContext context) =>
      _stage == _Stage.results ? _buildResults() : _buildTraining();

  Widget _buildTraining() {
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Emotion in music',
      subtitle: 'How does it feel?',
      instruction: 'How does this melody feel?',
      instructionIcon: Icons.music_note,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      encouragement: _encouragement,
      showPlaybackControls: true,
      pills: [
        const MetaPill(icon: Icons.forum, text: '4AFC'),
        MetaPill(icon: Icons.music_note, text: '${trial.noteCount} notes'),
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
                    answer: trial.choices[trial.targetIndex].label),
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
                label: trial.choices[i].label,
                emoji: trial.choices[i].emoji,
                enabled: _played && !answered,
                state: _stateFor(i, trial),
                onTap: () => _choose(i),
              ),
            ),
          ),
          if (!_played)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Play the melody to enable the choices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xff94a3b8))),
            ),
        ],
      ),
    );
  }

  TrainingChoiceState _stateFor(int index, MusicEmotionTrial trial) {
    if (_chosen == null) return TrainingChoiceState.neutral;
    if (index == trial.targetIndex) return TrainingChoiceState.correct;
    if (index == _chosen) return TrainingChoiceState.wrong;
    return TrainingChoiceState.neutral;
  }

  Widget _buildResults() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Emotion in music')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TrainingSummaryRow(
                label: 'Trials completed',
                value: '${_session.completedTrials}'),
            TrainingSummaryRow(label: 'Accuracy', value: '${_session.percent}%'),
            TrainingSummaryRow(
                label: 'Best streak', value: '${_session.bestStreak}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _records.clear();
                  _session = MusicEmotionSession(maxTrials: widget.maxTrials);
                  _generator = MusicEmotionGenerator(seed: widget.seed);
                  _sw
                    ..reset()
                    ..start();
                  _stage = _Stage.training;
                });
                _nextTrial();
              },
              child: const Text('Train again'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
            const SizedBox(height: 12),
            Text(
              'Training exercise — not a diagnosis. Synthesized melodies, not '
              'validated clinical stimuli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
        ),
      ),
    );
  }
}
