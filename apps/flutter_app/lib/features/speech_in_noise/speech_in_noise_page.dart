import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../common/norm_tile.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audio/voice_variants.dart';
import '../../core/difficulty.dart';
import '../../core/protocol_engine.dart';
import '../../core/speech_in_noise.dart';
import '../catalog/validation_badge.dart';
import '../common/level_meter.dart';
import '../common/trial_scaffold.dart';

/// Demonstration word pool for the 4AFC renderer. These are placeholder labels;
/// real, reviewed stimuli replace them once validated.
const List<String> kDemoWordPool = <String>[
  'bell',
  'ball',
  'bat',
  'bag',
  'pen',
  'pin',
  'cup',
  'cap',
];

/// Adaptive speech-in-noise 4AFC renderer.
///
/// Difficulty adapts on SNR via the deterministic [SpeechInNoiseSession]. The
/// comfortable level is already LOCKED before this screen is reached; nothing
/// here can change master volume. Feedback is shown during training only.
class SpeechInNoisePage extends StatefulWidget {
  const SpeechInNoisePage({
    super.key,
    required this.moduleId,
    required this.groupId,
    required this.comfortableLevel,
    this.itemPool = kDemoWordPool,
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
    this.difficulty = DifficultyLevel.medium,
    this.seed = 0,
    this.validationStatus = 'unvalidated',
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;

  /// The locked comfortable level in [0, 1] (display only; never changed here).
  final double comfortableLevel;

  final List<String> itemPool;
  final int maxTrials;
  final ProtocolMode mode;

  /// Starting difficulty. Sets the initial SNR + adaptation step (via
  /// [DifficultyConfig]); the staircase still adapts from there. Defaults to
  /// [DifficultyLevel.medium].
  final DifficultyLevel difficulty;

  final int seed;
  final String validationStatus;

  /// Audio output. Defaults to a silent port (tests/headless).
  final AudioPort? audioPort;

  /// Loads a word asset's bytes; defaults to the Flutter asset bundle.
  /// Injectable for tests.
  final Future<Uint8List> Function(String assetPath)? assetLoader;

  /// Fired once when the run finishes (completed or stopped). The app shell
  /// uses this to persist the session's trials via the offline [TrialQueue].
  final void Function(SpeechInNoiseSession session)? onCompleted;

  @override
  State<SpeechInNoisePage> createState() => _SpeechInNoisePageState();
}

class _SpeechInNoisePageState extends State<SpeechInNoisePage> {
  late final SpeechInNoiseSession _session = SpeechInNoiseSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
    mode: widget.mode,
    track: AdaptiveTrack.snr(
      start: widget.difficulty.config.startSnrDb,
      step: widget.difficulty.config.stepSize,
    ),
  );
  late final FourAfcGenerator _generator = FourAfcGenerator(
    widget.itemPool,
    seed: widget.seed,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  FourAlternativeTrial? _current;
  VoiceVariant _voice = kVoiceVariants.first;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;

  /// Talker variety is a TRAINING aid only: locked test measurements keep the
  /// single base voice so the SNR staircase measures listening, not
  /// adaptation to a new talker.
  bool get _variesVoice => widget.mode == ProtocolMode.training;

  int? _chosenIndex;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;
  final List<bool> _results = <bool>[];

  // Presentation-only stimulus level meter data (last mixed buffer).
  List<double> _envelope = const <double>[];
  Duration _stimDuration = Duration.zero;
  int _playToken = 0;

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  String _fmt(Duration d) {
    final mm = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
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
      _voice = _variesVoice
          ? voiceForTrial(widget.seed, _session.completedTrials)
          : kVoiceVariants.first;
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosenIndex = null;
      _lastCorrect = null;
    });
    _scheduleAutoPlay();
  }

