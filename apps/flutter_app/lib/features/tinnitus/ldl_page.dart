import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/ldl.dart';
import '../common/trial_scaffold.dart';

/// Hyperacusis Loudness Discomfort Level (LDL) screen. Tones ascend in 5 dB
/// steps at 500/1000/2000/4000 Hz until the listener presses "Too loud!".
///
/// SAFETY: on-signal amplitude is hard-capped at 0.7 (the master-volume lock
/// also applies). Reaching the cap records it as the LDL and moves on — the
/// tone can never get louder. Relative dB only, uncalibrated, not a diagnosis.
class LdlPage extends StatefulWidget {
  const LdlPage({
    super.key,
    this.comfortableLevel = 0.4,
    this.audioPort,
    this.onCompleted,
  });

  final double comfortableLevel;
  final AudioPort? audioPort;
  final void Function(LdlSession session)? onCompleted;

  @override
  State<LdlPage> createState() => _LdlPageState();
}

class _LdlPageState extends State<LdlPage> {
  late final LdlSession _session = LdlSession();
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

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
    // Amplitude is already capped at 0.7 by the session/level helper.
    final amp = _session.currentAmplitude;
    setState(() => _played = true);
    try {
      await _audio.playWav(
          encodeWav16(tone(seconds: 1.0, freqHz: _session.currentFrequencyHz, amp: amp)));
    } catch (_) {
      // ignore playback failure
    }
  }

  void _louder() {
    if (!_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _session.louder(latencyMs: latency);
    _afterResponse();
  }

  void _tooLoud() {
    if (!_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    _session.tooLoud(latencyMs: latency);
    _afterResponse();
  }

  void _afterResponse() {
    if (_session.isComplete) {
      _finish();
    } else {
      setState(() {
        _played = false;
        _shownAt = DateTime.now();
      });
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _results(context);
    final atCap = _session.atCap;
    return TrialScaffold(
      title: 'Loudness discomfort (LDL)',
      subtitle: 'Hyperacusis',
      instruction: 'Raise the level until it is uncomfortable.',
      instructionIcon: Icons.volume_up,
      enableShortcuts: false,
      pills: [
        MetaPill(
            icon: Icons.music_note,
            text: '${_session.currentFrequencyHz.round()} Hz '
                '(${_session.frequencyIndex + 1}/${_session.frequencyCount})'),
        MetaPill(
            icon: Icons.graphic_eq,
            text: 'Level ${_session.levelDb.toStringAsFixed(0)} dB'),
        const MetaPill(icon: Icons.shield, text: 'Cap 0.7'),
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
      statusLeft: 'Frequency ${_session.frequencyIndex + 1} '
          'of ${_session.frequencyCount}',
      statusRight: 'Elapsed Time ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      child: Center(
        child: !_played
            ? const Text('Press play to hear the tone at this level.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xff94a3b8)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 320,
                    child: Semantics(
                      button: true,
                      label: 'Too loud',
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xffef4444)),
                        onPressed: _tooLoud,
                        icon: const Icon(Icons.volume_off),
                        label: const Text('Too loud!'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 320,
                    child: Semantics(
                      button: true,
                      label: atCap
                          ? 'At safety cap — record and continue'
                          : 'Comfortable, make it louder',
                      child: OutlinedButton.icon(
                        onPressed: _louder,
                        icon: Icon(atCap ? Icons.flag : Icons.arrow_upward),
                        label: Text(atCap
                            ? 'At safe cap — record & next'
                            : 'Comfortable — louder'),
                      ),
                    ),
                  ),
                  if (atCap) ...[
                    const SizedBox(height: 10),
                    const Text('Safety cap reached — cannot present louder.',
                        style: TextStyle(color: Color(0xfffbbf24), fontSize: 12.5)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final results = _session.results;
    final mean = _session.meanLdlDb;
    return Scaffold(
      appBar: AppBar(title: const Text('Loudness discomfort (LDL)')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('LDL screen',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            for (final f in _session.frequencies)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${f.round()} Hz',
                        style: const TextStyle(color: Color(0xff94a3b8))),
                    Text(
                        results[f] == null
                            ? '—'
                            : '${results[f]!.toStringAsFixed(0)} dB',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            const Divider(color: Color(0x33ffffff), height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mean LDL',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Text(mean == null ? '—' : '${mean.toStringAsFixed(0)} dB',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
                'Relative discomfort levels on uncalibrated audio (amplitude '
                'capped at 0.7) — research screen, not a diagnosis.',
                style: TextStyle(color: Color(0xff94a3b8))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
