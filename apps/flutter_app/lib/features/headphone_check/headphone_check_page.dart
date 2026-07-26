import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pattern_synth.dart';
import '../../core/audio/pcm_synth.dart';

/// Left/right headphone-orientation check.
///
/// Plays a 1000 Hz tone (0.5 s) in ONE ear at a time and asks the listener
/// which ear they heard it in. Both must be answered correctly to pass — this
/// confirms headphones are worn and not swapped before any per-ear (dichotic,
/// monaural pattern) test. Uses [encodeMonauralWav] so the signal is genuinely
/// present in only one channel.
class HeadphoneCheckPage extends StatefulWidget {
  const HeadphoneCheckPage({super.key, this.audioPort, this.onCompleted, this.earOrder});

  /// Real playback port (e.g. `JustAudioPort`). Defaults to a silent port so
  /// the page can be widget-tested without an audio device.
  final AudioPort? audioPort;

  /// Called with the pass/fail result when the check finishes.
  final void Function(bool passed)? onCompleted;

  /// Optional fixed ear order for deterministic testing. If null, randomized.
  final List<String>? earOrder;

  @override
  State<HeadphoneCheckPage> createState() => _HeadphoneCheckPageState();
}

class _HeadphoneCheckPageState extends State<HeadphoneCheckPage> {
  // Dark glass theme palette.
  static const Color _bg = Color(0xff0f172a);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);
  static const Color _good = Color(0xff22c55e);
  static const Color _bad = Color(0xffef4444);

  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  /// The ear under test at each step — randomized so the user can't predict.
  late final List<String> _ears = widget.earOrder ?? (['left', 'right']..shuffle());

  int _step = 0; // index into _ears
  bool _played = false; // tone for the current step has started
  bool _finished = false;
  final Map<String, String> _answers = <String, String>{}; // ear -> chosen side

  bool get _passed =>
      _answers['left'] == 'left' && _answers['right'] == 'right';

  Uint8List _toneFor(String ear) => encodeMonauralWav(
        tone(seconds: 0.5, freqHz: 1000, amp: 0.25),
        ear: ear,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _play() async {
    try {
      await _audio.playWav(_toneFor(_ears[_step]));
    } catch (_) {
      // Playback failures should not brick the check; the listener can retry.
    }
    if (!mounted) return;
    setState(() => _played = true);
  }

  void _answer(String side) {
    if (!_played || _finished) return;
    _answers[_ears[_step]] = side;
    if (_step < _ears.length - 1) {
      setState(() {
        _step += 1;
        _played = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    } else {
      setState(() => _finished = true);
      widget.onCompleted?.call(_passed);
    }
  }

  void _restart() {
    setState(() {
      _step = 0;
      _played = false;
      _finished = false;
      _answers.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Headphone check'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _finished ? _buildResult() : _buildTest(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTest() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            children: [
              const Icon(Icons.headphones, size: 48, color: _primary),
              const SizedBox(height: 12),
              Text(
                'Tone ${_step + 1} of ${_ears.length}',
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Which ear did you hear the tone in?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Put your headphones on. A short 1000 Hz tone plays in one ear.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _SideButton(
                key: const Key('side-left'),
                label: 'Left',
                icon: Icons.arrow_back,
                enabled: _played,
                onTap: () => _answer('left'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SideButton(
                key: const Key('side-right'),
                label: 'Right',
                icon: Icons.arrow_forward,
                enabled: _played,
                onTap: () => _answer('right'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: 'Replay tone',
          child: OutlinedButton.icon(
            onPressed: _play,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.replay),
            label: Text(_played ? 'Replay tone' : 'Playing…'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Listen carefully — the tone plays in only one ear.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final passed = _passed;
    final color = passed ? _good : _bad;
    return Column(
      key: const Key('headphone-result'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          borderColor: color,
          child: Column(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                size: 72,
                color: color,
              ),
              const SizedBox(height: 14),
              Text(
                passed ? 'Headphones verified' : 'Check failed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                passed
                    ? 'You correctly identified both ears. Left/right '
                        'orientation is confirmed.'
                    : 'The ears did not match. Your headphones may be swapped '
                        '(left/right reversed) or not seated. Swap or reseat '
                        'them and try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('headphone-continue'),
          onPressed: () => Navigator.of(context).maybePop(passed),
          style: FilledButton.styleFrom(
            backgroundColor: passed ? _good : _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(passed ? 'Continue' : 'Continue anyway'),
        ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Try the headphone check again',
          child: OutlinedButton.icon(
            key: const Key('headphone-retry'),
            onPressed: _restart,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.replay),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? _border),
      ),
      child: child,
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xffe2e8f0);
    const primary = Color(0xff3b82f6);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label ear',
      child: Material(
        color: enabled ? const Color(0x1a3b82f6) : const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: enabled ? primary : const Color(0x33ffffff),
                width: enabled ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 38, color: enabled ? primary : Colors.white38),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? ink : Colors.white38,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
