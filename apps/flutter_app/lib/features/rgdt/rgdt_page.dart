import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/rgdt.dart';
import '../catalog/validation_badge.dart';
import '../common/norm_tile.dart';
import '../common/trial_scaffold.dart';

/// Research-only, task-relative interpretation for the combined RGDT gap
/// threshold (adults ≤ 10 ms, children ≤ 20 ms; Keith, 2000). Illustrative on
/// uncalibrated audio; never a diagnosis.
NormResult rgdtNorm(double? ms) {
  if (ms == null) return const NormResult.insufficient();
  const cite = 'RGDT norm: adults ≤ 10 ms, children ≤ 20 ms (Keith, 2000)';
  if (ms <= 6) {
    return const NormResult(NormBand.betterThanTypical,
        'A combined gap threshold ≤ 6 ms is fine temporal resolution.', cite);
  }
  if (ms <= 10) {
    return const NormResult(NormBand.withinTypical,
        '≤ 10 ms is within the typical adult RGDT range.', cite);
  }
  if (ms <= 20) {
    return const NormResult(NormBand.slightlyBelowTypical,
        '10–20 ms is within the child range but above the adult cut-off.',
        cite);
  }
  return const NormResult(NormBand.belowTypical,
      '> 20 ms is outside the typical RGDT range at any age.', cite);
}

/// Builds a tone-pair stimulus: two brief [freqHz] bursts separated by [gapMs]
/// of silence. A [gapMs] of 0 yields one continuous (fused) sound.
List<double> gapPairSamples(double freqHz, double gapMs,
    {int sampleRate = kSampleRate}) {
  final burst =
      tone(seconds: 0.015, freqHz: freqHz, amp: 0.3, fadeMs: 2, sampleRate: sampleRate);
  if (gapMs <= 0) {
    return concat([burst, burst]); // continuous → one sound
  }
  return concat([burst, silence(gapMs / 1000, sampleRate), burst]);
}

/// Random Gap Detection Test renderer: at each of four frequencies the listener
/// hears a tone pair (or a single fused sound on catch trials) and reports
/// "one sound" or "two sounds". The gap-detection threshold per frequency is
/// the smallest gap detected on ≥ 2/3 of trials; the combined threshold is the
/// mean across frequencies.
class RgdtPage extends StatefulWidget {
  const RgdtPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'random_gap_detection',
    required this.comfortableLevel,
    this.presentationsPerGap = 2,
    this.catchPerFrequency = 1,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int presentationsPerGap;
  final int catchPerFrequency;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(RgdtSession session)? onCompleted;

  @override
  State<RgdtPage> createState() => _RgdtPageState();
}

class _RgdtPageState extends State<RgdtPage> {
  late final RgdtGenerator _generator = RgdtGenerator(
    presentationsPerGap: widget.presentationsPerGap,
    catchPerFrequency: widget.catchPerFrequency,
    seed: widget.seed,
  );
  late final RgdtSession _session = RgdtSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    totalTrials: _generator.totalTrials,
  );
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  RgdtTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  bool _answered = false;
  bool? _lastCorrect;
  bool _finished = false;
  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

  int get _levelPercent => (widget.comfortableLevel * 100).round();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  void _nextTrial() {
    if (_generator.isComplete) {
      _finish();
      return;
    }
    setState(() {
      _current = _generator.next();
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _answered = false;
      _lastCorrect = null;
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
      final samples = gapPairSamples(trial.frequencyHz, trial.gapMs);
      await _audio.playWav(encodeWav16(samples));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _respond(bool heardTwo) {
    final trial = _current;
    if (trial == null || _answered || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, heardTwo, latencyMs: latency, replays: _replays);
    setState(() {
      _answered = true;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_generator.isComplete) {
      _finish();
    } else {
      _nextTrial();
    }
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Random gap detection')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildResults(context),
        ),
      );
    }
    final trial = _current;
    if (trial == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TrialScaffold(
      title: 'Random gap detection',
      subtitle: 'Temporal resolution',
      instruction: 'Play the sound. Did you hear one sound or two?',
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        MetaPill(icon: Icons.lock, text: 'Level $_levelPercent%'),
        MetaPill(
            icon: Icons.music_note,
            text: '${trial.frequencyHz.toStringAsFixed(0)} Hz'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_played && !_answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !_answered && _replays < _maxReplays) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft:
          'Question ${_session.trialNumber} of ${_generator.totalTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: _answered ? _footer() : null,
      child: _responseArea(),
    );
  }

  Widget _responseArea() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CountButton(
                    label: 'One sound',
                    icon: Icons.circle,
                    enabled: _played && !_answered,
                    onTap: () => _respond(false),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _CountButton(
                    label: 'Two sounds',
                    icon: Icons.more_horiz,
                    enabled: _played && !_answered,
                    onTap: () => _respond(true),
                  ),
                ),
              ],
            ),
            if (!_played && !_answered)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Play the sound to enable the choices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xff94a3b8))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.records.isNotEmpty && _lastCorrect != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_lastCorrect! ? Icons.check_circle : Icons.cancel,
                  color: _lastCorrect!
                      ? const Color(0xff22c55e)
                      : const Color(0xffef4444)),
              const SizedBox(width: 8),
              Text(_lastCorrect! ? 'Correct' : 'Not quite'),
            ],
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_generator.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final perFreq = _session.perFrequencyThresholds;
    final combined = _session.combinedThresholdMs;
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        for (final f in _session.frequencies)
          _SummaryRow(
            label: '${f.toStringAsFixed(0)} Hz threshold',
            value: perFreq.containsKey(f)
                ? '${perFreq[f]!.toStringAsFixed(0)} ms'
                : 'not reached',
          ),
        _SummaryRow(
          label: 'Combined threshold',
          value: combined == null
              ? 'not reached'
              : '${combined.toStringAsFixed(1)} ms',
        ),
        const SizedBox(height: 14),
        NormTile(rgdtNorm(combined)),
        const SizedBox(height: 12),
        Text(
            'Research measurement only — not a diagnosis. Synthesized tone '
            'pairs on uncalibrated audio; this is not a dB HL test.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: const Color(0xff94a3b8))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
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
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: const Color(0xff293548),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x33ffffff)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 30,
                    color: enabled
                        ? const Color(0xffe2e8f0)
                        : Colors.white38),
                const SizedBox(height: 10),
                Text(label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? const Color(0xffe2e8f0)
                          : Colors.white38,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff94a3b8))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
