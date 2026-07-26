import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/mci.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Melodic Contour Identification (9-choice) renderer using the shipped
/// pure-tone contour assets (real audio). Play the contour, then choose its
/// shape from nine options. Master volume is never changed here.
class MciPage extends StatefulWidget {
  const MciPage({
    super.key,
    this.moduleId = 'melodic',
    this.groupId = 'pure_tone_contour',
    this.comfortableLevel = 0,
    this.maxTrials = 25,
    this.seed = 0,
    this.validationStatus = 'unvalidated',
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

  /// Loads asset bytes; defaults to the Flutter asset bundle. Injectable for
  /// tests.
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(MciSession session)? onCompleted;

  @override
  State<MciPage> createState() => _MciPageState();
}

class _MciPageState extends State<MciPage> {
  late final MciSession _session = MciSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final MciGenerator _generator = MciGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  MciTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _autoPlayTimer?.cancel();
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
    });
    _scheduleAutoPlay();
  }

  /// Auto-play the new trial's contour after a short delay so the listener does
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
      final bytes = await _loadAsset(trial.assetFor(trial.targetIndex));
      await _audio.playWav(bytes);
    } catch (_) {
      // Asset/playback failure must not block the exercise.
    }
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
    // Show feedback briefly, then auto-advance; Next remains a manual override.
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_finished && _chosen != null) _advance();
    });
  }

  void _advance() {
    _autoAdvanceTimer?.cancel();
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Melodic contour')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Melodic contour')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Melodic contour',
      subtitle: 'Music',
      instruction: 'Listen, then choose the contour shape you heard.',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        if (widget.comfortableLevel > 0)
          MetaPill(
              icon: Icons.lock,
              text: 'Level ${(widget.comfortableLevel * 100).round()}%'),
        const MetaPill(icon: Icons.music_note, text: '9-choice contour'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play contour',
          color: TransportColors.play,
          onTap: (!_played && !answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !answered && _replays < _maxReplays) ? _play : null,
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
      footer: answered ? _footer(trial) : null,
      child: _contoursArea(trial, answered),
    );
  }

  Widget _contoursArea(MciTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < trial.choices.length; i++)
                    _ContourButton(
                      pattern: trial.choices[i],
                      enabled: _played && !answered,
                      state: _choiceState(i, trial),
                      onTap: () => _choose(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!answered && !_played)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Play the contour to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  Widget _footer(MciTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(
            correct: _lastCorrect!,
            answer: contourLabel(trial.targetPattern),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, MciTrial trial) {
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
        Text('Research measurement only — not a diagnosis.',
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

class _ContourButton extends StatelessWidget {
  const _ContourButton({
    required this.pattern,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String pattern;
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
      label: contourLabel(pattern),
      child: Material(
        color: bg ?? const Color(0xff293548),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(contourGlyph(pattern),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(contourLabel(pattern),
                  style: const TextStyle(fontSize: 12, color: const Color(0xffe2e8f0))),
            ],
          ),
        ),
      ),
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
              style: const TextStyle(color: const Color(0xff94a3b8))),
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
          Text(label, style: const TextStyle(color: const Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