  /// Auto-play the new trial's audio after a short delay so the listener does
  /// not have to press Play for every question. It is a no-op if the sample was
  /// already played (manually or by a prior auto-play), and the Play button
  /// stays available as a first-trial fallback for browser autoplay policies.
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
      final bytes = await _loadAsset(
        'assets/stimuli/speech/word_${trial.target}.wav',
      );
      final speech = decodeWav16(bytes);
      // Proxy talker variety in training (presentation only, never scoring).
      final voiced = applyVoiceVariant(speech.samples, _voice);
      final seconds = voiced.length / speech.sampleRate;
      final noise = whiteNoise(
        seconds: seconds,
        amp: 0.2,
        seed: widget.seed + _session.completedTrials,
        sampleRate: speech.sampleRate,
      );
      // SAFETY: adapt SNR only; peak-normalized mix never boosts master volume.
      final mixed = mixAtSnr(voiced, noise, _session.currentSnrDb);
      if (mounted) {
        setState(() {
          _envelope = levelEnvelope(mixed);
          _stimDuration = Duration(
              milliseconds: mixed.length * 1000 ~/ speech.sampleRate);
          _playToken++;
        });
      }
      await _audio.playWav(encodeWav16(mixed, sampleRate: speech.sampleRate));
    } catch (_) {
      // Asset missing (e.g. placeholder pool in tests) or playback failure:
      // do not block the exercise.
    }
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosenIndex != null) return;
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
      _chosenIndex = index;
      _lastCorrect = correct;
      _results.add(correct);
    });
    // Show feedback briefly, then auto-advance. The Next button stays as an
    // immediate manual override. Cancelled on dispose / manual advance / stop
    // so no timer leaks past the widget's lifetime.
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_finished && _chosenIndex != null) _advance();
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
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Speech in noise')),
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
    final answered = _chosenIndex != null;
    return TrialScaffold(
      title: 'Speech in noise',
      onStop: _confirmStop,
      instruction: 'Listen, then choose the word you heard.',
      pills: [
        MetaPill(text: 'SNR ${_session.currentSnrDb.toStringAsFixed(0)} dB'),
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.signal_cellular_alt,
            text: 'Level: ${widget.difficulty.label}'),
        if (_variesVoice)
          MetaPill(
              icon: Icons.record_voice_over,
              text: '${_voice.label} (proxy)'),
        if (_envelope.isNotEmpty)
          StimulusLevelMeter(
            envelope: _envelope,
            duration: _stimDuration,
            playToken: _playToken,
          ),
      ],
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      liveResults: _results,
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      revealedText: answered ? trial.choices[trial.targetIndex] : null,
      helpText: 'Measures the signal-to-noise ratio at which you recognise '
          'words (lower/negative thresholds are better). The noise level '
          'adapts to your answers.',
      onFlagLastTrial: answered
          ? () => setState(() => flagLastTrial(_session.records))
          : null,
      lastTrialFlagged: lastTrialFlagged(_session.records),
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
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
          onTap: _confirmStop,
        ),
      ],
      footer: answered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_session.showsFeedback)
                  _FeedbackLine(
                    correct: _lastCorrect!,
                    answer: trial.choices[trial.targetIndex],
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: _choicesArea(trial, answered),
    );
  }

  Widget _choicesArea(FourAlternativeTrial trial, bool answered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.6,
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < trial.choices.length; i++)
                    _ChoiceButton(
                      label: trial.choices[i],
                      enabled: _played && !answered,
                      state: _choiceState(i, trial),
                      onTap: () => _choose(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!_played)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Play the sample to enable the choices.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xff94a3b8)),
            ),
          ),
      ],
    );
  }

  /// Only reveals correctness during training feedback.
  _ChoiceState _choiceState(int index, FourAlternativeTrial trial) {
    if (_chosenIndex == null || !_session.showsFeedback) {
      return _ChoiceState.neutral;
    }
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosenIndex) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final threshold = _session.thresholdSnrDb;
    return ListView(
      children: [
        Text(
          'Session summary',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        _SummaryRow(
          label: 'Trials completed',
          value: '${_session.completedTrials}',
        ),
        _SummaryRow(
          label: 'Accuracy',
          value: '${(_session.accuracy * 100).round()}%',
        ),
        _SummaryRow(
          label: 'Threshold SNR',
          value: threshold == null
              ? 'not reached (needs more reversals)'
              : '${threshold.toStringAsFixed(1)}'
                  '${_session.track.thresholdSd == null ? '' : ' ± ${_session.track.thresholdSd!.toStringAsFixed(1)}'} dB',
        ),
        const SizedBox(height: 14),
        NormTile(Norms.speechSnrDb(threshold)),
        const SizedBox(height: 12),
        Text(
          'Research measurement only. This is not a diagnosis and not a dB HL '
          'threshold.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
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

enum _ChoiceState { neutral, correct, wrong }

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String label;
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
      label: label,
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
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: enabled || state != _ChoiceState.neutral
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
            Icon(
              correct ? Icons.check_circle : Icons.cancel,
              color:
                  correct ? const Color(0xff22c55e) : const Color(0xffef4444),
            ),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('The correct answer was: $answer',
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
          Text(label, style: const TextStyle(color: const Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
