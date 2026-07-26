import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/therapy_sounds.dart';
import '../../core/tinnitus/tinnitus_store.dart';

/// Tinnitus sound-therapy player: white/pink/brown noise, rain, ocean, with an
/// optional notch at the listener's matched tinnitus frequency, a capped volume
/// control and an auto-stop timer.
///
/// SAFETY: therapy volume maps to an on-signal amplitude capped at
/// [kMaxSafeAmp] (0.7) — it can never exceed the safe level. This is a relaxing
/// player, not a diagnosis or treatment claim.
class SoundTherapyPage extends StatefulWidget {
  const SoundTherapyPage({super.key, this.audioPort, this.store});

  final AudioPort? audioPort;
  final TinnitusStore? store;

  @override
  State<SoundTherapyPage> createState() => _SoundTherapyPageState();
}

class _SoundTherapyPageState extends State<SoundTherapyPage> {
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final TinnitusStore _store = widget.store ?? TinnitusStore();

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const List<int> _durations = <int>[5, 10, 20, 30];

  TherapySound _sound = TherapySound.pink;
  double _volume = 0.5;
  bool _notch = false;
  double? _notchHz;
  int _durationMin = 10;
  int _remainingSec = 10 * 60;
  bool _playing = false;

  Uint8List? _wav;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _store.load().then((p) {
      if (mounted) setState(() => _notchHz = p.pitchHz);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audio.stop();
    super.dispose();
  }

  void _regenerate() {
    final amp = (_volume * kMaxSafeAmp).clamp(0.0, kMaxSafeAmp).toDouble();
    final samples = buildTherapy(
      _sound,
      seconds: 8,
      amp: amp,
      notchHz: (_notch && _notchHz != null) ? _notchHz : null,
    );
    _wav = encodeWav16(samples);
  }

  Future<void> _play() async {
    if (_playing) return;
    setState(() {
      _playing = true;
      if (_remainingSec <= 0) _remainingSec = _durationMin * 60;
    });
    _startTimer();
    _regenerate();
    // Loop the buffer until stopped or the timer elapses.
    while (_playing && mounted && _remainingSec > 0) {
      final buf = _wav;
      if (buf == null) break;
      try {
        await _audio.playWav(buf);
      } catch (_) {
        break;
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_playing) {
        t.cancel();
        return;
      }
      if (!mounted) return;
      setState(() => _remainingSec--);
      if (_remainingSec <= 0) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    if (mounted) setState(() => _playing = false);
    await _audio.stop();
  }

  /// Regenerates the buffer and (if playing) restarts the loop so the change is
  /// heard promptly.
  Future<void> _applyChangeWhilePlaying() async {
    if (!_playing) return;
    _regenerate();
    await _audio.stop(); // the play loop re-plays with the new buffer
  }

  String _fmt(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sound therapy')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _timerCard(),
              const SizedBox(height: 18),
              _sectionLabel('Sound'),
              const SizedBox(height: 10),
              _soundGrid(),
              const SizedBox(height: 18),
              _sectionLabel('Volume (safe-capped)'),
              Slider(
                key: const Key('therapy-volume'),
                value: _volume,
                onChanged: (v) {
                  setState(() => _volume = v);
                },
                onChangeEnd: (_) => _applyChangeWhilePlaying(),
              ),
              const SizedBox(height: 6),
              _sectionLabel('Timer'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _durations)
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: _durationMin == m,
                      onSelected: _playing
                          ? null
                          : (_) => setState(() {
                                _durationMin = m;
                                _remainingSec = m * 60;
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _notchTile(),
              const SizedBox(height: 20),
              _transport(),
              const SizedBox(height: 16),
              const Text(
                'A relaxing sound player — not a diagnosis or treatment. Keep '
                'the volume comfortably low; it is capped for safety.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timerCard() => Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x1affffff), Color(0x0dffffff)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: Column(
          children: [
            Text(_fmt(_remainingSec),
                key: const Key('therapy-remaining'),
                style: const TextStyle(
                    color: _ink, fontSize: 46, fontWeight: FontWeight.w800)),
            Text(_playing ? 'Playing ${_sound.label}' : 'Paused',
                style: const TextStyle(color: _muted)),
          ],
        ),
      );

  Widget _soundGrid() => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in TherapySound.values)
            ChoiceChip(
              avatar: Text(s.emoji),
              label: Text(s.label),
              selected: _sound == s,
              onSelected: (_) {
                setState(() => _sound = s);
                _applyChangeWhilePlaying();
              },
            ),
        ],
      );

  Widget _notchTile() {
    final hasPitch = _notchHz != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0x1affffff),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33ffffff)),
      ),
      child: SwitchListTile(
        key: const Key('therapy-notch'),
        contentPadding: EdgeInsets.zero,
        value: _notch && hasPitch,
        onChanged: hasPitch
            ? (v) {
                setState(() => _notch = v);
                _applyChangeWhilePlaying();
              }
            : null,
        title: const Text('Notch at my tinnitus frequency',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasPitch
              ? 'Removes energy around ${_notchHz!.round()} Hz'
              : 'Run the pitch match first to enable this',
          style: const TextStyle(color: _muted, fontSize: 12.5),
        ),
      ),
    );
  }

  Widget _transport() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: _playing ? 'Stop' : 'Play',
          child: FilledButton.icon(
            key: const Key('therapy-play'),
            onPressed: _playing ? _stop : _play,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(_playing ? 'Stop' : 'Play'),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: Color(0xff3b82f6),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8),
      );
}
