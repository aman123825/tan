import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audio/timbre.dart';
import '../../core/speech_in_noise.dart';
import '../../core/training/scene_training.dart' show multiTalkerBabble;
import '../catalog/validation_badge.dart';
import '../common/trial_flow_timing.dart';
import '../common/trial_scaffold.dart';

/// Masker options for music-in-noise (K3/K4): speech-derived babble built
/// from the shipped word recordings, the synthetic babble fallback, or the
/// competing-music masker.
enum MusicMasker { speechBabble, syntheticBabble, music }

/// Music-in-noise: a familiar melody plays inside multi-talker babble and the
/// listener names it (4AFC). The SNR adapts 2-down/1-up — the melodic
/// analogue of the words-in-noise staircase (cf. the Music-In-Noise Task,
/// Coffey et al., 2019).
class MusicInNoisePage extends StatefulWidget {
  const MusicInNoisePage({
    super.key,
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.masker = MusicMasker.speechBabble,
    this.audioPort,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final int seed;

  /// Which masker competes with the melody (default: the speech-derived
  /// babble asset, falling back to synthetic babble if it fails to load).
  final MusicMasker masker;
  final AudioPort? audioPort;
  final void Function(SpeechInNoiseSession session)? onCompleted;

  @override
  State<MusicInNoisePage> createState() => _MusicInNoisePageState();
}

class _MusicInNoisePageState extends State<MusicInNoisePage> {
  late final SpeechInNoiseSession _session = SpeechInNoiseSession(
    moduleId: 'music',
    groupId: 'music_in_noise',
    maxTrials: widget.maxTrials,
  );
  late final FourAfcGenerator _generator =
      FourAfcGenerator(kMelodyIds, seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  FourAlternativeTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosenIndex;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _autoAdvanceTimer;
  Timer? _prePlayTimer;

  /// The exact presented buffer (for wrong-answer replays).
  Uint8List? _lastWav;
  final List<bool> _results = <bool>[];
  final Stopwatch _sw = Stopwatch()..start();

  static const int _maxReplays = 3;

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _prePlayTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosenIndex = null;
      _lastCorrect = null;
      _lastWav = null;
    });
    // Short breathing room, then the next tune auto-plays.
    _prePlayTimer?.cancel();
    _prePlayTimer = Timer(kTrialPrePlayDelay, () {
      if (mounted && !_finished && _chosenIndex == null) unawaited(_play());
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
      final melody = melodySynth(trial.target, noteSeconds: 0.28);
      final masker = await _maskerFor(melody.length / kSampleRate);
      // SAFETY: only the melody-to-masker SNR adapts; the peak-normalized
      // mix never boosts master volume.
      final mixed = mixAtSnr(melody, masker, _session.currentSnrDb);
      final wav = encodeWav16(mixed);
      _lastWav = wav; // exact bytes for wrong-answer replays
      await _audio.playWav(wav);
    } catch (_) {}
  }

  /// The chosen masker at [seconds] length. The speech-babble asset (24 kHz)
  /// is upsampled by simple repetition to the synth rate; load failures fall
  /// back to the synthetic babble so the task never blocks.
  Future<List<double>> _maskerFor(double seconds) async {
    switch (widget.masker) {
      case MusicMasker.music:
        return musicMaskerStimulus(
            seconds: seconds, seed: widget.seed + _session.completedTrials);
      case MusicMasker.speechBabble:
        try {
          _babbleAsset ??= await _loadBabbleAsset();
          final src = _babbleAsset!;
          final n = (seconds * kSampleRate).round();
          final start =
              (widget.seed * 131 + _session.completedTrials * 977) % src.length;
          return List<double>.generate(n, (i) => src[(start + i) % src.length]);
        } catch (_) {
          // Asset unavailable (tests / stripped bundles): synthetic babble.
        }
        return multiTalkerBabble(
            seconds: seconds, seed: widget.seed + _session.completedTrials);
      case MusicMasker.syntheticBabble:
        return multiTalkerBabble(
            seconds: seconds, seed: widget.seed + _session.completedTrials);
    }
  }

  List<double>? _babbleAsset;

  /// Decodes the 24 kHz speech-babble asset and duplicates samples up to the
  /// 48 kHz synthesis rate (nearest-neighbour is fine for a masker).
  Future<List<double>> _loadBabbleAsset() async {
    final ByteData bytes =
        await rootBundle.load('assets/stimuli/noise_babble_speech.wav');
    final decoded = decodeWav16(bytes.buffer.asUint8List());
    final factor = (kSampleRate / decoded.sampleRate).round().clamp(1, 4);
    if (factor == 1) return decoded.samples;
    return List<double>.generate(
        decoded.samples.length * factor, (i) => decoded.samples[i ~/ factor]);
  }

  void _choose(int index) {
    final trial = _current;
    if (trial == null || _chosenIndex != null || !_played) return;
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
    // Hands-free flow: a wrong answer re-plays the tune twice, then the next
    // question follows automatically after a short pause.
    _autoAdvanceTimer?.cancel();
    if (!correct) {
      unawaited(_replayFailThenAdvance());
    } else {
      _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
        if (mounted && !_finished && _chosenIndex != null) _advance();
      });
    }
  }

  /// Wrong-answer sequence: replay the exact presented mix twice, a brief
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
    if (!mounted || _finished || _chosenIndex == null) return;
    // Cancellable beat before advancing (a raw Future.delayed would leak a
    // timer past dispose).
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(kTrialFeedbackDelay, () {
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

  String _fmtTime(Duration d) {
    final m = (d.inSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _resultsView(context);
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final answered = _chosenIndex != null;
    return TrialScaffold(
      title: 'Music in noise',
      subtitle: 'Melody recognition · adaptive SNR',
      instruction: 'Listen through the chatter, then name the tune.',
      validationBadge: const ValidationBadge(validationStatus: 'demo_only'),
      liveResults: _results,
      helpText: 'Measures the melody-to-babble ratio at which you still '
          'recognise familiar tunes — the musical counterpart of the '
          'words-in-noise test.',
      pills: [
        MetaPill(text: 'SNR ${_session.currentSnrDb.toStringAsFixed(0)} dB'),
        MetaPill(
            icon: Icons.tag,
            text: 'Trial ${_session.trialNumber}/${widget.maxTrials}'),
        MetaPill(
            icon: Icons.music_off,
            text: switch (widget.masker) {
              MusicMasker.speechBabble => 'Speech babble',
              MusicMasker.syntheticBabble => 'Synthetic babble',
              MusicMasker.music => 'Competing music',
            }),
        const MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
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
      statusRight: 'Elapsed Time ${_fmtTime(_sw.elapsed)}',
      onStop: _finish,
      onDigitKey: (d) {
        if (d >= 1 && d <= trial.choices.length) _choose(d - 1);
      },
      footer: answered
          ? Column(
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
                    Text(
                      _lastCorrect!
                          ? 'Correct'
                          : 'It was: '
                              '${kMelodyTitles[trial.target] ?? trial.target}',
                      style: const TextStyle(color: Color(0xffe2e8f0)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _advance,
                  child: Text(_session.isComplete ? 'See results' : 'Next'),
                ),
              ],
            )
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < trial.choices.length; i++)
                _MelodyButton(
                  label: kMelodyTitles[trial.choices[i]] ?? trial.choices[i],
                  enabled: _played && !answered,
                  correct: answered && i == trial.targetIndex,
                  wrong:
                      answered && _chosenIndex == i && i != trial.targetIndex,
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
    final t = _session.thresholdSnrDb;
    return Scaffold(
      appBar: AppBar(title: const Text('Music in noise')),
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
                  t == null
                      ? 'No threshold'
                      : '${t > 0 ? '+' : ''}${t.toStringAsFixed(1)} dB SNR',
                  style: const TextStyle(
                      color: Color(0xff3b82f6),
                      fontSize: 38,
                      fontWeight: FontWeight.w900),
                ),
              ),
              Center(
                child: Text(
                  t == null
                      ? 'Too few reversals to estimate a threshold.'
                      : 'Melody-recognition threshold in babble '
                          '(lower = better).',
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
              const SizedBox(height: 14),
              Text(
                'Synthesized public-domain melodies in synthetic babble '
                '(demo stimuli) — task-relative, not normed, not a '
                'diagnosis.',
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

class _MelodyButton extends StatelessWidget {
  const _MelodyButton({
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
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: correct || wrong ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: enabled || correct || wrong
                      ? const Color(0xffe2e8f0)
                      : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
