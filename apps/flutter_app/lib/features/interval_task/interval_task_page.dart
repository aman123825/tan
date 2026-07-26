import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/difficulty.dart';
import '../../core/interval_task.dart';
import '../../core/psychometrics.dart';
import '../catalog/validation_badge.dart';

/// Builds the full N-interval trial audio for a given target interval and
/// current adapted-parameter value.
typedef IntervalSynth = List<double> Function(
    int targetInterval, double paramValue, int trialIndex);

const Color _panelBorder = Color(0x33ffffff);

/// Generic adaptive N-interval forced-choice renderer. The listener plays the
/// intervals, then picks the one that differs; difficulty adapts on a single
/// parameter owned by [IntervalTaskSession]. Used by level discrimination,
/// tone detection, and rhythm discrimination.
class IntervalTaskPage extends StatefulWidget {
  const IntervalTaskPage({
    super.key,
    required this.title,
    this.subtitle = 'Psychoacoustics',
    required this.instruction,
    required this.session,
    required this.synth,
    required this.paramChip,
    required this.thresholdText,
    this.seed = 0,
    this.playLabel = 'Play',
    this.replayLabel = 'Replay',
    this.choiceWord = 'Sound',
    this.sampleRate = kSampleRate,
    this.intervalSeconds = 0.4,
    this.gapSeconds = 0.2,
    this.researchNote =
        'Research measurement only — not a diagnosis and not a dB HL threshold.',
    this.validationStatus = 'unvalidated',
    this.difficulty = DifficultyLevel.medium,
    this.audioPort,
    this.resultExtra,
    this.onCompleted,
  });

  final String title;
  final String subtitle;
  final String instruction;
  final IntervalTaskSession session;
  final IntervalSynth synth;

  /// Chip text for the current adapted-parameter value.
  final String Function(double value) paramChip;

  /// Results text for the reached threshold (null if not reached).
  final String Function(double? threshold) thresholdText;

  final int seed;
  final String playLabel;
  final String replayLabel;
  final String choiceWord;
  final int sampleRate;

  /// Per-interval tone duration / gap (seconds) — used to time the
  /// currently-playing box highlight against the single presented buffer.
  final double intervalSeconds;
  final double gapSeconds;
  final String researchNote;
  final String validationStatus;

  /// Starting difficulty (display only here — the starting parameter is set on
  /// the injected [session]'s track by the caller). Shown as a "Level:" pill.
  final DifficultyLevel difficulty;

  final AudioPort? audioPort;

  /// Optional extra content rendered in the results (e.g. a cited norm badge),
  /// given the reached threshold (null if not reached).
  final Widget Function(BuildContext context, double? threshold)? resultExtra;
  final void Function(IntervalTaskSession session)? onCompleted;

  @override
  State<IntervalTaskPage> createState() => _IntervalTaskPageState();
}

