import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/speed_training.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Time-Compressed Speech *training*: sentences are played at an adaptive
/// speed. Two correct answers speed the material up (0.1×, harder); a wrong
/// answer slows it (0.1×, easier), bounded 0.8×..2.0×. The listener types what
/// they heard and is scored by word accuracy. Adapts speed, never volume.
class CompressedTrainingPage extends StatefulWidget {
  const CompressedTrainingPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'speed_training',
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(SpeedTrainingSession session)? onCompleted;

  @override
  State<CompressedTrainingPage> createState() => _CompressedTrainingPageState();
}

class _CompressedTrainingPageState extends State<CompressedTrainingPage> {
  late final SpeedTrainingSession _session = SpeedTrainingSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final SpeedTrainingGenerator _generator =
      SpeedTrainingGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();
  final TextEditingController _input = TextEditingController();

  SpeedTrainingTrial? _current;
  DateTime? _shownAt;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  int _replays = 0;
  Timer? _autoPlayTimer;
  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  int get _levelPercent => (widget.comfortableLevel * 100).round();

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

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _played = false;
      _replays = 0;
      _answered = false;
      _lastCorrect = null;
      _input.clear();
    });
    _scheduleAutoPlay();
  }

  /// Auto-play the new trial's sentence after a short delay so the listener does
  /// not have to press Play for every question. A no-op if it was already
  /// played; the Play button remains a first-trial fallback.
  void _scheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_played) _play();
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
    try {
      final samples = <double>[];
      var rate = kSampleRate;
      for (final path in trial.assetPaths) {
        final decoded = decodeWav16(await _loadAsset(path));
        rate = decoded.sampleRate;
        samples.addAll(decoded.samples);
      }
      final scaled = timeScale(samples, _session.currentSpeed);
      await _audio.playWav(encodeWav16(scaled, sampleRate: rate));
    } catch (_) {
      // Asset missing / playback failure must not block the exercise.
    }
  }

  void _submit() {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final score = _session.submit(trial, _input.text,
        latencyMs: latency, replays: _replays);
    setState(() {
      _answered = true;
      _lastCorrect = score >= _session.correctThreshold;
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
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Time-compressed training')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TrialScaffold(
      title: 'Time-compressed training',
      subtitle: 'Rapid speech',
      instruction: 'Listen to the sped-up sentence, then type what you heard.',
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.speed,
            text: '${_session.currentSpeed.toStringAsFixed(1)}×'),
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
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !_answered && _replays < _maxReplays) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _answered ? _footer() : null,
      child: _answerArea(),
    );
  }

  Widget _answerArea() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _input,
              enabled: _played && !_answered,
              onSubmitted: (_) => _submit(),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Type the sentence you heard',
              ),
            ),
            const SizedBox(height: 16),
            if (!_answered)
              FilledButton(
                onPressed: _played ? _submit : null,
                child: const Text('Submit'),
              ),
            if (!_played && !_answered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Play the sentence to enable typing.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: _current?.text ?? ''),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
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
            label: 'Mean word accuracy',
            value: '${_session.meanAccuracyPercent}%'),
        _SummaryRow(
            label: 'Fastest speed reached',
            value: '${_session.maxSpeedReached.toStringAsFixed(1)}×'),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Time-scaled demonstration '
            'speech, not validated clinical stimuli.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
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
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('It was “$answer”',
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
