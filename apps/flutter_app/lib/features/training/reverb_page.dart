import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/protocol_engine.dart';
import '../../core/training/reverb_training.dart';
import '../catalog/validation_badge.dart';
import '../common/choice_layout.dart';
import '../common/encouragement.dart';
import '../common/trial_scaffold.dart';
import 'training_widgets.dart';

/// Reverberation training: identify a word presented with synthetic reverb
/// (a feedback comb filter). The simulated room grows more reverberant
/// (RT60 0.3 → 1.2 s) on a correct streak. 20 adaptive trials.
///
/// Synthesized word tokens (`demo_only`), not validated clinical stimuli.
/// Adaptation changes only the reverb amount, never master volume.
class ReverbPage extends StatefulWidget {
  const ReverbPage({
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
  State<ReverbPage> createState() => _ReverbPageState();
}

enum _Stage { training, results }

class _ReverbPageState extends State<ReverbPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late ReverbSession _session = ReverbSession(maxTrials: widget.maxTrials);
  late ReverbGenerator _generator = ReverbGenerator(seed: widget.seed);

  _Stage _stage = _Stage.training;
  ReverbTrial? _current;
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
      _current = _generator.next(_session.level);
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
      final dry = synthesizeReverbWord(trial.target);
      final wet = combReverb(dry, rt60Seconds: trial.rt60Seconds);
      await _audio.playWav(encodeWav16(wet));
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
      target: trial.target.label,
      response: trial.choices[index].label,
      correct: correct,
      latencyMs: latency,
      parameters: <String, Object?>{
        'rt60_s': trial.rt60Seconds,
        'level': trial.level,
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
  Widget build(BuildContext context) =>
      _stage == _Stage.results ? _buildResults() : _buildTraining();

  Widget _buildTraining() {
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Reverb training',
      subtitle: 'Word in a reverberant room',
      instruction: 'Which word did you hear?',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      isPlaying: _isPlaying,
      liveResults: _session.results,
      encouragement: _encouragement,
      showPlaybackControls: true,
      pills: [
        MetaPill(icon: Icons.forum, text: '${trial.choices.length}AFC'),
        MetaPill(
            icon: Icons.blur_on,
            text: 'RT60 ${trial.rt60Seconds.toStringAsFixed(1)} s'),
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
                    correct: _lastCorrect!, answer: trial.target.label),
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
        ],
      ),
    );
  }

  TrainingChoiceState _stateFor(int index, ReverbTrial trial) {
    if (_chosen == null) return TrainingChoiceState.neutral;
    if (index == trial.targetIndex) return TrainingChoiceState.correct;
    if (index == _chosen) return TrainingChoiceState.wrong;
    return TrainingChoiceState.neutral;
  }

  Widget _buildResults() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reverb training')),
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
            TrainingSummaryRow(
                label: 'Most reverberant room handled',
                value: 'RT60 ${_session.maxRt60.toStringAsFixed(1)} s'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _records.clear();
                  _session = ReverbSession(maxTrials: widget.maxTrials);
                  _generator = ReverbGenerator(seed: widget.seed);
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
              'Training exercise — not a diagnosis. Synthesized word tokens '
              'with synthetic reverberation, not validated clinical stimuli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ],
        ),
      ),
    );
  }
}
