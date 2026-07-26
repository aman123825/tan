import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/forced_choice.dart';
import '../../core/protocol_engine.dart'
    show flagLastTrial, lastTrialFlagged;
import '../../core/psychoacoustics.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

/// Temporal Modulation Transfer Function: modulation-detection thresholds at
/// 4–512 Hz (abbreviated staircase per rate) plotted as the classic TMTF
/// curve. 3AFC per trial — pick the fluttering burst.
class TmtfPage extends StatefulWidget {
  const TmtfPage({
    super.key,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final int seed;
  final AudioPort? audioPort;
  final void Function(TmtfSession session)? onCompleted;

  @override
  State<TmtfPage> createState() => _TmtfPageState();
}

class _TmtfPageState extends State<TmtfPage> {
  late final TmtfSession _session = TmtfSession();
  late final ThreeIntervalGenerator _generator =
      ThreeIntervalGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  final Stopwatch _sw = Stopwatch()..start();
  final Stopwatch _latency = Stopwatch();

  ThreeIntervalTrial? _trial;
  bool _playing = false;
  bool _played = false;
  int? _chosen;
  bool? _lastCorrect;
  bool _finished = false;
  Timer? _advanceTimer;
  final List<bool> _results = <bool>[];

  @override
  void initState() {
    super.initState();
    _nextTrial();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _nextTrial() {
    if (_session.isComplete) {
      _finish();
      return;
    }
    setState(() {
      _trial = _generator.next();
      _played = false;
      _chosen = null;
      _lastCorrect = null;
    });
    unawaited(_play());
  }

  Future<void> _play() async {
    final trial = _trial;
    if (trial == null || _playing) return;
    setState(() => _playing = true);
    try {
      final seq = buildTmtfSequence(
        targetInterval: trial.targetInterval,
        depthDb: _session.currentDepthDb,
        rateHz: _session.currentRateHz,
        seed: widget.seed * 1000 + _session.completedTrials,
      );
      await _audio.playWav(encodeWav16(seq));
    } catch (_) {}
    if (!mounted) return;
    _latency
      ..reset()
      ..start();
    setState(() {
      _playing = false;
      _played = true;
    });
  }

  void _choose(int interval) {
    if (_chosen != null || !_played) return;
    _latency.stop();
    final rateBefore = _session.currentRateHz;
    final correct = _session.submit(_trial!.targetInterval, interval,
        latencyMs: _latency.elapsedMilliseconds);
    setState(() {
      _chosen = interval;
      _lastCorrect = correct;
      _results.add(correct);
    });
    final rateChanged =
        _session.isComplete || _session.currentRateHz != rateBefore;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(
        Duration(milliseconds: rateChanged ? 1400 : 900), () {
      if (mounted && !_finished && _chosen != null) _nextTrial();
    });
  }

  void _finish() {
    if (_finished) return;
    _advanceTimer?.cancel();
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmtTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _rateLabel(double r) =>
      r >= 1000 ? '${(r / 1000).toStringAsFixed(1)} kHz' : '${r.round()} Hz';

  @override
  Widget build(BuildContext context) {
    if (_finished) return _resultsView(context);
    final answered = _chosen != null;
    return TrialScaffold(
      title: 'Temporal modulation (TMTF)',
      subtitle: 'Envelope sensitivity · ${_session.rates.length} rates',
      instruction:
          'Three noise bursts play. One flutters — choose which.',
      isPlaying: _playing,
      validationBadge: const ValidationBadge(validationStatus: 'unvalidated'),
      liveResults: _results,
      helpText: 'Measures the shallowest amplitude flutter you can hear at '
          'several flutter speeds; the plotted curve is your temporal '
          'modulation transfer function.',
      pills: [
        MetaPill(
          icon: Icons.waves,
          text: 'Rate ${_rateLabel(_session.currentRateHz)} '
              '(${_session.rateNumber}/${_session.rates.length})',
        ),
        MetaPill(
          icon: Icons.tune,
          text: 'Depth ${_session.currentDepthDb.toStringAsFixed(0)} dB',
        ),
        MetaPill(icon: Icons.tag, text: 'Trial ${_session.trialNumber}'),
      ],
      transport: [
        TransportAction(
          icon: Icons.replay,
          label: 'Replay',
          color: TransportColors.replay,
          onTap: (_played && !answered && !_playing) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft:
          'Rate ${_session.rateNumber} of ${_session.rates.length}',
      statusRight: 'Elapsed Time ${_fmtTime(_sw.elapsed)}',
      onStop: _finish,
      onFlagLastTrial: answered
          ? () => setState(() => flagLastTrial(_session.records))
          : null,
      lastTrialFlagged: lastTrialFlagged(_session.records),
      onDigitKey: (d) {
        if (d >= 1 && d <= 3) _choose(d - 1);
      },
      footer: answered
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _lastCorrect! ? Icons.check_circle : Icons.cancel,
                  color: _lastCorrect!
                      ? const Color(0xff22c55e)
                      : const Color(0xffef4444),
                ),
                const SizedBox(width: 8),
                Text(_lastCorrect! ? 'Correct' : 'Not quite',
                    style: const TextStyle(color: Color(0xffe2e8f0))),
              ],
            )
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _SoundButton(
                    label: 'Sound ${i + 1}',
                    enabled: _played && !answered,
                    correct: answered && i == _trial!.targetInterval,
                    wrong: answered &&
                        _chosen == i &&
                        i != _trial!.targetInterval,
                    onTap: () => _choose(i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Temporal modulation (TMTF)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Modulation thresholds by rate',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Lower (more negative) = shallower flutter detected = finer '
                'envelope sensitivity. Typical listeners are most sensitive '
                'at low rates with a high-rate roll-off.',
                style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Container(
                height: 260,
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0x1affffff),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33ffffff)),
                ),
                child: CustomPaint(
                  key: const Key('tmtf-plot'),
                  painter: TmtfCurvePainter(session: _session),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 14),
              for (final r in _session.rates)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_rateLabel(r),
                          style:
                              const TextStyle(color: Color(0xff94a3b8))),
                      Text(
                        _session.thresholdFor(r) == null
                            ? 'not reached'
                            : '${_session.thresholdFor(r)!.toStringAsFixed(1)} dB',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xffe2e8f0)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Research measurement (cf. Viemeister, 1979) on uncalibrated '
                'audio — not a diagnosis.',
                style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
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

class _SoundButton extends StatelessWidget {
  const _SoundButton({
    required this.label,
    required this.enabled,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool correct;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = const Color(0x33ffffff);
    if (correct) {
      bg = const Color(0x3322c55e);
      border = const Color(0xff22c55e);
    } else if (wrong) {
      bg = const Color(0x33ef4444);
      border = const Color(0xffef4444);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: correct || wrong ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.waves,
                      size: 26,
                      color: enabled || correct || wrong
                          ? const Color(0xffe2e8f0)
                          : Colors.white38),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: enabled || correct || wrong
                              ? const Color(0xffe2e8f0)
                              : Colors.white38)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the classic TMTF curve: log rate (x) vs modulation-depth threshold
/// in dB (y, more sensitive = lower on the page like published TMTFs is NOT
/// used — here more negative is plotted toward the TOP so "higher = finer",
/// matching the app's other threshold plots).
class TmtfCurvePainter extends CustomPainter {
  TmtfCurvePainter({required this.session});

  final TmtfSession session;

  static const Color _grid = Color(0x33ffffff);
  static const Color _label = Color(0xff8b9bb4);
  static const Color _line = Color(0xff3b82f6);

  static const double _top = -40; // finest detectable depth at the top
  static const double _bottom = 0;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0, bottomPad = 24.0, topPad = 6.0, rightPad = 6.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    final rates = session.rates;
    double xOf(int i) => leftPad + plotW * i / (rates.length - 1);
    double yOf(double db) => topPad + plotH * (db - _top) / (_bottom - _top);

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    const textStyle = TextStyle(color: _label, fontSize: 10);

    for (var db = _top; db <= _bottom; db += 10) {
      final y = yOf(db);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${db.round()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }
    for (var i = 0; i < rates.length; i++) {
      final x = xOf(i);
      canvas.drawLine(Offset(x, topPad), Offset(x, topPad + plotH), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${rates[i].round()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topPad + plotH + 6));
    }

    final line = Paint()
      ..color = _line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    Offset? prev;
    for (var i = 0; i < rates.length; i++) {
      final t = session.thresholdFor(rates[i]);
      if (t == null) {
        prev = null;
        continue;
      }
      final p = Offset(xOf(i), yOf(t.clamp(_top, _bottom)));
      if (prev != null) canvas.drawLine(prev, p, line);
      canvas.drawCircle(p, 5, Paint()..color = _line);
      // Halo for readability against gridlines.
      canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      prev = p;
    }
  }

  @override
  bool shouldRepaint(TmtfCurvePainter oldDelegate) =>
      oldDelegate.session != session;
}
