import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/loudness_match.dart';
import '../../core/tinnitus/tinnitus_store.dart';
import '../common/trial_scaffold.dart';

/// Tinnitus loudness matching at the matched pitch. A tone is presented and the
/// listener says whether it is louder than / softer than / about the same as
/// their tinnitus; the level brackets toward a match. Subjective research aid —
/// relative dB SL, not a diagnosis; master volume is never changed.
class LoudnessMatchPage extends StatefulWidget {
  const LoudnessMatchPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.frequencyHz,
    this.maxTrials = 20,
    this.audioPort,
    this.store,
    this.onCompleted,
  });

  final double comfortableLevel;

  /// Fixed match frequency; when null it is loaded from [TinnitusStore] (or
  /// defaults to 4000 Hz if no pitch match exists yet).
  final double? frequencyHz;
  final int maxTrials;
  final AudioPort? audioPort;
  final TinnitusStore? store;
  final void Function(double matchedDb)? onCompleted;

  @override
  State<LoudnessMatchPage> createState() => _LoudnessMatchPageState();
}

class _LoudnessMatchPageState extends State<LoudnessMatchPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final TinnitusStore _store = widget.store ?? TinnitusStore();

  LoudnessMatchSession? _session;
  final Stopwatch _sw = Stopwatch()..start();
  bool _played = false;
  bool _finished = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var freq = widget.frequencyHz;
    if (freq == null) {
      final profile = await _store.load();
      freq = profile.pitchHz ?? 4000;
    }
    if (!mounted) return;
    setState(() {
      _session = LoudnessMatchSession(
        frequencyHz: freq!,
        maxTrials: widget.maxTrials,
      );
      _shownAt = DateTime.now();
    });
  }

  Future<void> _play() async {
    final s = _session;
    if (s == null) return;
    final amp = relativeDbToAmplitude(s.levelDb);
    setState(() => _played = true);
    try {
      await _audio
          .playWav(encodeWav16(tone(seconds: 1.2, freqHz: s.frequencyHz, amp: amp)));
    } catch (_) {
      // ignore playback failure
    }
  }

  void _respond(LoudnessResponse r) {
    final s = _session;
    if (s == null || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    s.submit(r, latencyMs: latency);
    if (s.isComplete) {
      _finish();
    } else {
      setState(() {
        _played = false;
        _shownAt = DateTime.now();
      });
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    final s = _session;
    setState(() => _finished = true);
    if (s != null) {
      await _store.saveLoudness(s.matchedDb);
      widget.onCompleted?.call(s.matchedDb);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) return _results(context, s);
    return TrialScaffold(
      title: 'Tinnitus loudness match',
      subtitle: 'Tinnitus',
      instruction: 'Is this tone louder or softer than your tinnitus?',
      instructionIcon: Icons.volume_up,
      enableShortcuts: false,
      pills: [
        MetaPill(icon: Icons.music_note, text: '${s.frequencyHz.round()} Hz'),
        MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play tone',
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
      statusLeft: 'Trial ${s.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      child: Center(
        child: !_played
            ? const Text('Press play to hear the tone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff94a3b8)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _respBtn('Louder than my tinnitus',
                      () => _respond(LoudnessResponse.louder)),
                  const SizedBox(height: 12),
                  _respBtn('About the same',
                      () => _respond(LoudnessResponse.same)),
                  const SizedBox(height: 12),
                  _respBtn('Softer than my tinnitus',
                      () => _respond(LoudnessResponse.softer)),
                ],
              ),
      ),
    );
  }

  Widget _respBtn(String label, VoidCallback onTap) => SizedBox(
        width: 320,
        child: Semantics(
          button: true,
          label: label,
          child: FilledButton(onPressed: onTap, child: Text(label)),
        ),
      );

  Widget _results(BuildContext context, LoudnessMatchSession s) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tinnitus loudness match')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Matched loudness',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text('${s.matchedDb.toStringAsFixed(1)} dB SL',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('at ${s.frequencyHz.round()} Hz',
                style: const TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 16),
            const Text(
                'Relative sensation level on uncalibrated audio — subjective '
                'research match, not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(s.matchedDb),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
