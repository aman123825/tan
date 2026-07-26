// Headless verification for the generic interval-discrimination task.
//
//   dart run tool/verify/interval_harness.dart
import 'dart:io';
import 'dart:math';

import '../../lib/core/audio/task_stimuli.dart';
import '../../lib/core/interval_task.dart';
import '../../lib/core/protocol_engine.dart';

int _checks = 0;
int _failures = 0;

void check(String name, bool condition) {
  _checks++;
  if (condition) {
    stdout.writeln('  ok   $name');
  } else {
    _failures++;
    stdout.writeln('  FAIL $name');
  }
}

double rmsWindow(List<double> x, int start, int len) {
  var acc = 0.0;
  final end = min(start + len, x.length);
  for (var i = start; i < end; i++) {
    acc += x[i] * x[i];
  }
  final n = end - start;
  return n <= 0 ? 0 : sqrt(acc / n);
}

double peak(List<double> x) {
  var mx = 0.0;
  for (final v in x) {
    if (v.abs() > mx) mx = v.abs();
  }
  return mx;
}

const int sr = 48000;

void main() {
  // ampFromDb.
  check('ampFromDb(+6) louder', ampFromDb(0.2, 6) > 0.2);
  check('ampFromDb(-6) softer', ampFromDb(0.2, -6) < 0.2);
  check('ampFromDb(0) unchanged', (ampFromDb(0.2, 0) - 0.2).abs() < 1e-9);

  // Generic session.
  final session = IntervalTaskSession(
    moduleId: 'auditory',
    groupId: 'amplitude',
    paramName: 'delta_db',
    track: AdaptiveTrack(value: 6, min: 0.5, max: 15, step: 1),
    extraParameters: const <String, Object?>{'carrier': 'tone_1000hz'},
    maxTrials: 6,
  );
  final gen = ThreeIntervalGenerator(seed: 5, intervals: 3);
  final t1 = gen.next();
  check('target in range', t1.targetInterval >= 0 && t1.targetInterval < 3);
  final wasCorrect = session.submit(t1, t1.targetInterval, latencyMs: 800);
  check('correct choice scores', wasCorrect);
  final t2 = gen.next();
  session.submit(t2, (t2.targetInterval + 1) % 3, latencyMs: 800);
  check('accuracy = 1/2', (session.accuracy - 0.5).abs() < 1e-9);
  check('records adapted param',
      session.records.first.parameters['delta_db'] == 6);
  check('records extra param',
      session.records.first.parameters['carrier'] == 'tone_1000hz');
  check(
      'no volume key',
      !session.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));
  check('threshold null before reversals', session.threshold == null);

  // Level discrimination: target interval is louder.
  final level = levelDiscriminationStimulus(
    targetInterval: 1,
    deltaDb: 12,
    intervals: 3,
  );
  const toneLen = 19200; // 0.4 s
  const step = 28800; // tone + 0.2 s gap
  check('level: length correct', level.length == 3 * toneLen + 2 * 9600);
  check('level: no clipping', peak(level) <= 0.95 + 1e-9);
  check('level: target louder than reference',
      rmsWindow(level, 1 * step, toneLen) > rmsWindow(level, 0, toneLen) * 1.5);
  final levelB =
      levelDiscriminationStimulus(targetInterval: 1, deltaDb: 12, intervals: 3);
  check('level: deterministic',
      level.length == levelB.length && level[100] == levelB[100]);

  // Detection (quiet): only the target interval carries a tone.
  final det = detectionStimulus(
    targetInterval: 2,
    toneLevelDb: 0,
    intervals: 3,
  );
  const dTone = 14400; // 0.3 s
  const dStep = 26400; // tone + 0.25 s gap
  check(
      'detection: target has energy', rmsWindow(det, 2 * dStep, dTone) > 0.05);
  check('detection: non-target is silent', rmsWindow(det, 0, dTone) < 1e-6);
  check('detection: no clipping', peak(det) <= 0.95 + 1e-9);

  // Forward masking variant builds and is safe.
  final fm = detectionStimulus(
    targetInterval: 0,
    toneLevelDb: -6,
    maskerAmp: 0.3,
    forwardGapMs: 30,
  );
  check('forward masking: builds', fm.isNotEmpty);
  check('forward masking: no clipping', peak(fm) <= 0.95 + 1e-9);

  // Rhythm: larger deviation lengthens the buffer.
  final r20 = rhythmStimulus(targetInterval: 0, deltaMs: 20);
  final r120 = rhythmStimulus(targetInterval: 0, deltaMs: 120);
  check('rhythm: larger delta is longer', r120.length > r20.length);
  check('rhythm: no clipping', peak(r120) <= 0.95 + 1e-9);
  final r20b = rhythmStimulus(targetInterval: 0, deltaMs: 20);
  check('rhythm: deterministic',
      r20.length == r20b.length && r20[50] == r20b[50]);

  // Note sequence synthesis.
  final mel = noteSequenceStimulus(<String>['C', 'E', 'G']);
  const noteLen = 16800; // 0.35 s
  const noteGap = 5760; // 0.12 s
  check('note seq: length', mel.length == 3 * noteLen + 2 * noteGap);
  check('note seq: no clipping', peak(mel) <= 0.95 + 1e-9);
  check('note seq: unknown note falls back',
      noteSequenceStimulus(<String>['?']).isNotEmpty);
  final melB = noteSequenceStimulus(<String>['C', 'E', 'G']);
  check('note seq: deterministic',
      mel.length == melB.length && mel[10] == melB[10]);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks interval checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks interval checks');
    exit(1);
  }
}
