import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/training/spatial.dart';
import '../catalog/validation_badge.dart';
import '../common/trial_scaffold.dart';

// Dark glassmorphic palette.
const Color _ink = Color(0xffe2e8f0);
const Color _muted = Color(0xff94a3b8);
const Color _border = Color(0x33ffffff);
const Color _primary = Color(0xff3b82f6);
const Color _good = Color(0xff22c55e);
const Color _bad = Color(0xffef4444);

/// Spatial-hearing / sound-localization training.
///
/// A broadband noise burst is placed at a simulated azimuth (ITD + ILD, stereo)
/// and the listener taps the matching position on a semicircular display. The
/// active positions widen/narrow with performance (start at ±90°, add ±60°,
/// ±30° and 0° as the listener improves). Wired headphones are required.
/// Illustrative demonstration on uncalibrated audio — adapts difficulty, never
/// master volume.
class SpatialPage extends StatefulWidget {
  const SpatialPage({
    super.key,
    this.moduleId = 'auditory',
    this.groupId = 'spatial',
    required this.comfortableLevel,
    this.maxTrials = 20,
    this.seed = 0,
    this.validationStatus = 'demo_only',
    this.audioPort,
    this.onCompleted,
  });

  final String moduleId;
  final String groupId;
  final double comfortableLevel;
  final int maxTrials;
  final int seed;
  final String validationStatus;
  final AudioPort? audioPort;
  final void Function(SpatialSession session)? onCompleted;

  @override
  State<SpatialPage> createState() => _SpatialPageState();
}

class _SpatialPageState extends State<SpatialPage> {
  late final SpatialSession _session = SpatialSession(
    moduleId: widget.moduleId,
    groupId: widget.groupId,
    maxTrials: widget.maxTrials,
  );
  late final SpatialGenerator _generator = SpatialGenerator(seed: widget.seed);
  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();

  SpatialTrial? _current;
  DateTime? _shownAt;
  int _replays = 0;
  bool _played = false;
  int? _chosenAngle;
  bool? _lastCorrect;
  bool _finished = false;

