import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/music_perception.dart';
import '../../core/settings/app_settings.dart';
import '../catalog/validation_badge.dart';

/// Beat tapping (production): tap along with a click track; scored on the
/// CONSISTENCY of tap-to-beat timing (SD of asynchronies — device latency
/// cancels out of a spread measure), plus hit rate and tempo matching.
class BeatTapPage extends StatefulWidget {
  const BeatTapPage({
    super.key,
    this.bpm = 90,
    this.beats = 24,
    this.audioPort,
    this.onCompleted,
  });

  final double bpm;
  final int beats;
  final AudioPort? audioPort;
  final void Function(BeatTapSession session)? onCompleted;

  @override
  State<BeatTapPage> createState() => _BeatTapPageState();
}

class _BeatTapPageState extends State<BeatTapPage> {
  late final BeatTapSession _session =
      BeatTapSession(bpm: widget.bpm, beats: widget.beats);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final Stopwatch _clock = Stopwatch();

  bool _running = false;
  bool _finished = false;
  int _tapCount = 0;
  Timer? _endTimer;

  @override
  void dispose() {
    _endTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _tapCount = 0;
    });
    _session.tapTimesMs.clear();
    final track = buildBeatTrack(bpm: widget.bpm, beats: widget.beats);
    // The clock starts with playback; a fixed end-timer covers ports that
    // return before the audio actually finishes.
    _clock
      ..reset()
      ..start();
    _endTimer?.cancel();
    _endTimer = Timer(
      Duration(milliseconds: _session.totalDurationMs.round() + 300),
      _finishRun,
    );
    try {
      await _audio.playWav(encodeWav16(track));
    } catch (_) {}
  }

  void _tap() {
    if (!_running || _finished) return;
    _session.addTap(_clock.elapsedMilliseconds.toDouble());
    setState(() => _tapCount++);
  }

  void _finishRun() {
    if (_finished) return;
    _endTimer?.cancel();
    _clock.stop();
    setState(() {
      _running = false;
      _finished = true;
    });
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _resultsView(context);
    final beatMs = _session.beatIntervalMs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beat tapping'),
        actions: [
          if (_running)
            IconButton(
              tooltip: 'End early',
              onPressed: _finishRun,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Listen to the count-in, then TAP the big pad on '
                          'every click. Keep going until the clicks stop.',
                          style: TextStyle(
                              color: Color(0xffe2e8f0),
                              fontSize: 15.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const ValidationBadge(validationStatus: 'unvalidated'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.bpm.round()} beats/min · '
                    '${widget.beats} scored beats · '
                    '4-beat count-in (${(beatMs / 1000).toStringAsFixed(2)} s '
                    'per beat)',
                    style: const TextStyle(
                        color: Color(0xff8b9bb4), fontSize: 12.5),
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Center(
                      child: _TapPad(
                        key: const Key('beat-tap-pad'),
                        enabled: _running,
                        tapCount: _tapCount,
                        onTap: _tap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_running)
                    FilledButton.icon(
                      key: const Key('beat-tap-start'),
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start the click track'),
                    )
                  else
                    Text('Taps: $_tapCount',
                        style: const TextStyle(
                            color: Color(0xff94a3b8),
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Production task — master volume never changes. '
                    'Research exercise, not a diagnosis.',
                    style:
                        TextStyle(color: Color(0xff8b9bb4), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    final theme = Theme.of(context);
    final sd = _session.sdAsynchronyMs;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Beat tapping')),
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
                  sd == null ? 'Too few taps' : '±${sd.toStringAsFixed(0)} ms',
                  style: const TextStyle(
                      color: Color(0xff3b82f6),
                      fontSize: 40,
                      fontWeight: FontWeight.w900),
                ),
              ),
              const Center(
                child: Text('Tapping consistency (SD of tap timing)',
                    style:
                        TextStyle(color: Color(0xff94a3b8), fontSize: 13)),
              ),
              const SizedBox(height: 16),
              row('Scored taps', '${_session.scoredTapCount}'),
              row('Beats hit (within ±25%)',
                  '${(_session.hitRate * 100).round()}%'),
              if (_session.meanAsynchronyMs != null)
                row(
                    'Mean offset (incl. device latency)',
                    '${_session.meanAsynchronyMs! >= 0 ? '+' : ''}'
                        '${_session.meanAsynchronyMs!.toStringAsFixed(0)} ms'),
              if (_session.tempoRatio != null)
                row('Tempo match (1.00 = exact)',
                    _session.tempoRatio!.toStringAsFixed(2)),
              const SizedBox(height: 12),
              Text(
                'Steady adult tappers typically show an SD near 20–50 ms at '
                'this tempo (Repp, 2005). The mean offset includes your '
                'device\'s audio latency, so the SD is the meaningful '
                'number. Research measurement — not a diagnosis.',
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

class _TapPad extends StatelessWidget {
  const _TapPad({
    super.key,
    required this.enabled,
    required this.tapCount,
    required this.onTap,
  });

  final bool enabled;
  final int tapCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pulse = enabled && tapCount > 0 && !reduceMotionActive(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Tap on every click',
      child: AnimatedScale(
        // A subtle press pulse keyed to the tap count (decorative only).
        scale: pulse && tapCount.isOdd ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Material(
          color: enabled ? const Color(0x333b82f6) : const Color(0xff293548),
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? const Color(0xff3b82f6)
                  : const Color(0x33ffffff),
              width: 3,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 220,
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app,
                        size: 54,
                        color: enabled
                            ? const Color(0xffe2e8f0)
                            : Colors.white38),
                    const SizedBox(height: 8),
                    Text('TAP',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: enabled
                                ? const Color(0xffe2e8f0)
                                : Colors.white38)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
