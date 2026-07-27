import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/difficulty.dart';
import '../../core/mld_test.dart';
import '../common/trial_scaffold.dart';

/// Masking Level Difference test page.
///
/// Alternates between S₀N₀ and SπN₀ conditions, adaptively finding threshold
/// in each. The listener presses "Heard tone" or "No tone" after each stimulus.
class MldTestPage extends StatefulWidget {
  const MldTestPage({
    super.key,
    this.maxTrialsPerCondition = 30,
    this.difficulty = DifficultyLevel.medium,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final int maxTrialsPerCondition;

  /// Starting difficulty — sets the staircase start level. A higher level (easy)
  /// makes the tone easier to detect. Defaults to [DifficultyLevel.medium].
  final DifficultyLevel difficulty;

  final int seed;
  final AudioPort? audioPort;
  final void Function(MldSession session)? onCompleted;

  @override
  State<MldTestPage> createState() => _MldTestPageState();
}

class _MldTestPageState extends State<MldTestPage> {
  /// Starting tone amplitude per difficulty (higher = easier to hear).
  /// Medium keeps the original 0.4 default.
  double get _startLevel => switch (widget.difficulty) {
        DifficultyLevel.easy => 0.6,
        DifficultyLevel.medium => 0.4,
        DifficultyLevel.hard => 0.3,
        DifficultyLevel.expert => 0.2,
      };

  late final MldSession _session = MldSession(startLevel: _startLevel);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final Stopwatch _sw = Stopwatch()..start();
  final Random _rng = Random();

  int _trialCount = 0;
  String _currentCondition = 'S0N0';
  bool _tonePresent = true;
  bool _played = false;
  bool? _responded;
  bool _finished = false;

  MldStaircase get _currentStaircase =>
      _currentCondition == 'S0N0' ? _session.s0n0 : _session.spiN0;

  bool get _bothComplete => _session.s0n0.isComplete && _session.spiN0.isComplete;

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    if (_bothComplete || _trialCount >= widget.maxTrialsPerCondition * 2) {
      _finish();
      return;
    }
    // Alternate conditions, skipping completed ones
    if (_currentCondition == 'S0N0' && !_session.spiN0.isComplete) {
      _currentCondition = 'SpiN0';
    } else if (!_session.s0n0.isComplete) {
      _currentCondition = 'S0N0';
    }
    // 70% tone-present, 30% catch trials (no tone)
    _tonePresent = _rng.nextDouble() < 0.7;
    setState(() {
      _played = false;
      _responded = null;
    });
    _play();
  }

  Future<void> _play() async {
    setState(() => _played = true);
    try {
      final wav = buildMldStimulus(
        condition: _currentCondition,
        signalLevel: _currentStaircase.currentLevel,
        tonePresent: _tonePresent,
        seed: widget.seed + _trialCount,
      );
      await _audio.playWav(wav);
    } catch (_) {}
  }

  void _respond(bool heardTone) {
    if (_responded != null || !_played) return;
    _currentStaircase.respond(heardTone, _tonePresent);
    _trialCount++;
    setState(() => _responded = heardTone);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _nextTrial();
    });
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
    if (_finished) return _buildResults(context);
    return TrialScaffold(
      title: 'Masking Level Difference',
      subtitle: 'Binaural interaction',
      instruction: 'Did you hear a tone in the noise?',
      pills: [
        MetaPill(
          icon: Icons.headphones,
          text: 'Condition: $_currentCondition',
        ),
        MetaPill(
          icon: Icons.tag,
          text: 'Trial $_trialCount',
        ),
        MetaPill(
          icon: Icons.signal_cellular_alt,
          text: 'Level: ${widget.difficulty.label}',
        ),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Replay',
          color: TransportColors.play,
          onTap: _played && _responded == null ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'S0N0: ${_session.s0n0.reversals}/8  ·  SπN0: ${_session.spiN0.reversals}/8',
      statusRight: 'Elapsed ${_fmt(_sw.elapsed)}',
      onStop: _finish,
      child: _responseButtons(),
    );
  }

  Widget _responseButtons() {
    final answered = _responded != null;
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ResponseButton(
            icon: Icons.check_circle_outline,
            label: 'Heard tone',
            color: const Color(0xff22c55e),
            enabled: _played && !answered,
            selected: _responded == true,
            onTap: () => _respond(true),
          ),
          const SizedBox(width: 24),
          _ResponseButton(
            icon: Icons.cancel_outlined,
            label: 'No tone',
            color: const Color(0xffef4444),
            enabled: _played && !answered,
            selected: _responded == false,
            onTap: () => _respond(false),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final mld = _session.mldDb;
    return Scaffold(
      appBar: AppBar(title: const Text('Masking Level Difference')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('MLD Results',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            if (mld != null) ...[
              Center(
                child: Text(
                  '${mld.toStringAsFixed(1)} dB',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: mld >= 10
                        ? const Color(0xff22c55e)
                        : const Color(0xffef4444),
                  ),
                ),
              ),
              const Center(
                child: Text('Masking Level Difference',
                    style: TextStyle(color: Color(0xff94a3b8)))),
            ] else
              const Center(
                child: Text('Not enough reversals to compute threshold',
                    style: TextStyle(color: Color(0xff94a3b8)))),
            const SizedBox(height: 16),
            Text('Interpretation: ${_session.interpret(25)}',
                style: const TextStyle(color: Color(0xffe2e8f0))),
            const SizedBox(height: 12),
            Text(
              'Normal: ≥ 10–12 dB (adults), ≥ 9 dB (children)\n'
              'Reference: Wilson et al., 2003; Interacoustics clinical protocol.\n'
              'Research measurement only — not a clinical diagnosis.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff8b9bb4)),
            ),
            const SizedBox(height: 24),
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

class _ResponseButton extends StatelessWidget {
  const _ResponseButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.2) : const Color(0xff293548),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? color : const Color(0x33ffffff),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 160,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: enabled ? color : Colors.white38),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: enabled ? const Color(0xffe2e8f0) : Colors.white38,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