  static const int _maxReplays = 5;
  final Stopwatch _sessionSw = Stopwatch()..start();

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
    setState(() {
      _current = _generator.next(_session.currentLevel);
      _shownAt = DateTime.now();
      _replays = 0;
      _played = false;
      _chosenAngle = null;
      _lastCorrect = null;
    });
  }

  /// A short broadband noise burst with raised-cosine fades, placed at [angle].
  Uint8List _buildStimulus(int angle) {
    const seconds = 0.6;
    final mono = whiteNoise(seconds: seconds, amp: 0.28, seed: 7);
    // Gentle fades to avoid clicks.
    final fade = (0.02 * kSampleRate).round();
    for (var i = 0; i < mono.length; i++) {
      if (i < fade) {
        mono[i] *= i / fade;
      } else if (i >= mono.length - fade) {
        mono[i] *= (mono.length - 1 - i) / fade;
      }
    }
    final stereo = spatialize(mono, angle.toDouble());
    return encodeWavStereo16(stereo.left, stereo.right);
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
      await _audio.playWav(_buildStimulus(trial.angleDeg));
    } catch (_) {
      // Playback failure must not block the exercise.
    }
  }

  void _choose(int angle) {
    final trial = _current;
    if (trial == null || _chosenAngle != null || !_played) return;
    final latency = _shownAt == null
        ? 0
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    final correct =
        _session.submit(trial, angle, latencyMs: latency, replays: _replays);
    setState(() {
      _chosenAngle = angle;
      _lastCorrect = correct;
    });
  }

  void _advance() {
    if (_session.isComplete) {
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
        appBar: AppBar(title: const Text('Sound localization')),
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
    final answered = _chosenAngle != null;
    return TrialScaffold(
      title: 'Sound localization',
      subtitle: 'Spatial hearing',
      instruction: 'Where did the sound come from? Tap the position.',
      instructionIcon: Icons.spatial_audio_off,
      enableShortcuts: false,
      validationBadge:
          ValidationBadge(validationStatus: widget.validationStatus),
      pills: [
        const MetaPill(icon: Icons.lock, text: 'Volume locked'),
        MetaPill(
            icon: Icons.headphones, text: '${_session.activePositions} positions'),
        MetaPill(icon: Icons.trending_up, text: 'Level ${_session.currentLevel + 1}'),
      ],
      transport: [
        TransportAction(
          icon: Icons.play_arrow,
          label: 'Play',
          color: TransportColors.play,
          onTap: (!_played && !answered) ? _play : null,
        ),
        TransportAction(
          icon: Icons.replay,
          label: 'Replay ($_replays/$_maxReplays)',
          color: TransportColors.replay,
          onTap:
              (_played && !answered && _replays < _maxReplays) ? _play : null,
        ),
        TransportAction(
          icon: Icons.stop,
          label: 'Stop',
          color: TransportColors.stop,
          onTap: _finish,
        ),
      ],
      statusLeft: 'Question ${_session.trialNumber} of ${widget.maxTrials}',
      statusRight: 'Elapsed Time ${_fmt(_sessionSw.elapsed)}',
      onStop: _finish,
      footer: answered ? _footer(trial) : null,
      child: _displayArea(trial, answered),
    );
  }

  Widget _displayArea(SpatialTrial trial, bool answered) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SemicircleLocalizationDisplay(
                angles: kSpatialAngles,
                enabled: _played && !answered,
                presentedAngle: answered ? trial.angleDeg : null,
                chosenAngle: _chosenAngle,
                onSelect: _choose,
              ),
              const SizedBox(height: 8),
              Text(
                _played
                    ? 'Tap the dot where you heard the sound.'
                    : 'Play the sound to reveal the positions.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(SpatialTrial trial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_session.showsFeedback)
          _FeedbackLine(
            correct: _lastCorrect!,
            answerLabel: _angleLabel(trial.angleDeg),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _advance,
          child: Text(_session.isComplete ? 'See results' : 'Next'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Session summary',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _SummaryRow(
            label: 'Trials completed', value: '${_session.completedTrials}'),
        _SummaryRow(label: 'Correct', value: '${_session.percent}%'),
        _SummaryRow(
          label: 'Mean angular error',
          value: '${_session.meanAngularError.toStringAsFixed(0)}°',
        ),
        _SummaryRow(
          label: 'Hardest level reached',
          value: 'Level ${_session.maxLevelReached + 1}'
              ' (${kSpatialLevels[_session.maxLevelReached].length} positions)',
        ),
        const SizedBox(height: 14),
        Text(
            'Training exercise — not a diagnosis. Simulated ITD/ILD spatial '
            'audio on uncalibrated devices; wired headphones required for the '
            'binaural cues to separate.',
            style: theme.textTheme.bodySmall?.copyWith(color: _muted)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_session),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Formats an azimuth for display / semantics ("30° right", "straight ahead").
String _angleLabel(int deg) {
  if (deg == 0) return 'straight ahead (0°)';
  final side = deg < 0 ? 'left' : 'right';
  return '${deg.abs()}° $side';
}

/// A semicircular localization display: seven position dots on a half-circle
/// arc with a head icon at the centre. Dots are tappable when [enabled]; after
/// answering, the [presentedAngle] is marked correct (green) and a wrong
/// [chosenAngle] is marked in red.
class SemicircleLocalizationDisplay extends StatelessWidget {
  const SemicircleLocalizationDisplay({
    super.key,
    required this.angles,
    required this.enabled,
    required this.onSelect,
    this.presentedAngle,
    this.chosenAngle,
  });

  final List<int> angles;
  final bool enabled;
  final void Function(int angle) onSelect;
  final int? presentedAngle;
  final int? chosenAngle;

  static const double _dotRadius = 24;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 440.0;
        final height = width / 2 + _dotRadius + 12;
        final cx = width / 2;
        final cy = height - _dotRadius - 6; // arc centre near the bottom
        final r = width / 2 - _dotRadius - 6;

        final dots = <Widget>[];
        for (final angle in angles) {
          final t = angle * math.pi / 180.0;
          final x = cx + r * math.sin(t);
          final y = cy - r * math.cos(t);
          dots.add(Positioned(
            left: x - _dotRadius,
            top: y - _dotRadius,
            child: _PositionDot(
              angle: angle,
              radius: _dotRadius,
              enabled: enabled,
              state: _stateFor(angle),
              onTap: () => onSelect(angle),
            ),
          ));
        }

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Top-down room: walls, listening arc, spokes, the listener's
              // head (nose = facing direction) and — after answering — a
              // green feedback arrow toward the true source (plus a red one
              // toward a wrong choice).
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoomPainter(
                    angles: angles,
                    center: Offset(cx, cy),
                    radius: r,
                    presentedAngle: presentedAngle,
                    chosenAngle: chosenAngle,
                  ),
                ),
              ),
              ...dots,
            ],
          ),
        );
      },
    );
  }

  _DotState _stateFor(int angle) {
    if (presentedAngle == null) return _DotState.idle;
    if (angle == presentedAngle) return _DotState.correct;
    if (angle == chosenAngle) return _DotState.wrong;
    return _DotState.idle;
  }
}

enum _DotState { idle, correct, wrong }

