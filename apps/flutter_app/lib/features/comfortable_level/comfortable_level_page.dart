import 'package:flutter/material.dart';

import '../../core/safety.dart';

/// Comfortable-level check.
///
/// This is a *comfortable listening level* calibration, NOT a hearing test and
/// NOT a dB HL measurement. It uses the safety-guarded
/// [ComfortableLevelController]:
///   * `auto_volume` is always off;
///   * the level is user-set during calibration only;
///   * once the user continues, the level is LOCKED for the test so that no
///     response (right or wrong) can change master volume.
class ComfortableLevelPage extends StatefulWidget {
  const ComfortableLevelPage({super.key, this.controller, this.onLocked});

  final ComfortableLevelController? controller;

  /// Called once the user locks a comfortable level and continues. Receives the
  /// locked unitless level in [0, 1].
  final void Function(double level)? onLocked;

  @override
  State<ComfortableLevelPage> createState() => _ComfortableLevelPageState();
}

class _ComfortableLevelPageState extends State<ComfortableLevelPage> {
  late final ComfortableLevelController _controller =
      widget.controller ?? ComfortableLevelController(initialLevel: 0.3);

  bool _sampleLooping = false;

  int get _percent => (_controller.level * 100).round();

  void _onSliderChanged(double value) {
    // Guarded by the disabled state below, but we still route through the
    // safety controller so the invariant is centralised.
    setState(() => _controller.setLevel(value));
  }

  void _toggleSample() => setState(() => _sampleLooping = !_sampleLooping);

  void _lockAndContinue() {
    setState(() {
      _sampleLooping = false;
      _controller.lock();
    });
    widget.onLocked?.call(_controller.level);
  }

  void _reCalibrate() => setState(_controller.unlock);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _controller.isLocked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comfortable-level check'),
        actions: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: Chip(label: Text('RESEARCH ONLY')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Set a comfortable listening level',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const _NotAHearingTestNotice(),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq),
                      const SizedBox(width: 10),
                      Text(
                        'Calibration sample',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: locked ? null : _toggleSample,
                        icon: Icon(
                          _sampleLooping ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(_sampleLooping ? 'Stop' : 'Play'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A neutral sample loops while you adjust the level. Choose '
                    'a level that is clear and comfortable — never as loud as '
                    'you can bear.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xff94a3b8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: _controller.level,
                          min: _controller.minLevel,
                          max: _controller.maxLevel,
                          divisions: 20,
                          label: '$_percent%',
                          onChanged: locked ? null : _onSliderChanged,
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                  Center(
                    child: Text(
                      'Comfortable level: $_percent%',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!locked)
            FilledButton.icon(
              onPressed: _lockAndContinue,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock level and continue'),
            )
          else
            _LockedPanel(percent: _percent, onReCalibrate: _reCalibrate),
        ],
      ),
    );
  }
}

class _NotAHearingTestNotice extends StatelessWidget {
  const _NotAHearingTestNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffdf0dc),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xff8a5300)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a comfortable-level setting, not a hearing test. It does '
              'not measure dB HL. Volume never changes on its own, and it will '
              'be locked during the exercise so answers cannot change it.',
              style: TextStyle(color: Color(0xff8a5300)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedPanel extends StatelessWidget {
  const _LockedPanel({required this.percent, required this.onReCalibrate});

  final int percent;
  final VoidCallback onReCalibrate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x3322c55e),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock, color: Color(0xff22c55e)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Level locked at $percent% for this session. It will not '
                  'change during the exercise.',
                  style: const TextStyle(color: Color(0xff22c55e)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'You can stop the exercise at any time. Fatigue is not failure.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onReCalibrate,
          icon: const Icon(Icons.tune),
          label: const Text('Re-calibrate level'),
        ),
      ],
    );
  }
}
