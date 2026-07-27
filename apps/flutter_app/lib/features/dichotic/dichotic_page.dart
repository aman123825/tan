import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/dichotic.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_flow_timing.dart';
import '../common/trial_scaffold.dart';

/// Dichotic-digits renderer: a different digit plays in each ear at once.
///
/// Supports three response paradigms via [mode]:
/// - [DichoticMode.cued] (default, backward-compatible): report the cued ear's
///   digit.
/// - [DichoticMode.freeRecall]: report BOTH digits (order-independent).
/// - [DichoticMode.directed]: the cued ear alternates each trial; report only
///   that ear. A Right-Ear-Advantage summary is reported.
///
/// Presentation is stereo, so wired headphones are required; results carry the
/// target ear.
class DichoticPage extends StatefulWidget {
  const DichoticPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'dichotic_digits',
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.mode = DichoticMode.cued,
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

  /// Response paradigm (cued / free-recall / directed). Defaults to [cued] for
  /// backward compatibility.
  final DichoticMode mode;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(DichoticSession session)? onCompleted;

  @override
  State<DichoticPage> createState() => _DichoticPageState();
}

class _DichoticPageState extends State<DichoticPage> {
  late final DichoticSession _session = DichoticSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
    dichoticMode: widget.mode,
  );
  late final DichoticGenerator _generator =
      DichoticGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  DichoticTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  String? _chosen; // cued/directed single choice (for highlight)
  final List<String> _chosenDigits = <String>[]; // free recall
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;
  Uint8List? _lastWav;

  bool get _isFreeRecall => widget.mode == DichoticMode.freeRecall;

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
    // Directed mode deliberately alternates the cued ear for balance.
    Ear? forceEar;
    if (widget.mode == DichoticMode.directed) {
      forceEar = _session.completedTrials.isEven ? Ear.right : Ear.left;
    }
    setState(() {
      _current = _generator.next(forceEar: forceEar);
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosen = null;
      _chosenDigits.clear();
      _answered = false;
      _lastCorrect = null;
      _lastWav = null;
    });
    _scheduleAutoPlay();
  }

  /// Auto-play the new trial's digits after a short delay so the listener does
  /// not have to press Play for every question. A no-op if it was already
  /// played; the Play button remains a first-trial fallback.
  void _scheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(kTrialPrePlayDelay, () {
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
      final l = decodeWav16(await _loadAsset(
          'assets/stimuli/digits/digit_${trial.leftDigit}.wav'));
      final r = decodeWav16(await _loadAsset(
          'assets/stimuli/digits/digit_${trial.rightDigit}.wav'));
      final rate = l.sampleRate;
      final wav = encodeWavStereo16(l.samples, r.samples, sampleRate: rate);
      _lastWav = wav;
      await _audio.playWav(wav);
    } catch (_) {
      // Missing asset / playback failure must not block the exercise.
    }
  }

  void _choose(String digit) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    if (_isFreeRecall) {
      if (_chosenDigits.contains(digit)) return;
      setState(() => _chosenDigits.add(digit));
      if (_chosenDigits.length >= 2) _scoreFreeRecall(trial);
    } else {
      _scoreCued(trial, digit);
    }
  }

  int get _latencyMs => _shownAt == null
      ? 0
      : DateTime.now().difference(_shownAt!).inMilliseconds;

  void _scoreCued(DichoticTrial trial, String digit) {
    final correct = _session.submit(
      trial,
      digit,
      latencyMs: _latencyMs,
      replays: _replays,
    );
    setState(() {
      _chosen = digit;
      _answered = true;
      _lastCorrect = correct;
    });
    _scheduleAutoAdvance(correct);
  }

  void _scoreFreeRecall(DichoticTrial trial) {
    final correct = _session.submitFreeRecall(
      trial,
      List<String>.of(_chosenDigits),
      latencyMs: _latencyMs,
      replays: _replays,
    );
    setState(() {
      _answered = true;
      _lastCorrect = correct;
    });
    _scheduleAutoAdvance(correct);
  }

  /// Show feedback briefly, then auto-advance; Next remains a manual override.
  /// Cancelled on dispose / manual advance / stop so no timer leaks.
  void _scheduleAutoAdvance(bool correct) {
    _autoAdvanceTimer?.cancel();
    if (!correct && _session.showsFeedback) {
      unawaited(_replayFailThenAdvance());
    } else {
      _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _answered) _advance();
      });
    }
  }

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
    if (!mounted || _finished || !_answered) return;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
      if (mounted && !_finished && _answered) _advance();
    });
  }

  void _advance() {
    _autoAdvanceTimer?.cancel();
    _autoPlayTimer?.cancel();
    if (_session.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    _autoAdvanceTimer?.cancel();
    _autoPlayTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _modeLabel() => switch (widget.mode) {
        DichoticMode.cued => 'Cued',
        DichoticMode.freeRecall => 'Free recall',
        DichoticMode.directed => 'Directed',
      };

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dichotic digits')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dichotic digits')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final cued = trial.targetEar == Ear.left ? 'LEFT' : 'RIGHT';
    final instruction = _isFreeRecall
        ? 'Play the digits, then tap BOTH numbers you heard (either order).'
        : 'Play the digits, then tap the number you heard in your $cued ear.';
    return TrialScaffold(
      title: 'Dichotic digits',
      subtitle: 'Dichotic listening · ${_modeLabel()}',
      instruction: instruction,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        if (_isFreeRecall)
          const MetaPill(icon: Icons.hearing, text: 'Report: both ears')
        else
          MetaPill(icon: Icons.hearing, text: 'Cued ear: $cued'),
        const MetaPill(icon: Icons.headphones, text: 'Wired headphones'),
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
      footer: _answered ? _footer(trial) : null,
      child: _digitsArea(trial),
    );
  }

  Widget _digitsArea(DichoticTrial trial) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GridView.count(
                crossAxisCount: 5,
                childAspectRatio: 1.4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: EdgeInsets.zero,
                children: [
                  for (final d in kDichoticDigits)
                    _DigitButton(
                      digit: d,
                      enabled: _played && !_answered,
                      state: _digitState(d, trial),
                      onTap: () => _choose(d),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!_answered && !_played)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Play the digits to enable the choices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
        if (!_answered && _isFreeRecall && _played)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Selected: ${_chosenDigits.isEmpty ? "—" : _chosenDigits.join(", ")}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  Widget _footer(DichoticTrial trial) {
    final answerText = _isFreeRecall
        ? 'left ${trial.leftDigit}, right ${trial.rightDigit}'
        : trial.targetDigit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: answerText),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  _DigitState _digitState(String digit, DichoticTrial trial) {
    if (!_answered) {
      if (_isFreeRecall && _chosenDigits.contains(digit)) {
        return _DigitState.selected;
      }
      return _DigitState.neutral;
    }
    if (!_session.showsFeedback) return _DigitState.neutral;
    if (_isFreeRecall) {
      if (digit == trial.leftDigit || digit == trial.rightDigit) {
        return _DigitState.correct;
      }
      if (_chosenDigits.contains(digit)) return _DigitState.wrong;
      return _DigitState.neutral;
    }
    if (digit == trial.targetDigit) return _DigitState.correct;
    if (digit == _chosen) return _DigitState.wrong;
    return _DigitState.neutral;
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final showRea = widget.mode == DichoticMode.directed;
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
        _SummaryRow(label: 'Left ear', value: '${_session.leftPercent}%'),
        _SummaryRow(label: 'Right ear', value: '${_session.rightPercent}%'),
        if (showRea)
          _SummaryRow(
            label: 'Right-ear advantage',
            value: '${_session.rightEarAdvantage >= 0 ? '+' : ''}'
                '${_session.rightEarAdvantage.toStringAsFixed(0)} pts',
          ),
        const SizedBox(height: 14),
        Text('Left ear (per-ear norm)', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        NormTile(Norms.dichoticPercent(_session.completedTrials == 0
            ? null
            : _session.leftAccuracy * 100)),
        const SizedBox(height: 10),
        Text('Right ear (per-ear norm)', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        NormTile(Norms.dichoticPercent(_session.completedTrials == 0
            ? null
            : _session.rightAccuracy * 100)),
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Digits are generated '
            'demo speech; left/right are reported separately.',
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

enum _DigitState { neutral, selected, correct, wrong }

class _DigitButton extends StatelessWidget {
  const _DigitButton({
    required this.digit,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String digit;
  final bool enabled;
  final _DigitState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color? bg = switch (state) {
      _DigitState.correct => const Color(0x3322c55e),
      _DigitState.wrong => const Color(0x33ef4444),
      _DigitState.selected => const Color(0x333b82f6),
      _DigitState.neutral => null,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Digit $digit',
      child: Material(
        color: bg ?? const Color(0xff293548),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: enabled || state != _DigitState.neutral
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
