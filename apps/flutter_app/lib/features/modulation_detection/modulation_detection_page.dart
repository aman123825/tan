import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../common/norm_tile.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/modulation_detection.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_flow_timing.dart';

/// Amplitude-modulation-detection 3AFC renderer with real synthesized audio.
///
/// Three noise intervals play; one is amplitude-modulated (its loudness
/// pulses) and the listener chooses which. Difficulty adapts on modulation
/// depth (dB) via the deterministic [ModulationDetectionSession]. The
/// comfortable level is locked before this screen; master volume never changes.
class ModulationDetectionPage extends StatefulWidget {
  const ModulationDetectionPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'modulation_depth',
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
  final void Function(ModulationDetectionSession session)? onCompleted;

  @override
  State<ModulationDetectionPage> createState() =>
      _ModulationDetectionPageState();
}

class _ModulationDetectionPageState extends State<ModulationDetectionPage> {
  late final ModulationDetectionSession _session = ModulationDetectionSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final ThreeIntervalGenerator _generator =
      ThreeIntervalGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  ThreeIntervalTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;

  static const int _maxReplays = 5;
  Uint8List? _lastWav;
  bool _playing = false;
  Timer? _tick;
  Timer? _prePlayTimer;
  Timer? _autoAdvanceTimer;
  Duration _elapsed = Duration.zero;
  int _activeInterval = -1;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _prePlayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosen = null;
      _lastCorrect = null;
      _lastWav = null;
    });
    _prePlayTimer?.cancel();
    _prePlayTimer = Timer(kTrialPrePlayDelay, () {
      if (mounted && !_finished && _chosen == null) unawaited(_present());
    });
  }

  Future<void> _present() async {
    final trial = _current;
    if (trial == null) return;
    final seq = buildModulationSequence(
      targetInterval: trial.targetInterval,
      depthDb: _session.currentDepthDb,
      rateHz: _session.rateHz,
      seed: widget.seed + _session.completedTrials,
    );
    final wav = encodeWav16(seq);
    _lastWav = wav;
    if (mounted) setState(() => _played = true);
    await _playBuffer(wav);
  }

  Future<void> _replay() async {
    final wav = _lastWav;
    if (wav == null || _playing || _chosen != null || _replays >= _maxReplays) {
      return;
    }
    setState(() => _replays++);
    await _playBuffer(wav);
  }

  Future<void> _replayOnFail() async {
    final wav = _lastWav;
    if (wav == null) return;
    for (var i = 0; i < 2; i++) {
      if (!mounted) return;
      await _playBuffer(wav);
    }
  }

  Future<void> _playBuffer(Uint8List wav) async {
    _tick?.cancel();
    final sw = Stopwatch()..start();
    if (mounted) {
      setState(() {
        _playing = true;
        _elapsed = Duration.zero;
        _activeInterval = 0;
      });
    }
    _tick = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = sw.elapsed;
        _activeInterval = _intervalAt(sw.elapsed);
      });
    });
    try {
      await _audio.playWav(wav);
    } finally {
      _tick?.cancel();
      _tick = null;
      if (mounted) {
        setState(() {
          _playing = false;
          _activeInterval = -1;
        });
      }
    }
  }

  int _intervalAt(Duration t) {
    const span = 0.6;
    final secs = t.inMilliseconds / 1000.0;
    final idx = secs ~/ span;
    if (idx >= 3) return -1;
    return (secs - idx * span) < 0.4 ? idx : -1;
  }

  void _pause() {
    _tick?.cancel();
    _tick = null;
    _audio.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _activeInterval = -1;
      });
    }
  }

  String _fmt(Duration d) {
    final mm = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
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
    _autoAdvanceTimer?.cancel();
    if (!correct && _session.showsFeedback) {
      unawaited(_replayFailThenAdvance());
    } else {
      _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _chosen != null) _advance();
      });
    }
  }

  Future<void> _replayFailThenAdvance() async {
    await _replayOnFail();
    if (!mounted || _finished || _chosen == null) return;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
      if (mounted && !_finished && _chosen != null) _advance();
    });
  }

  void _advance() {
    _autoAdvanceTimer?.cancel();
    _prePlayTimer?.cancel();
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    _prePlayTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  Future<void> _confirmStop() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop the exercise?'),
        content: const Text(
          'You can stop at any time. Fatigue is not failure — your progress so '
          'far is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop now'),
          ),
        ],
      ),
    );
    if (stop == true && mounted) {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modulation detection'),
        actions: [
          IconButton(
            tooltip: 'Stop',
            onPressed: _finished ? null : _confirmStop,
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
        _StatusBar(
          depthDb: _session.currentDepthDb,
          trialNumber: _session.trialNumber,
          maxTrials: widget.maxTrials,
          levelPercent: _levelPercent,
          validationStatus: widget.validationStatus,
        ),
        const SizedBox(height: 10),
        const _WiredHeadphoneNote(),
        const SizedBox(height: 16),
        Text(
          'Play the three sounds. One flutters (its loudness pulses) — choose '
          'which.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _playing
                ? _pause
                : ((_played && _chosen == null && _replays < _maxReplays)
                    ? _replay
                    : null),
            icon: Icon(_playing ? Icons.pause : Icons.replay),
            label: Text(_playing
                ? 'Playing  ${_fmt(_elapsed)}'
                : 'Replay sequence ($_replays/$_maxReplays)'),
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _IntervalButton(
                      label: '${i + 1}',
                      enabled: _played && !answered,
                      active: _activeInterval == i,
                      state: _intervalState(i, trial),
                      onTap: () => _choose(i),
                    ),
                  ),
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
          Text(
            'Play the sequence to enable the choices.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8)),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  _IntervalState _intervalState(int index, ThreeIntervalTrial trial) {
    if (_chosen == null || !_session.showsFeedback) {
      return _IntervalState.neutral;
    }
    if (index == trial.targetInterval) return _IntervalState.correct;
    if (index == _chosen) return _IntervalState.wrong;
    return _IntervalState.neutral;
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final threshold = _session.thresholdDepthDb;
    return ListView(
      children: [
        Text(
          'Session summary',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
          label: 'Accuracy',
          value: '${(_session.accuracy * 100).round()}%',
        ),
        _SummaryRow(
          label: 'Modulation-depth threshold',
          value: threshold == null
              ? 'not reached (needs more reversals)'
              : '${threshold.toStringAsFixed(1)}'
                  '${_session.track.thresholdSd == null ? '' : ' ± ${_session.track.thresholdSd!.toStringAsFixed(1)}'} dB',
        ),
        const SizedBox(height: 14),
        NormTile(Norms.amDepthDb(threshold)),
        const SizedBox(height: 12),
        Text(
          'Research measurement only — not a diagnosis and not a dB HL '
          'threshold. Wired-headphone recommended; not comparable across '
          'output devices.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: const Color(0xff94a3b8)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.depthDb,
    required this.trialNumber,
    required this.maxTrials,
    required this.levelPercent,
    required this.validationStatus,
  });

  final double depthDb;
  final int trialNumber;
  final int maxTrials;
  final int levelPercent;
  final String validationStatus;

  @override
  Widget build(BuildContext context) {
    final progress = (trialNumber - 1) / maxTrials;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Chip(label: Text('Depth ${depthDb.toStringAsFixed(0)} dB')),
            const SizedBox(width: 8),
            Chip(
              avatar: const Icon(Icons.lock, size: 16),
              label: Text('Level $levelPercent%'),
            ),
            const Spacer(),
            ValidationBadge(validationStatus: validationStatus),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text('Trial $trialNumber of $maxTrials',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WiredHeadphoneNote extends StatelessWidget {
  const _WiredHeadphoneNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffeaf3ff),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.headphones_outlined, color: Color(0xff246bce), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Use wired headphones for temporal tasks. Bluetooth and speakers '
              'are not suitable for modulation thresholds.',
              style: TextStyle(color: Color(0xff20406b)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _IntervalState { neutral, correct, wrong }

class _IntervalButton extends StatelessWidget {
  const _IntervalButton({
    required this.label,
    required this.enabled,
    required this.active,
    required this.state,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool active;
  final _IntervalState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color? bg = switch (state) {
      _IntervalState.correct => const Color(0x3322c55e),
      _IntervalState.wrong => const Color(0x33ef4444),
      _IntervalState.neutral => active ? const Color(0xffffe0b2) : null,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Interval $label',
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
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: enabled || state != _IntervalState.neutral
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
        Icon(
          correct ? Icons.check_circle : Icons.cancel,
          color: correct ? const Color(0xff22c55e) : const Color(0xffef4444),
        ),
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