class _IntervalTaskPageState extends State<IntervalTaskPage> {
  late final ThreeIntervalGenerator _generator = ThreeIntervalGenerator(
    seed: widget.seed,
    intervals: widget.session.intervals,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  ThreeIntervalTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;

  /// Maximum manual replays per trial.
  static const int _maxReplays = 5;

  /// The exact buffer presented this trial (re-used for replays/auto-replay).
  Uint8List? _lastWav;
  bool _playing = false;
  bool _paused = false;
  Timer? _tick;
  int _activeInterval = -1;
  final Stopwatch _sessionSw = Stopwatch()..start();

  IntervalTaskSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _tick?.cancel();
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
      _paused = false;
    });
    _present(); // auto-play the new trial; the listener never taps "play".
  }

  /// Builds, caches and auto-plays the stimulus for the current trial.
  Future<void> _present() async {
    final trial = _current;
    if (trial == null) return;
    final seq = widget.synth(
      trial.targetInterval,
      _session.currentParam,
      _session.completedTrials,
    );
    final wav = encodeWav16(seq, sampleRate: widget.sampleRate);
    _lastWav = wav;
    if (mounted) setState(() => _played = true);
    await _playBuffer(wav);
  }

  /// Manual replay, capped at [_maxReplays] per trial.
  Future<void> _replay() async {
    final wav = _lastWav;
    if (wav == null ||
        _playing ||
        _paused ||
        _chosen != null ||
        _replays >= _maxReplays) {
      return;
    }
    setState(() => _replays++);
    await _playBuffer(wav);
  }

  /// After a wrong answer (training), re-play the trial's sounds twice,
  /// sequentially (each starts only when the previous finishes).
  Future<void> _replayOnFail() async {
    final wav = _lastWav;
    if (wav == null) return;
    for (var i = 0; i < 2; i++) {
      if (!mounted) return;
      await _playBuffer(wav);
    }
  }

  /// Plays a buffer while running a live elapsed timer and lighting the
  /// currently-playing box.
  Future<void> _playBuffer(Uint8List wav) async {
    _tick?.cancel();
    final sw = Stopwatch()..start();
    if (mounted) {
      setState(() {
        _playing = true;
        _activeInterval = 0;
      });
    }
    _tick = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() => _activeInterval = _intervalAt(sw.elapsed));
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

  /// Which interval box is lit at playback time [t] (-1 during a gap/idle).
  int _intervalAt(Duration t) {
    final span = widget.intervalSeconds + widget.gapSeconds;
    if (span <= 0) return -1;
    final secs = t.inMilliseconds / 1000.0;
    final idx = secs ~/ span;
    if (idx >= _session.intervals) return -1;
    return (secs - idx * span) < widget.intervalSeconds ? idx : -1;
  }

  /// Pause the current presentation (can be resumed).
  void _pause() {
    _tick?.cancel();
    _tick = null;
    _audio.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _paused = true;
        _activeInterval = -1;
      });
    }
  }

  /// Resume after a pause: re-present the current buffer (not counted as a
  /// manual replay — it continues the same presentation).
  Future<void> _resume() async {
    final wav = _lastWav;
    if (wav == null || _playing || _chosen != null) return;
    setState(() => _paused = false);
    await _playBuffer(wav);
  }

  /// Hard stop: silence audio and reset the transport to idle.
  void _stop() {
    _tick?.cancel();
    _tick = null;
    _audio.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _paused = false;
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
    if (!correct && _session.showsFeedback) _replayOnFail();
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
    if (stop == true && mounted) _finish();
  }

  /// Space/Enter target: Resume when paused, else Replay when idle.
  VoidCallback? get _primaryKeyAction {
    if (_finished || _chosen != null) return null;
    if (_paused && !_playing) return _resume;
    final idle = _played && !_playing && !_paused;
    if (idle && _replays < _maxReplays) return _replay;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffold = Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subtitle.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                )),
            Text(widget.title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'End exercise',
            onPressed: _finished ? null : _confirmStop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _finished ? _buildResults(context) : _buildTrial(context),
      ),
    );
    if (_finished) return scaffold;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _primaryKeyAction?.call(),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _primaryKeyAction?.call(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _primaryKeyAction?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () => _confirmStop(),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Widget _buildTrial(BuildContext context) {
    final theme = Theme.of(context);
    final trial = _current;
    if (trial == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final answered = _chosen != null;
    final idle = _played && !_playing && !_paused && _chosen == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _MetaPill(text: widget.paramChip(_session.currentParam)),
                    const SizedBox(width: 8),
                    const _MetaPill(icon: Icons.lock, text: 'Volume locked'),
                    const SizedBox(width: 8),
                    _MetaPill(
                      icon: Icons.signal_cellular_alt,
                      text: 'Level: ${widget.difficulty.label}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValidationBadge(validationStatus: widget.validationStatus),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main stimulus area.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.instruction,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.hearing,
                            size: 26, color: theme.colorScheme.primary),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final h = c.maxHeight.isFinite
                              ? c.maxHeight.clamp(120.0, 300.0).toDouble()
                              : 260.0;
                          return Center(
                            child: SizedBox(
                              height: h,
                              child: Row(
                                children: [
                                  for (var i = 0; i < _session.intervals; i++)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: _IntervalButton(
                                          label:
                                              '${widget.choiceWord} ${i + 1}',
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
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              // Side transport panel (Resume / Pause / Stop / Replay).
              _TransportPanel(
                onResume: (_paused && !_playing && !answered) ? _resume : null,
                onPause: _playing ? _pause : null,
                onStop: (_playing || _paused) ? _stop : null,
                onReplay:
                    (idle && _replays < _maxReplays) ? _replay : null,
                replayLabel: '${widget.replayLabel} ($_replays/$_maxReplays)',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _StatusBar(
          question: 'Question ${_session.trialNumber} of ${_session.maxTrials}',
          elapsed: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
        ),
        const SizedBox(height: 6),
        Text('Space = replay    ·    Esc = end',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: const Color(0xff8b9bb4))),
        if (answered) ...[
          const SizedBox(height: 12),
          if (_session.showsFeedback) _FeedbackLine(correct: _lastCorrect!),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _advance,
            child: Text(_session.isComplete ? 'See results' : 'Next'),
          ),
        ],
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
    final threshold = _session.threshold;
    final sd = _session.track.thresholdSd;
    final thresholdStr = (threshold != null && sd != null)
        ? '${widget.thresholdText(threshold)}  (± ${sd.toStringAsFixed(2)})'
        : widget.thresholdText(threshold);
    return ListView(
      children: [
        Text('Session report',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Center(
          child: Text('${(_session.accuracy * 100).round()}%',
              style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900, color: const Color(0xff1565c0))),
        ),
        const Center(
            child: Text('accuracy', style: TextStyle(color: const Color(0xff94a3b8)))),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _session.accuracy.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: const Color(0xffe0e0e0),
          ),
        ),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(label: 'Time', value: _fmt(_sessionSw.elapsed)),
        _SummaryRow(label: 'Threshold', value: thresholdStr),
        // Signal-detection sensitivity from proportion correct on this nAFC
        // task (Hacker & Ratcliff, 1979). Research summary only.
        if (dPrimeFromPc(_session.accuracy, _session.intervals) != null)
          _SummaryRow(
              label: 'Sensitivity (d′, ${_session.intervals}AFC)',
              value: dPrimeFromPc(_session.accuracy, _session.intervals)!
                  .toStringAsFixed(2)),
        if (widget.resultExtra != null) ...[
          const SizedBox(height: 14),
          widget.resultExtra!(context, threshold),
        ],
        const SizedBox(height: 12),
        Text(widget.researchNote,
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

/// Angel-Sound-style vertical transport panel.
class _TransportPanel extends StatelessWidget {
  const _TransportPanel({
    required this.onResume,
    required this.onPause,
    required this.onStop,
    required this.onReplay,
    required this.replayLabel,
  });

  final VoidCallback? onResume;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onReplay;
  final String replayLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        border: Border.all(color: _panelBorder),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TransportButton(
              icon: Icons.play_arrow,
              label: 'Resume',
              color: const Color(0xff2e9e5b),
              onTap: onResume,
            ),
            const SizedBox(height: 18),
            _TransportButton(
              icon: Icons.pause,
              label: 'Pause',
              color: const Color(0xff3d9be9),
              onTap: onPause,
            ),
            const SizedBox(height: 18),
            _TransportButton(
              icon: Icons.stop,
              label: 'Stop',
              color: const Color(0xfff08c2e),
              onTap: onStop,
            ),
            const SizedBox(height: 18),
            _TransportButton(
              icon: Icons.replay,
              label: replayLabel,
              color: const Color(0xffe0a400),
              onTap: onReplay,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: enabled ? color : const Color(0xff334155),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(icon,
                    size: 24,
                    color: enabled ? Colors.white : const Color(0xff8b9bb4)),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 88,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: enabled ? const Color(0xfff1f5f9) : Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom status strip: "Question X of N" (left) · "Elapsed Time MM:SS" (right).
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.question, required this.elapsed});

  final String question;
  final String elapsed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x1affffff), Color(0x0dffffff)],
            ),
            border: Border.all(color: _panelBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(question,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xfff1f5f9))),
              Text(elapsed,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xfff1f5f9))),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1affffff), Color(0x0dffffff)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xff94a3b8)),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xfff1f5f9))),
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
      _IntervalState.neutral => active ? const Color(0xff3b82f6) : null,
    };
    final border = active && state == _IntervalState.neutral
        ? const Color(0xff60a5fa)
        : _panelBorder;
    final onActive = active && state == _IntervalState.neutral;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Container(
        decoration: BoxDecoration(
          gradient: onActive
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x1affffff), Color(0x0dffffff)],
                ),
          color: onActive ? bg : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: onActive ? 2 : 1),
          boxShadow: onActive
              ? [
                  BoxShadow(
                    color: const Color(0xff3b82f6).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: bg ?? Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: onActive
                      ? Colors.white
                      : (enabled || state != _IntervalState.neutral
                          ? const Color(0xfff1f5f9)
                          : Colors.white38),
                ),
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
        Icon(correct ? Icons.check_circle : Icons.cancel,
            color: correct ? const Color(0xff22c55e) : const Color(0xffef4444)),
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
          Text(label, style: const TextStyle(color: const Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
