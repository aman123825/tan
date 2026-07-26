import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/pitch_match.dart';
import '../../core/tinnitus/tinnitus_store.dart';
import '../common/trial_scaffold.dart';

/// Tinnitus pitch matching (2AFC binary search). Two tones are played in
/// sequence and the listener picks the one closer to their tinnitus; the search
/// range halves toward the choice each trial. The matched frequency is stored
/// (reused by the sound-therapy notch). Subjective research aid — not a
/// diagnosis; master volume is never changed.
class PitchMatchPage extends StatefulWidget {
  const PitchMatchPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.maxTrials = 18,
    this.audioPort,
    this.store,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final AudioPort? audioPort;
  final TinnitusStore? store;
  final void Function(double matchedHz)? onCompleted;

  @override
  State<PitchMatchPage> createState() => _PitchMatchPageState();
}

class _PitchMatchPageState extends State<PitchMatchPage> {
  late final PitchMatchSession _session =
      PitchMatchSession(maxTrials: widget.maxTrials);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final TinnitusStore _store = widget.store ?? TinnitusStore();

  final Stopwatch _sw = Stopwatch()..start();
  bool _played = false;
  bool _finished = false;

  /// When true, the first tone in the pair is the higher candidate (randomized
  /// per trial to avoid an order bias).
  bool _firstIsHigher = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _prepareTrial();
  }

  void _prepareTrial() {
    _firstIsHigher = _session.completedTrials.isEven;
    _played = false;
    _shownAt = DateTime.now();
  }

  Future<void> _play() async {
    final hiFirst = _firstIsHigher;
    final f1 = hiFirst ? _session.higherHz : _session.lowerHz;
    final f2 = hiFirst ? _session.lowerHz : _session.higherHz;
    final buffer = concat(<List<double>>[
      tone(seconds: 1.0, freqHz: f1, amp: 0.25),
      silence(0.4),
      tone(seconds: 1.0, freqHz: f2, amp: 0.25),
    ]);
    setState(() => _played = true);
    try {
      await _audio.playWav(encodeWav16(buffer));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _choose(bool choseTone2) {
    if (!_played) return;
    // Map the chosen playback position to the higher/lower candidate.
    final choseHigher = choseTone2 ? !_firstIsHigher : _firstIsHigher;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _session.submit(choseHigher, latencyMs: latency);
    if (_session.isComplete) {
      _finish();
    } else {
      setState(_prepareTrial);
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    setState(() => _finished = true);
    await _store.savePitch(_session.matchedHz);
    widget.onCompleted?.call(_session.matchedHz);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _results(context);
    return TrialScaffold(
      title: 'Tinnitus pitch match',
      subtitle: 'Tinnitus',
      instruction: 'Which tone is closer to your tinnitus?',
      instructionIcon: Icons.graphic_eq,
      enableShortcuts: false,
      pills: [
        MetaPill(
          icon: Icons.search,
          text: 'Search ${_session.rangeLowHz.round()}–'
              '${_session.rangeHighHz.round()} Hz',
        ),
        MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play both tones',
          color: TransportColors.play,
          onTap: _play,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Trial ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_played)
              const Text('Press play — you will hear Tone 1, then Tone 2.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xff94a3b8)))
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _choiceButton('Tone 1', () => _choose(false)),
                  const SizedBox(width: 20),
                  _choiceButton('Tone 2', () => _choose(true)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _choiceButton(String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: '$label closer',
      child: SizedBox(
        width: 130,
        height: 96,
        child: FilledButton(
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tinnitus pitch match')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Matched pitch',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text('${_session.matchedHz.round()} Hz',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Final search range '
                '${_session.rangeLowHz.round()}–${_session.rangeHighHz.round()} Hz',
                style: const TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 16),
            const Text(
                'Saved for the sound-therapy notch. Subjective research match '
                'on uncalibrated audio — not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_session.matchedHz),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
