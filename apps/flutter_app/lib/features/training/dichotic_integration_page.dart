import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/dichotic_integration.dart';
import '../common/focus_ring.dart';
import '../common/trial_scaffold.dart';

/// Dichotic Integration Training renderer (CADPOTS-style).
///
/// A target digit plays in the WEAK ear (left by default) louder than a
/// competing digit in the other ear. As the listener succeeds the interaural
/// level difference shrinks (10 → 0 dB) on a 2-down/1-up staircase, training
/// the weak ear to integrate under increasing competition. Wired headphones
/// required. The minimum level difference reached is reported.
class DichoticIntegrationPage extends StatefulWidget {
  const DichoticIntegrationPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'dichotic_integration',
    required this.comfortableLevel,
    this.trainedEar = TrainedEar.left,
    this.maxTrials = 20,
    this.seed = 0,
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final TrainedEar trainedEar;
  final int maxTrials;
  final int seed;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(DichoticIntegrationSession session)? onCompleted;

  @override
  State<DichoticIntegrationPage> createState() =>
      _DichoticIntegrationPageState();
}

class _DichoticIntegrationPageState extends State<DichoticIntegrationPage> {
  late final DichoticIntegrationSession _session = DichoticIntegrationSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    trainedEar: widget.trainedEar,
    maxTrials: widget.maxTrials,
  );
  late final DichoticIntegrationGenerator _generator =
      DichoticIntegrationGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  DichoticIntegrationTrial? _current;
  DateTime? _shownAt;
  bool _counting = false;
  bool _played = false;
  String? _chosen;
  bool _answered = false;
  bool? _lastCorrect;
  int? _lastLatency;
  int _replays = 0;
  bool _finished = false;
  Timer? _countdownFallback;

  static const int _maxReplays = 3;
  final Stopwatch _sessionSw = Stopwatch()..start();

  String get _earLabel => widget.trainedEar.label;

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
    _countdownFallback?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    _countdownFallback?.cancel();
    setState(() {
      _current = _generator.next();
      _shownAt = null;
      _counting = true;
      _played = false;
      _chosen = null;
      _answered = false;
      _lastCorrect = null;
      _lastLatency = null;
      _replays = 0;
    });
    _countdownFallback = Timer(const Duration(milliseconds: 2200), () {
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
        _counting = false;
        _shownAt = DateTime.now();
      }
    });
    try {
      final target = decodeWav16(
          await _loadAsset('assets/stimuli/digits/digit_${trial.targetDigit}.wav'));
      final distractor = decodeWav16(await _loadAsset(
          'assets/stimuli/digits/digit_${trial.distractorDigit}.wav'));
      final wav = buildDichoticIntegrationStimulus(
        target: target.samples,
        distractor: distractor.samples,
        trainedEar: widget.trainedEar,
        levelDiffDb: _session.currentLevelDiffDb,
        sampleRate: target.sampleRate,
      );
      await _audio.playWav(wav);
    } catch (_) {
      // Asset missing/playback failure must not block the exercise.
    }
  }

  void _choose(String digit) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct = _session.submit(trial, digit, latencyMs: latency, replays: _replays);
    setState(() {
      _chosen = digit;
      _answered = true;
      _lastCorrect = correct;
      _lastLatency = latency;
    });
  }

  void _onDigitKey(int digit) {
    if (_answered || !_played) return;
    _choose('$digit');
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
    _countdownFallback?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dichotic Integration Training')),
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
      title: 'Dichotic Integration',
      subtitle: 'Weak-ear training',
      instruction: _counting
          ? 'A digit plays in each ear.'
          : 'Tap the digit you heard in your $_earLabel ear (keys 0–9).',
      isPlaying: _played && !_answered && !_counting,
      showCountdown: _counting,
      onCountdownComplete: () {
        if (mounted && !_played) _play();
      },
      responseTimeMs: _answered ? _lastLatency : null,
      onDigitKey: _onDigitKey,
      pills: [
        MetaPill(icon: Icons.hearing, text: 'Target ear: $_earLabel'),
        MetaPill(
          icon: Icons.tune,
          text: 'Level Δ ${_session.currentLevelDiffDb.toStringAsFixed(0)} dB',
        ),
        const MetaPill(icon: Icons.headphones, text: 'Wired headphones'),
      ],
      transport: [
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

  Widget _digitsArea(DichoticIntegrationTrial trial) {
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
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final d in kDichoticIntegrationDigits)
                    FocusRing(
                      borderRadius: 12,
                      child: _DigitButton(
                        digit: d,
                        enabled: _played && !_answered,
                        state: _digitState(d, trial),
                        onTap: () => _choose(d),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!_played && !_answered)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('The digits will play automatically.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff94a3b8))),
          ),
      ],
    );
  }

  _DigitState _digitState(String digit, DichoticIntegrationTrial trial) {
    if (!_answered || !_session.showsFeedback) return _DigitState.neutral;
    if (digit == trial.targetDigit) return _DigitState.correct;
    if (digit == _chosen) return _DigitState.wrong;
    return _DigitState.neutral;
  }

  Widget _footer(DichoticIntegrationTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback && _lastCorrect != null)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.targetDigit),
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
        Text('Training summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(
            label: 'Accuracy', value: '${(_session.accuracy * 100).round()}%'),
        _SummaryRow(label: 'Trained ear', value: _earLabel),
        _SummaryRow(
          label: 'Minimum level difference',
          value: '${_session.minLevelDiffDb.toStringAsFixed(0)} dB',
        ),
        const SizedBox(height: 14),
        Text(
            'Smaller minimum level differences mean the weak ear integrated '
            'the target under stronger competition — the training goal.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 8),
        Text(
            'Research training only — not a diagnosis. Adaptation moves the '
            'interaural level balance, never master volume.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff8b9bb4))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

enum _DigitState { neutral, correct, wrong }

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
        if (correct == false) ...[
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
