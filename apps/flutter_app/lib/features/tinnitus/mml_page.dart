import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/mml.dart';
import '../../core/tinnitus/tinnitus_store.dart';
import '../common/trial_scaffold.dart';

/// Tinnitus Minimum Masking Level (MML). Broadband noise is presented at
/// increasing level until the listener reports their tinnitus is masked. The
/// lowest masking level is averaged over a few ascending runs. Subjective
/// research aid — relative dB, not a diagnosis; master volume is never changed.
class MmlPage extends StatefulWidget {
  const MmlPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.maxTrials = 25,
    this.audioPort,
    this.store,
    this.onCompleted,
  });

  final double comfortableLevel;
  final int maxTrials;
  final AudioPort? audioPort;
  final TinnitusStore? store;
  final void Function(double mmlDb)? onCompleted;

  @override
  State<MmlPage> createState() => _MmlPageState();
}

class _MmlPageState extends State<MmlPage> {
  late final MmlSession _session = MmlSession(maxTrials: widget.maxTrials);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final TinnitusStore _store = widget.store ?? TinnitusStore();

  final Stopwatch _sw = Stopwatch()..start();
  bool _played = false;
  bool _finished = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
  }

  Future<void> _play() async {
    final amp = relativeDbToAmplitude(_session.levelDb);
    setState(() => _played = true);
    try {
      await _audio.playWav(
          encodeWav16(whiteNoise(seconds: 1.5, amp: amp, seed: 7)));
    } catch (_) {
      // ignore playback failure
    }
  }

  void _respond(MaskingResponse r) {
    if (!_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _session.submit(r, latencyMs: latency);
    if (_session.isComplete) {
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
    setState(() => _finished = true);
    await _store.saveMml(_session.mmlDb);
    widget.onCompleted?.call(_session.mmlDb);
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
      title: 'Minimum masking level',
      subtitle: 'Tinnitus',
      instruction: 'Does this noise cover your tinnitus?',
      instructionIcon: Icons.blur_on,
      enableShortcuts: false,
      pills: [
        MetaPill(
            icon: Icons.graphic_eq,
            text: 'Noise ${_session.levelDb.toStringAsFixed(0)} dB'),
        MetaPill(
            icon: Icons.check_circle_outline,
            text: 'Samples ${_session.samplesCollected}/3'),
        MetaPill(icon: Icons.lock, text: 'Volume locked'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play noise',
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
        child: !_played
            ? const Text('Press play to hear the masking noise.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff94a3b8)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 320,
                    child: Semantics(
                      button: true,
                      label: 'I can still hear it',
                      child: FilledButton.icon(
                        onPressed: () =>
                            _respond(MaskingResponse.stillHear),
                        icon: const Icon(Icons.hearing),
                        label: const Text('I can still hear it'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 320,
                    child: Semantics(
                      button: true,
                      label: 'Tinnitus is gone',
                      child: FilledButton.icon(
                        onPressed: () => _respond(MaskingResponse.gone),
                        icon: const Icon(Icons.check),
                        label: const Text('Tinnitus is gone'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final sd = _session.mmlSd;
    return Scaffold(
      appBar: AppBar(title: const Text('Minimum masking level')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Minimum masking level',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(
                '${_session.mmlDb.toStringAsFixed(1)} dB'
                '${sd == null ? '' : ' ± ${sd.toStringAsFixed(1)}'}',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text(
                'Relative masking level on uncalibrated audio — subjective '
                'research measurement, not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_session.mmlDb),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
