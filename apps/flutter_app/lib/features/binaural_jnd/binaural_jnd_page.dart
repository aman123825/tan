import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/binaural_jnd.dart';
import '../../core/interval_task.dart';
import '../../core/protocol_engine.dart' show flagLastTrial, lastTrialFlagged;
import '../catalog/validation_badge.dart';
import '../common/trial_flow_timing.dart';
import '../common/trial_scaffold.dart';

/// ITD / ILD lateralization JND test: two sounds play — one centred, one
/// off-centre by an adaptive interaural time (µs) or level (dB) difference.
/// The listener picks the off-centre interval; 2-down/1-up converges on the
/// JND. Headphones are REQUIRED (the cue is interaural by definition).
class BinauralJndPage extends StatefulWidget {
  const BinauralJndPage({
    super.key,
    required this.mode,
    this.seed = 0,
    this.maxTrials = 30,
    this.audioPort,
    this.onCompleted,
  });

  /// 'itd' or 'ild'.
  final String mode;
  final int seed;
  final int maxTrials;
  final AudioPort? audioPort;
  final void Function(IntervalTaskSession session)? onCompleted;

  @override
  State<BinauralJndPage> createState() => _BinauralJndPageState();
}

class _BinauralJndPageState extends State<BinauralJndPage> {
  bool get _isItd => widget.mode == 'itd';

  late final IntervalTaskSession _session = IntervalTaskSession(
    moduleId: 'auditory',
    groupId: _isItd ? 'itd_jnd' : 'ild_jnd',
    paramName: _isItd ? 'itd_us' : 'ild_db',
    track: _isItd ? itdTrack() : ildTrack(),
    intervals: 2,
    maxTrials: widget.maxTrials,
  );
  late final ThreeIntervalGenerator _generator =
      ThreeIntervalGenerator(seed: widget.seed, intervals: 2);
  late final Random _sideRng = Random(widget.seed + 31);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final Stopwatch _sw = Stopwatch()..start();
  final Stopwatch _latency = Stopwatch();

  ThreeIntervalTrial? _trial;
  String _side = 'left';
  bool _playing = false;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  int _replays = 0;
  Timer? _advanceTimer;
  Timer? _prePlayTimer;

  /// The exact presented buffer (for wrong-answer replays).
  Uint8List? _lastWav;
  final List<bool> _results = <bool>[];

