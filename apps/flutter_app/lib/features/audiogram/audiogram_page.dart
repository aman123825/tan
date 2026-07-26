import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/audio/audio_port.dart';
import '../../core/audio/pattern_synth.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/audiogram.dart';
import '../../core/noah_export.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';
import '../settings/text_saver_io.dart'
    if (dart.library.js_interop) '../settings/text_saver_web.dart'
    as text_saver;

/// Screening audiogram: adaptive tone detection at 250–8000 Hz per ear with a
/// plotted threshold curve (clinical symbols: right = red O, left = blue X).
///
/// Levels are dB re: full scale on uncalibrated audio — the curve's SHAPE is
/// informative; absolute dB HL needs a calibrated audiometer. Research
/// screening only, not a hearing test.
class AudiogramPage extends StatefulWidget {
  const AudiogramPage({
    super.key,
    this.seed = 0,
    this.audioPort,
    this.onCompleted,
  });

  final int seed;
  final AudioPort? audioPort;
  final void Function(AudiogramSession session)? onCompleted;

  @override
  State<AudiogramPage> createState() => _AudiogramPageState();
}

class _AudiogramPageState extends State<AudiogramPage> {
  late final AudiogramSession _session = AudiogramSession(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  late final Random _delayRng = Random(widget.seed + 17);
  final Stopwatch _sw = Stopwatch()..start();
  final Stopwatch _latency = Stopwatch();

  bool _playing = false;
  bool _played = false;
  bool _finished = false;

  @override
  void dispose() {
    _sw.stop();
    super.dispose();
  }

  Future<void> _play() async {
    final p = _session.next();
    if (p == null || _playing) return;
    setState(() {
      _playing = true;
      _played = false;
    });
    // A seeded random onset delay so responses track the tone, not a rhythm.
    await Future<void>.delayed(
        Duration(milliseconds: 400 + _delayRng.nextInt(900)));
    if (!mounted) return;
    try {
      final samples = p.isCatch
          ? silence(1.0)
          : tone(seconds: 1.0, freqHz: p.freqHz, amp: p.amplitude);
      await _audio.playWav(encodeMonauralWav(samples, ear: p.ear));
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

  void _answer(bool heard) {
    if (!_played) return;
    _latency.stop();
    _session.submit(heard, latencyMs: _latency.elapsedMilliseconds);
    if (_session.isComplete) {
      _finish();
      return;
    }
    setState(() => _played = false);
    // Next presentation plays on demand (self-paced screening).
    unawaited(_play());
  }

  void _finish() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onCompleted?.call(_session);
  }

  String _fmtTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_finished || _session.isComplete) return _results(context);
    final freqLabel = _session.currentFreqHz >= 1000
        ? '${(_session.currentFreqHz / 1000).toStringAsFixed(0)} kHz'
        : '${_session.currentFreqHz.round()} Hz';
    return TrialScaffold(
      title: 'Screening audiogram',
      subtitle: 'Tone detection',
      instruction: _played
          ? 'Did you hear a tone?'
          : 'Press Play, listen carefully in the ${_session.currentEar} ear.',
      isPlaying: _playing,
      validationBadge: const ValidationBadge(validationStatus: 'unvalidated'),
      pills: [
        MetaPill(
          icon: Icons.hearing,
          text: 'Ear: ${_session.currentEar.toUpperCase()}',
        ),
        MetaPill(icon: Icons.graphic_eq, text: freqLabel),
        MetaPill(
          icon: Icons.tag,
          text: 'Presentation ${_session.completedTrials + 1}',
        ),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_playing && !_played) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Ear ${_session.currentEar == 'right' ? 1 : 2} of 2 · '
          '$freqLabel',
      statusRight: 'Elapsed Time ${_fmtTime(_sw.elapsed)}',
      onStop: _finish,
      onDigitKey: (d) {
        if (d == 1) _answer(true);
        if (d == 2) _answer(false);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  key: const Key('audiogram-heard'),
                  label: 'I heard a tone',
                  hint: '1',
                  icon: Icons.check,
                  color: const Color(0xff2e9e5b),
                  enabled: _played,
                  onTap: () => _answer(true),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _AnswerButton(
                  key: const Key('audiogram-nothing'),
                  label: 'I heard nothing',
                  hint: '2',
                  icon: Icons.close,
                  color: const Color(0xff64648f),
                  enabled: _played,
                  onTap: () => _answer(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final ptaR = _session.ptaFor('right');
    final ptaL = _session.ptaFor('left');
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(0);
    return Scaffold(
      appBar: AppBar(title: const Text('Screening audiogram')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Detection thresholds',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'dB re: full scale (top = quieter tones detected). '
                'Right ear = red O, left ear = blue X; ▼ = no response at '
                'the level cap.',
                style: TextStyle(color: Color(0xff8b9bb4), fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Container(
                height: 300,
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0x1affffff),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33ffffff)),
                ),
                child: CustomPaint(
                  key: const Key('audiogram-plot'),
                  painter: AudiogramPainter(session: _session),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 16),
              _thresholdTable(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _statTile('PTA right', '${fmt(ptaR)} dBFS')),
                  const SizedBox(width: 10),
                  Expanded(child: _statTile('PTA left', '${fmt(ptaL)} dBFS')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statTile(
                      'False alarms',
                      _session.catchTrials == 0
                          ? '—'
                          : '${(_session.falseAlarmRate * 100).round()}%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Uncalibrated screening on consumer audio — the SHAPE of the '
                'curve is informative; the absolute level is not dB HL. A '
                'raised threshold pattern deserves a calibrated audiogram '
                'with an audiologist. Not a diagnosis.',
                style: TextStyle(
                    color: Color(0xff8b9bb4), fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('audiogram-noah'),
                onPressed: () => _exportNoah(context),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Export NOAH-style XML (unofficial)'),
              ),
              const SizedBox(height: 10),
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

  /// Copies the NOAH-style XML to the clipboard and offers it as a download.
  /// Unofficial format; the dBFS-not-dB-HL caveat travels inside the file.
  Future<void> _exportNoah(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final xml =
        noahStyleAudiogramXml(_session, measuredAt: DateTime.now());
    await Clipboard.setData(ClipboardData(text: xml));
    String? path;
    try {
      path = await text_saver.saveTextFile(
          xml,
          'hearbloom-audiogram-'
          '${DateTime.now().toIso8601String().substring(0, 10)}.xml');
    } catch (_) {}
    messenger.showSnackBar(SnackBar(
      content: Text(path == null
          ? 'NOAH-style XML copied to clipboard (and downloaded on web).'
          : 'NOAH-style XML copied to clipboard and saved to $path'),
    ));
  }

  Widget _thresholdTable() {
    Widget cell(String s, {bool head = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            s,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color ?? (head ? const Color(0xff8b9bb4) : const Color(0xffe2e8f0)),
              fontWeight: head ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        );
    String fmt(String ear, double f) {
      if (_session.noResponseFor(ear, f)) return '>${kMaxLevelDbfs.round()}';
      final t = _session.thresholdFor(ear, f);
      return t == null ? '—' : '${t.round()}';
    }

    return Table(
      border: TableBorder.all(color: const Color(0x22ffffff)),
      children: [
        TableRow(children: [
          cell('Ear', head: true),
          for (final f in kAudiogramFrequencies)
            cell(f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}',
                head: true),
        ]),
        TableRow(children: [
          cell('Right', color: const Color(0xfff87171)),
          for (final f in kAudiogramFrequencies) cell(fmt('right', f)),
        ]),
        TableRow(children: [
          cell('Left', color: const Color(0xff60a5fa)),
          for (final f in kAudiogramFrequencies) cell(fmt('left', f)),
        ]),
      ],
    );
  }

  Widget _statTile(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x1affffff),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xff8b9bb4), fontSize: 11.5)),
          ],
        ),
      );
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? color.withValues(alpha: 0.22) : const Color(0xff293548),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: enabled ? color : const Color(0x33ffffff), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 30,
                      color:
                          enabled ? const Color(0xffe2e8f0) : Colors.white38),
                  const SizedBox(height: 8),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? const Color(0xffe2e8f0)
                              : Colors.white38)),
                  const SizedBox(height: 4),
                  Text('key $hint',
                      style: const TextStyle(
                          color: Color(0xff8b9bb4), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the audiogram grid and both ears' threshold curves with clinical
/// symbols (right = red O, left = blue X, ▼ = no response at the cap).
class AudiogramPainter extends CustomPainter {
  AudiogramPainter({required this.session});

  final AudiogramSession session;

  static const Color _grid = Color(0x33ffffff);
  static const Color _label = Color(0xff8b9bb4);
  static const Color _right = Color(0xfff87171);
  static const Color _left = Color(0xff60a5fa);

  static const double _top = kMinLevelDbfs; // quietest at the top
  static const double _bottom = kMaxLevelDbfs;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0, bottomPad = 24.0, topPad = 6.0, rightPad = 6.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    double xOf(int i) =>
        leftPad + plotW * i / (kAudiogramFrequencies.length - 1);
    double yOf(double dbfs) =>
        topPad + plotH * (dbfs - _top) / (_bottom - _top);

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    const textStyle = TextStyle(color: _label, fontSize: 10);

    // Horizontal 10 dB gridlines + labels.
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
    // Vertical frequency gridlines + labels.
    for (var i = 0; i < kAudiogramFrequencies.length; i++) {
      final x = xOf(i);
      canvas.drawLine(Offset(x, topPad), Offset(x, topPad + plotH), gridPaint);
      final f = kAudiogramFrequencies[i];
      final tp = TextPainter(
        text: TextSpan(
            text: f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}',
            style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topPad + plotH + 6));
    }

    for (final earSpec in const [('right', _right), ('left', _left)]) {
      final (ear, color) = earSpec;
      final line = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final points = <Offset?>[];
      for (var i = 0; i < kAudiogramFrequencies.length; i++) {
        final f = kAudiogramFrequencies[i];
        final t = session.thresholdFor(ear, f);
        if (t != null) {
          points.add(Offset(xOf(i), yOf(t)));
        } else if (session.noResponseFor(ear, f)) {
          points.add(null); // no-response markers are drawn, not connected
        } else {
          points.add(null);
        }
      }
      // Connect consecutive measured points.
      Offset? prev;
      for (final p in points) {
        if (p != null && prev != null) canvas.drawLine(prev, p, line);
        prev = p;
      }
      // Symbols.
      for (var i = 0; i < kAudiogramFrequencies.length; i++) {
        final f = kAudiogramFrequencies[i];
        final t = session.thresholdFor(ear, f);
        if (t != null) {
          final c = Offset(xOf(i), yOf(t));
          if (ear == 'right') {
            canvas.drawCircle(c, 6, line);
          } else {
            const r = 5.0;
            canvas.drawLine(
                c + const Offset(-r, -r), c + const Offset(r, r), line);
            canvas.drawLine(
                c + const Offset(-r, r), c + const Offset(r, -r), line);
          }
        } else if (session.noResponseFor(ear, f)) {
          // ▼ at the bottom edge: tested, no response at the cap.
          final c = Offset(xOf(i), yOf(_bottom) - 5);
          final path = Path()
            ..moveTo(c.dx - 6, c.dy - 5)
            ..lineTo(c.dx + 6, c.dy - 5)
            ..lineTo(c.dx, c.dy + 5)
            ..close();
          canvas.drawPath(path, Paint()..color = color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(AudiogramPainter oldDelegate) =>
      oldDelegate.session != session;
}
