import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/identification.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Provides the WAV bytes to play for the [target] on a given [trialIndex]
/// (synthesized instruments/melodies/effects, or a decoded asset).
typedef IdentificationAudio = Future<Uint8List> Function(
    IdentificationChoice target, int trialIndex);

/// Generic audio-identification renderer: a stimulus plays and the listener
/// picks it from a closed set. Choices render as an emoji + label, a color
/// swatch, or a text label. The audio source is injected via [audioProvider],
/// so the same page serves instrument, melody, environmental-sound, speaker and
/// picture identification.
class IdentificationPage extends StatefulWidget {
  const IdentificationPage({
    super.key,
    required this.moduleId,
    required this.groupId,
    required this.comfortableLevel,
    required this.pool,
    required this.title,
    required this.instruction,
    required this.audioProvider,
    this.choiceCount = 4,
    this.maxTrials = 20,
    this.seed = 0,
    this.playLabel = 'Play',
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final List<IdentificationChoice> pool;
  final String title;
  final String instruction;
  final IdentificationAudio audioProvider;
  final int choiceCount;
  final int maxTrials;
  final int seed;
  final String playLabel;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(IdentificationSession session)? onCompleted;

  @override
  State<IdentificationPage> createState() => _IdentificationPageState();
}

class _IdentificationPageState extends State<IdentificationPage> {
  late final IdentificationSession _session = IdentificationSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final IdentificationGenerator _generator = IdentificationGenerator(
    pool: widget.pool,
    choiceCount: widget.choiceCount,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  IdentificationTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

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

  /// Auto-play the new trial's audio after a short delay so the listener does
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
      final bytes =
          await widget.audioProvider(trial.target, _session.completedTrials);
      await _audio.playWav(bytes);
    } catch (_) {
      // Synthesis/asset failure must not block the exercise.
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

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final answered = _chosen != null;
    return TrialScaffold(
      title: widget.title,
      subtitle: 'Identification',
      instruction: widget.instruction,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: widget.playLabel,
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
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(IdentificationTrial trial, bool answered) {
    final theme = Theme.of(context);
    final hasEmoji = trial.choices.any((c) => c.emoji != null);
    final hasSwatch = trial.choices.any((c) => c.swatchArgb != null);
    final grid = hasEmoji || hasSwatch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: grid ? 720 : 620),
              child: GridView.count(
                crossAxisCount: grid ? 3 : 2,
                childAspectRatio: grid ? 1 : 2.4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < trial.choices.length; i++)
                    _ChoiceButton(
                      choice: trial.choices[i],
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
            child: Text('Play the sound to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  Widget _footer(IdentificationTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.target.label),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  _ChoiceState _choiceState(int index, IdentificationTrial trial) {
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
        Text(
            'Research measurement only — not a diagnosis. Synthesized or demo '
            'material, not validated clinical stimuli.',
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

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.choice,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final IdentificationChoice choice;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _ChoiceState.correct => const Color(0xff22c55e),
      _ChoiceState.wrong => const Color(0xffef4444),
      _ChoiceState.neutral => Colors.transparent,
    };
    final isSwatch = choice.swatchArgb != null;
    final Color bg = isSwatch
        ? Color(choice.swatchArgb!)
        : (switch (state) {
            _ChoiceState.correct => const Color(0x3322c55e),
            _ChoiceState.wrong => const Color(0x33ef4444),
            _ChoiceState.neutral =>
              const Color(0xff293548),
          });
    return Semantics(
      button: true,
      enabled: enabled,
      label: choice.label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: isSwatch
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (choice.emoji != null)
                        Text(choice.emoji!,
                            style: const TextStyle(fontSize: 34)),
                      Text(
                        choice.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: enabled || state != _ChoiceState.neutral
                              ? const Color(0xffe2e8f0)
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
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
          Text('The correct answer was: $answer',
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