  String get _title =>
      _isItd ? 'ITD Lateralization JND' : 'ILD Lateralization JND';

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _prePlayTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    if (_session.isComplete) {
      _finish();
      return;
    }
    setState(() {
      _trial = _generator.next();
      _side = _sideRng.nextBool() ? 'left' : 'right';
      _played = false;
      _chosen = null;
      _lastCorrect = null;
      _replays = 0;
      _lastWav = null;
    });
    // Short breathing room, then the new pair auto-plays.
    _prePlayTimer?.cancel();
    _prePlayTimer = Timer(kTrialPrePlayDelay, () {
      if (mounted && !_finished && _chosen == null) unawaited(_play());
    });
  }

  Future<void> _play() async {
    final trial = _trial;
    if (trial == null || _playing) return;
    setState(() {
      if (_played) _replays++;
      _playing = true;
    });
    try {
      final param = _session.currentParam;
      final StereoInterval reference;
      final StereoInterval target;
      if (_isItd) {
        reference = diotticTone();
        target = itdTone(param, leadingSide: _side);
      } else {
        final seed = widget.seed * 1000 + _session.trialNumber;
        reference = diotticNoise(seed: seed);
        target = ildNoise(param, louderSide: _side, seed: seed);
      }
      final assembled = assembleTwoIntervals(
        reference: reference,
        target: target,
        targetIndex: trial.targetInterval,
      );
      final wav = encodeWavStereo16(assembled.left, assembled.right);
      _lastWav = wav; // exact bytes for wrong-answer replays
      await _audio.playWav(wav);
    } catch (_) {}
    if (!mounted) return;
    _latency
      ..reset()
      ..start();
    setState(() {
      _playing = false;
      _played = true;
    });
  }

  void _choose(int interval) {
    if (_chosen != null || !_played) return;
    _latency.stop();
    final correct = _session.submit(
      _trial!,
      interval,
      latencyMs: _latency.elapsedMilliseconds,
      replays: _replays,
    );
    setState(() {
      _chosen = interval;
      _lastCorrect = correct;
      _results.add(correct);
    });
    // Hands-free flow: a wrong answer re-plays the pair twice, then the next
    // question follows automatically after a short pause.
    _advanceTimer?.cancel();
    if (!correct) {
      unawaited(_replayFailThenAdvance());
    } else {
      _advanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _chosen != null) _advance();
      });
    }
  }

  /// Wrong-answer sequence: replay the exact presented pair twice, a brief
  /// beat, then advance automatically.
  Future<void> _replayFailThenAdvance() async {
    final wav = _lastWav;
    for (var i = 0; i < 2 && wav != null; i++) {
      if (!mounted || _finished) return;
      try {
        await _audio.playWav(wav);
      } catch (_) {
        break;
      }
    }
    if (!mounted || _finished || _chosen == null) return;
    // Cancellable beat before advancing (a raw Future.delayed would leak a
    // timer past dispose).
    _advanceTimer?.cancel();
    _advanceTimer = Timer(kTrialFeedbackDelay, () {
      if (mounted && !_finished && _chosen != null) _advance();
    });
  }

  void _advance() {
    _advanceTimer?.cancel();
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    _advanceTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmtParam(double v) => _isItd
      ? '${v.round()} µs'
      : '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} dB';

  String _fmtTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _resultsView(context);
    final answered = _chosen != null;
    return TrialScaffold(
      title: _title,
      subtitle: 'Binaural cues · headphones required',
      instruction:
          'Two sounds play. One is centred, one is off to a side — choose '
          'the OFF-CENTRE one.',
      isPlaying: _playing,
      validationBadge: const ValidationBadge(validationStatus: 'unvalidated'),
      liveResults: _results,
      pills: [
        MetaPill(
          icon: Icons.swap_horiz,
          text: '${_isItd ? 'ITD' : 'ILD'} ${_fmtParam(_session.currentParam)}',
        ),
        MetaPill(
          icon: Icons.tag,
          text: 'Trial ${_session.trialNumber}/${widget.maxTrials}',
        ),
        const MetaPill(icon: Icons.headphones, text: 'Headphones required'),
      ],
      transport: [
        TransportAction(
          icon: Icons.replay,
          label: 'Replay',
          color: TransportColors.replay,
          onTap: (_played && !answered && !_playing && _replays < 2)
              ? _play
              : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmtTime(_sw.elapsed)}',
      onStop: _finish,
      onFlagLastTrial: answered
          ? () => setState(() => flagLastTrial(_session.records))
          : null,
      lastTrialFlagged: lastTrialFlagged(_session.records),
      footer: answered ? _feedbackFooter() : null,
      onDigitKey: (d) {
        if (d == 1) _choose(0);
        if (d == 2) _choose(1);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: _IntervalButton(
                    label: 'Sound ${i + 1}',
                    enabled: _played && !answered,
                    correct: answered && i == _trial!.targetInterval,
                    wrong:
                        answered && _chosen == i && i != _trial!.targetInterval,
                    onTap: () => _choose(i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _feedbackFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _lastCorrect! ? Icons.check_circle : Icons.cancel,
              color: _lastCorrect!
                  ? const Color(0xff22c55e)
                  : const Color(0xffef4444),
            ),
            const SizedBox(width: 8),
            Text(_lastCorrect! ? 'Correct' : 'Not quite',
                style: const TextStyle(color: Color(0xffe2e8f0))),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _resultsView(BuildContext context) {
    final theme = Theme.of(context);
    final t = _session.threshold;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Session Results',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  t == null ? 'No threshold' : _fmtParam(t),
                  style: const TextStyle(
                      color: Color(0xff3b82f6),
                      fontSize: 40,
                      fontWeight: FontWeight.w900),
                ),
              ),
              Center(
                child: Text(
                  t == null
                      ? 'Too few reversals to estimate a JND.'
                      : 'Just-noticeable interaural '
                          '${_isItd ? 'time' : 'level'} difference '
                          '(smaller = finer).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xff94a3b8)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Trials: ${_session.completedTrials} · '
                'Correct: ${_session.correctCount} '
                '(${(_session.accuracy * 100).round()}%)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xff94a3b8)),
              ),
              const SizedBox(height: 16),
              Text(
                _isItd
                    ? 'Reference: young adults typically resolve ≈ 20–60 µs '
                        'with 500 Hz tones (Klumpp & Eady, 1956); values are '
                        'task-relative on consumer headphones.'
                    : 'Reference: young adults typically resolve ≈ 0.5–2 dB '
                        '(Mills, 1960); values are task-relative on consumer '
                        'headphones.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff8b9bb4), height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Research measurement — not a diagnosis. Requires stereo '
                'headphones worn the right way round.',
                style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_session),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntervalButton extends StatelessWidget {
  const _IntervalButton({
    required this.label,
    required this.enabled,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool correct;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    if (correct) {
      bg = const Color(0x3322c55e);
      border = const Color(0xff22c55e);
    } else if (wrong) {
      bg = const Color(0x33ef4444);
      border = const Color(0xffef4444);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: correct || wrong ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_note,
                      size: 28,
                      color: enabled || correct || wrong
                          ? const Color(0xffe2e8f0)
                          : Colors.white38),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: enabled || correct || wrong
                              ? const Color(0xffe2e8f0)
                              : Colors.white38)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
