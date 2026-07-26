import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/desensitization.dart';
import '../../core/tinnitus/therapy_sounds.dart' show pinkNoise;
import '../../data/session_history.dart';
import '../catalog/validation_badge.dart';

/// Hyperacusis sound-desensitization program (D7): 14 daily 10-minute pink
/// noise sessions on a graded level ladder that stays ≥10 dB below the
/// measured LDL and under the app's amplitude cap. Education/self-practice
/// framing — a clinical program belongs with an audiologist.
class DesensitizationPage extends StatefulWidget {
  const DesensitizationPage({
    super.key,
    this.sessionSeconds = kDesensitizationMinutes * 60,
    this.audioPort,
  });

  /// Listening time per step (overridable for tests).
  final int sessionSeconds;
  final AudioPort? audioPort;

  @override
  State<DesensitizationPage> createState() => _DesensitizationPageState();
}

class _DesensitizationPageState extends State<DesensitizationPage> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _soft = Color(0xff8b9bb4);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);
  static const String _stepsKey = 'hearbloom.desensitization.v1.steps';
  static const String _dayKey = 'hearbloom.desensitization.v1.last_day';

  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  DesensitizationProgram? _program;
  String? _lastCompletedDay;
  bool _running = false;
  int _remaining = 0;
  Timer? _tick;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _stopRequested = true;
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Latest stored LDL result (relative dB), when the screen has been run.
    double? ldl;
    for (final r in await SessionHistory().load()) {
      if (r.groupId.contains('ldl') && r.metricValue != null) {
        ldl = r.metricValue;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _program = DesensitizationProgram(
        ldlDb: ldl,
        completedSteps: prefs.getInt(_stepsKey) ?? 0,
      );
      _lastCompletedDay = prefs.getString(_dayKey);
    });
  }

  bool get _doneToday =>
      !canCompleteStepToday(_lastCompletedDay, DateTime.now());

  Future<void> _start() async {
    final program = _program!;
    setState(() {
      _running = true;
      _stopRequested = false;
      _remaining = widget.sessionSeconds;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _completeStep();
      }
    });
    // Loop a 20 s pink-noise buffer until the timer ends or Stop is tapped.
    // SAFETY: the level is fixed for the whole session (never rises mid-run).
    final buffer = encodeWav16(
        pinkNoise(seconds: 20, amp: program.currentAmplitude, seed: 11));
    while (mounted && _running && !_stopRequested && _remaining > 0) {
      final sw = Stopwatch()..start();
      try {
        await _audio.playWav(buffer);
      } catch (_) {
        break;
      }
      // A port that returns immediately (silent/headless) must not spin a
      // tight microtask loop — yield through a real timer instead.
      if (sw.elapsedMilliseconds < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  void _stopEarly() {
    _tick?.cancel();
    _stopRequested = true;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stopped — no problem. Stopping early never counts '
            'against you; try again when it feels comfortable.')));
  }

  Future<void> _completeStep() async {
    _stopRequested = true;
    final program = _program!;
    program.completeStep();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stepsKey, program.completedSteps);
    await prefs.setString(_dayKey, desensitizationDayKey(DateTime.now()));
    if (!mounted) return;
    setState(() {
      _running = false;
      _lastCompletedDay = desensitizationDayKey(DateTime.now());
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(program.isFinished
            ? 'Program complete — well done!'
            : 'Step ${program.completedSteps} of $kDesensitizationSteps '
                'done. Next session unlocks tomorrow.')));
  }

  String _fmt(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final program = _program;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound comfort program'),
        actions: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: ValidationBadge(validationStatus: 'unvalidated'),
          ),
        ],
      ),
      body: program == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'A gentle daily listening routine for sound '
                        'sensitivity: quiet pink noise, a little longer '
                        'each day at a slightly higher (still comfortable) '
                        'level. The level always stays well below your '
                        'measured discomfort level and under the app\'s '
                        'safety cap.',
                        style: TextStyle(
                            color: _muted, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 16),
                      _progressCard(program),
                      const SizedBox(height: 16),
                      if (program.isFinished)
                        _card(const Text(
                          'Program complete! You can restart it from the '
                          'beginning by clearing app data, or simply keep '
                          'using the sound-therapy player.',
                          style: TextStyle(color: _ink, height: 1.4),
                        ))
                      else if (_running)
                        _card(Column(
                          children: [
                            Text(_fmt(_remaining),
                                style: const TextStyle(
                                    color: _ink,
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            const Text('Keep the noise soft and easy — '
                                'read, relax, or potter about.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _muted)),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              key: const Key('desens-stop'),
                              onPressed: _stopEarly,
                              icon: const Icon(Icons.stop),
                              label: const Text(
                                  'Stop (never counts against you)'),
                            ),
                          ],
                        ))
                      else
                        _card(Column(
                          children: [
                            Text(
                              _doneToday
                                  ? 'Today\'s session is done — the next '
                                      'step unlocks tomorrow.'
                                  : 'Today: step '
                                      '${program.completedSteps + 1} of '
                                      '$kDesensitizationSteps · '
                                      '${widget.sessionSeconds ~/ 60} min '
                                      'of soft pink noise',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const Key('desens-start'),
                              onPressed: _doneToday ? null : _start,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start today\'s session'),
                            ),
                          ],
                        )),
                      const SizedBox(height: 14),
                      Text(
                        program.ldlDb == null
                            ? 'Tip: run the "Loudness discomfort (LDL)" '
                                'screen first so the ladder is anchored to '
                                'YOUR comfort — until then a conservative '
                                'default ceiling is used.'
                            : 'Ladder ceiling: 10 dB below your measured '
                                'discomfort level.',
                        style: const TextStyle(
                            color: _soft, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Education and self-practice only — not a treatment '
                        'plan. Worsening discomfort, pain or new symptoms '
                        'belong with an audiologist or doctor.',
                        style: TextStyle(
                            color: _soft, fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _progressCard(DesensitizationProgram program) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Progress',
                style: TextStyle(
                    color: _ink, fontWeight: FontWeight.w800)),
            Text('${program.completedSteps} / $kDesensitizationSteps days',
                style: const TextStyle(
                    color: _muted, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: program.completedSteps / kDesensitizationSteps,
            minHeight: 10,
            backgroundColor: const Color(0x33ffffff),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Today\'s level: ${program.currentLevelDb.toStringAsFixed(0)} dB '
          '(relative, capped) · ceiling '
          '${program.ceilingDb.toStringAsFixed(0)} dB',
          style: const TextStyle(color: _muted, fontSize: 12.5),
        ),
      ],
    ));
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: child,
      );
}
