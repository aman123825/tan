import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audio/voice_variants.dart';
import '../../core/figure_ground.dart';
import '../../core/protocol_engine.dart'
    show flagLastTrial, lastTrialFlagged;
import '../../core/speech_in_noise.dart'
    show FourAfcGenerator, FourAlternativeTrial;
import '../catalog/validation_badge.dart';
import '../common/level_meter.dart';
import '../common/trial_scaffold.dart';
import '../speech_in_noise/speech_in_noise_page.dart' show kDemoWordPool;

/// SCAN-style figure-ground word recognition at fixed +8 / 0 / −8 dB SNR.
///
/// Three word blocks at constant SNR (easy → hard) with per-SNR percent
/// scores — the fixed-SNR complement to the adaptive word-in-noise staircase.
/// Words rotate through the four proxy voice variants for talker variety.
class FigureGroundPage extends StatefulWidget {
  const FigureGroundPage({
    super.key,
    required this.comfortableLevel,
    this.trialsPerSnr = 8,
    this.seed = 0,
    this.audioPort,
    this.assetLoader,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int trialsPerSnr;
  final int seed;
  final AudioPort? audioPort;
  final Future<Uint8List> Function(String assetPath)? assetLoader;
  final void Function(FigureGroundSession session)? onCompleted;

  @override
  State<FigureGroundPage> createState() => _FigureGroundPageState();
}

class _FigureGroundPageState extends State<FigureGroundPage> {
  late final FigureGroundSession _session =
      FigureGroundSession(trialsPerSnr: widget.trialsPerSnr);
  late final FourAfcGenerator _generator =
      FourAfcGenerator(kDemoWordPool, seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Future<Uint8List> Function(String) _loadAsset =
      widget.assetLoader ??
          (path) async => (await rootBundle.load(path)).buffer.asUint8List();

  FourAlternativeTrial? _current;
  VoiceVariant _voice = kVoiceVariants.first;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosenIndex;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _autoPlayTimer;
  final List<bool> _results = <bool>[];
  final Stopwatch _sw = Stopwatch()..start();

  // Presentation-only stimulus level meter data (last mixed buffer).
  List<double> _envelope = const <double>[];
  Duration _stimDuration = Duration.zero;
  int _playToken = 0;

  static const int _maxReplays = 3;

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
      _voice = voiceForTrial(widget.seed, _session.completedTrials);
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosenIndex = null;
    });
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
      // Proxy talker variety (presentation only — scoring is unaffected).
      final voiced = applyVoiceVariant(speech.samples, _voice);
      final seconds = voiced.length / speech.sampleRate;
      final noise = whiteNoise(
        seconds: seconds,
        amp: 0.2,
        seed: widget.seed + _session.completedTrials,
        sampleRate: speech.sampleRate,
      );
      // SAFETY: the SNR is a fixed block constant; the peak-normalized mix
      // never boosts master volume.
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
      // Missing asset/playback failure must not block the run.
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
      _results.add(correct);
    });
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 900), () {
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
    _autoPlayTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmtTime(Duration d) {
    final m = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _snrLabel(double snr) =>
      '${snr > 0 ? '+' : ''}${snr.toStringAsFixed(0)} dB';

  @override
  Widget build(BuildContext context) {
    if (_finished) return _resultsView(context);
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosenIndex != null;
    return TrialScaffold(
      title: 'Figure-ground words',
      subtitle: 'Fixed SNR blocks',
      instruction: 'Listen, then choose the word you heard.',
      validationBadge: const ValidationBadge(validationStatus: 'unvalidated'),
      liveResults: _results,
      pills: [
        MetaPill(
          icon: Icons.blur_on,
          text: 'Block SNR ${_snrLabel(_session.currentSnrDb)}',
        ),
        MetaPill(
          icon: Icons.tag,
          text: 'Word ${_session.trialInBlock}/${widget.trialsPerSnr}',
        ),
        MetaPill(icon: Icons.record_voice_over, text: '${_voice.label} (proxy)'),
        if (_envelope.isNotEmpty)
          StimulusLevelMeter(
            envelope: _envelope,
            duration: _stimDuration,
            playToken: _playToken,
          ),
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
      revealedText: answered ? trial.target : null,
      helpText: 'Word blocks at three FIXED signal-to-noise ratios '
          '(+8, 0, −8 dB). The per-SNR percent shows how quickly accuracy '
          'falls as noise increases.',
      onFlagLastTrial: answered
          ? () => setState(() => flagLastTrial(_session.records))
          : null,
      lastTrialFlagged: lastTrialFlagged(_session.records),
      statusLeft: 'Question ${_session.trialNumber} of '
          '${_session.totalTrials}',
      statusRight: 'Elapsed Time ${_fmtTime(_sw.elapsed)}',
      onStop: _finish,
      onDigitKey: (d) {
        if (d >= 1 && d <= trial.choices.length) _choose(d - 1);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < trial.choices.length; i++)
                _WordButton(
                  label: trial.choices[i],
                  enabled: _played && !answered,
                  onTap: () => _choose(i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(double snr) {
      final pct = _session.percentFor(snr);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Words at ${_snrLabel(snr)} SNR',
                style: const TextStyle(color: Color(0xff94a3b8))),
            Text(pct == null ? '—' : '${pct.round()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xffe2e8f0))),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Figure-ground words')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Session Results',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              for (final snr in kFigureGroundSnrsDb) row(snr),
              const Divider(color: Color(0x33ffffff)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall',
                        style: TextStyle(color: Color(0xff94a3b8))),
                    Text('${(_session.accuracy * 100).round()}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xffe2e8f0))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Typical listeners lose accuracy gradually as SNR falls; a '
                'steep drop from +8 to 0 dB suggests strong noise '
                'susceptibility (cf. SCAN-3 figure-ground subtests). '
                'Task-relative demonstration stimuli — not normed scores, '
                'not a diagnosis.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xff8b9bb4), height: 1.4),
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

class _WordButton extends StatelessWidget {
  const _WordButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: const Color(0xff293548),
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
                color: enabled ? const Color(0xffe2e8f0) : Colors.white38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