class _PositionDot extends StatelessWidget {
  const _PositionDot({
    required this.angle,
    required this.radius,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final int angle;
  final double radius;
  final bool enabled;
  final _DotState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xff293548);
    Color border = _border;
    if (state == _DotState.correct) {
      bg = const Color(0x3322c55e);
      border = _good;
    } else if (state == _DotState.wrong) {
      bg = const Color(0x33ef4444);
      border = _bad;
    } else if (enabled) {
      border = _primary.withValues(alpha: 0.7);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: _angleLabel(angle),
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: border, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: Center(
              child: Text(
                angle == 0 ? '0°' : '${angle > 0 ? '+' : ''}$angle',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: enabled || state != _DotState.idle
                      ? _ink
                      : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-down room backdrop for the localization display: walls, the listening
/// arc with radial spokes, a listener's head facing the speakers (nose wedge
/// + ears), and post-answer feedback arrows (green = true source direction,
/// red = a wrong chosen direction).
class _RoomPainter extends CustomPainter {
  _RoomPainter({
    required this.angles,
    required this.center,
    required this.radius,
    this.presentedAngle,
    this.chosenAngle,
  });

  final List<int> angles;
  final Offset center;
  final double radius;
  final int? presentedAngle;
  final int? chosenAngle;

  Offset _onArc(double angleDeg, double r) {
    final t = angleDeg * math.pi / 180.0;
    return Offset(center.dx + r * math.sin(t), center.dy - r * math.cos(t));
  }

  void _arrow(Canvas canvas, double angleDeg, Color color,
      {double strokeWidth = 4}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final from = _onArc(angleDeg, 26); // just outside the head
    final to = _onArc(angleDeg, radius * 0.72);
    canvas.drawLine(from, to, paint);
    // Arrowhead.
    final dir = (to - from);
    final len = dir.distance;
    if (len <= 0) return;
    final u = Offset(dir.dx / len, dir.dy / len);
    final perp = Offset(-u.dy, u.dx);
    const headLen = 12.0, headWidth = 8.0;
    final tip = _onArc(angleDeg, radius * 0.72 + headLen);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(to.dx + perp.dx * headWidth, to.dy + perp.dy * headWidth)
      ..lineTo(to.dx - perp.dx * headWidth, to.dy - perp.dy * headWidth)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Room walls: a soft rounded rectangle around the scene.
    final wall = Paint()
      ..color = const Color(0x1a94a3b8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(18),
      ),
      wall,
    );

    final arcPaint = Paint()
      ..color = _border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Semicircle from left (180°) to right (0°) over the top.
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, math.pi, math.pi, false, arcPaint);

    // Radial spokes from the head to each position.
    final spoke = Paint()
      ..color = const Color(0x22ffffff)
      ..strokeWidth = 1;
    for (final angle in angles) {
      canvas.drawLine(center, _onArc(angle.toDouble(), radius), spoke);
    }

    // Feedback arrows (under the head so the head stays readable).
    if (presentedAngle != null) {
      if (chosenAngle != null && chosenAngle != presentedAngle) {
        _arrow(canvas, chosenAngle!.toDouble(), _bad.withValues(alpha: 0.75),
            strokeWidth: 3);
      }
      _arrow(canvas, presentedAngle!.toDouble(), _good);
    }

    // The listener's head, facing the arc: skull, ears, nose wedge.
    final headFill = Paint()..color = const Color(0x333b82f6);
    final headStroke = Paint()
      ..color = _primary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const headR = 16.0;
    // Ears (left/right of the head, matching the interaural axis).
    final ear = Paint()..color = _primary.withValues(alpha: 0.7);
    canvas.drawCircle(center + const Offset(-headR, 0), 4, ear);
    canvas.drawCircle(center + const Offset(headR, 0), 4, ear);
    canvas.drawCircle(center, headR, headFill);
    canvas.drawCircle(center, headR, headStroke);
    // Nose: a small wedge pointing "up" toward 0° (the facing direction).
    final nose = Path()
      ..moveTo(center.dx - 5, center.dy - headR + 2)
      ..lineTo(center.dx + 5, center.dy - headR + 2)
      ..lineTo(center.dx, center.dy - headR - 7)
      ..close();
    canvas.drawPath(nose, Paint()..color = _primary.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _RoomPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.center != center ||
      oldDelegate.presentedAngle != presentedAngle ||
      oldDelegate.chosenAngle != chosenAngle;
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.correct, required this.answerLabel});

  final bool correct;
  final String answerLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(correct ? Icons.check_circle : Icons.cancel,
                color: correct ? _good : _bad),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Not quite'),
          ],
        ),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('It came from $answerLabel',
              style: const TextStyle(color: _muted)),
        ],
      ],
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
          Text(label, style: const TextStyle(color: _muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
