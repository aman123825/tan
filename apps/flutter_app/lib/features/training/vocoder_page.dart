import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/difficulty.dart';
import '../../core/speech_in_noise.dart'
    show FourAfcGenerator, FourAlternativeTrial;
import '../../core/training/vocoder.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';
import '../open_set/open_set_page.dart' show kOpenWordPool;

// Dark glassmorphic palette (kept local to match the shared trial chrome).
const Color _ink = Color(0xffe2e8f0);
const Color _muted = Color(0xff94a3b8);
const Color _border = Color(0x33ffffff);
const Color _good = Color(0xff22c55e);
const Color _bad = Color(0xffef4444);

/// Noise-Vocoded Speech (cochlear-implant simulation) training.
///
/// Words from [kOpenWordPool] are degraded into N spectral channels (a noise
/// vocoder) and identified in a 4-alternative forced choice. The channel count
/// adapts: two correct answers drop to fewer channels (harder, more degraded);
/// a wrong answer adds channels (easier). It reports the fewest channels the
/// listener could still understand. Illustrative demonstration on uncalibrated
/// audio — not a validated CI simulation. Adapts channels, never volume.
class VocoderPage extends StatefulWidget {
  const VocoderPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'vocoder',
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.difficulty = DifficultyLevel.medium,
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

  /// Starting difficulty — sets the vocoder's starting channel count (more
  /// channels = clearer). Defaults to [DifficultyLevel.medium] (16 channels).
  final DifficultyLevel difficulty;

  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(VocoderSession session)? onCompleted;

  @override
  State<VocoderPage> createState() => _VocoderPageState();
}

class _VocoderPageState extends State<VocoderPage> {
  late final VocoderSession _session = VocoderSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
    startChannels: widget.difficulty.config.startingChannels,
  );
  late final FourAfcGenerator _generator =
      FourAfcGenerator(kOpenWordPool, seed: widget.seed, choices: 4);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  FourAlternativeTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;

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

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosen = null;
      _lastCorrect = null;
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
      final decoded =
          decodeWav16(await _loadAsset('assets/stimuli/words/word_${trial.target}.wav'));
      final vocoded = vocode(
        decoded.samples,
        _session.currentChannels,
        sampleRate: decoded.sampleRate,
      );
      await _audio.playWav(encodeWav16(vocoded, sampleRate: decoded.sampleRate));
    } catch (_) {
      // Asset missing / playback failure must not block the exercise.
    }
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosen != null || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, index, latencyMs: latency, replays: _replays);
    setState(() {
      _chosen = index;
      _lastCorrect = correct;
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
        appBar: AppBar(title: const Text('Vocoded speech')),
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
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Vocoded speech',
      subtitle: 'Cochlear-implant simulation',
      instruction: 'Listen to the degraded word, then tap what you heard.',
      instructionIcon: Icons.graphic_eq,
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.blur_on, text: '${_session.currentChannels} channels'),
        MetaPill(
            icon: Icons.signal_cellular_alt,
            text: 'Level: ${widget.difficulty.label}'),
      ],
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

  Widget _choicesArea(FourAlternativeTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2.4,
              children: [
                for (var i = 0; i < trial.choices.length; i++)
                  _WordButton(
                    text: trial.choices[i],
                    enabled: _played && !answered,
                    state: _choiceState(i, trial),
                    onTap: () => _choose(i),
                  ),
              ],
            ),
            if (!_played && !answered)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Play the word to enable the choices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: _muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ChoiceState _choiceState(int index, FourAlternativeTrial trial) {
    if (_chosen == null || !_session.showsFeedback) return _ChoiceState.neutral;
    if (index == trial.targetIndex) return _ChoiceState.correct;
    if (index == _chosen) return _ChoiceState.wrong;
    return _ChoiceState.neutral;
  }

  Widget _footer(FourAlternativeTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(correct: _lastCorrect!, answer: trial.target),
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
    final fewest = _session.fewestChannelsMastered;
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(label: 'Accuracy', value: '${_session.percent}%'),
        _SummaryRow(
          label: 'Fewest channels mastered',
          value: fewest == null ? '—' : '$fewest channels',
        ),
        const SizedBox(height: 6),
        const Text('Fewer channels = more degraded = harder.',
            style: TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Noise-vocoded demonstration '
            'speech on uncalibrated audio, not a validated cochlear-implant '
            'simulation.',
            style: theme.textTheme.bodySmall?.copyWith(color: _muted)),
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

class _WordButton extends StatelessWidget {
  const _WordButton({
    required this.text,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final _ChoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = _border;
    if (state == _ChoiceState.correct) {
      bg = const Color(0x3322c55e);
      border = _good;
    } else if (state == _ChoiceState.wrong) {
      bg = const Color(0x33ef4444);
      border = _bad;
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: border, width: state == _ChoiceState.neutral ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: enabled || state != _ChoiceState.neutral
                      ? _ink
                      : Colors.white38,
                )),
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
                color: correct ? _good : _bad),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('It was “$answer”', style: const TextStyle(color: _muted)),
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
          Text(label, style: const TextStyle(color: _muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
