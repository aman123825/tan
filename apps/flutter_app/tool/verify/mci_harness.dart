// Headless verification harness for Melodic Contour Identification.
//
//   dart run tool/verify/mci_harness.dart
import 'dart:io';

import '../../lib/core/mci.dart';

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

void main() {
  check('nine contour patterns', kContourPatterns.length == 9);
  check('patterns are unique', kContourPatterns.toSet().length == 9);
  check('every pattern has a label',
      kContourPatterns.every((p) => contourLabel(p) != p));
  check('every pattern has a glyph',
      kContourPatterns.every((p) => contourGlyph(p) != '?'));

  // Every contour has a shipped audio asset (real audio, not synthesized here).
  var allAssets = true;
  for (final p in kContourPatterns) {
    final uri = Platform.script.resolve('../../assets/stimuli/mci_$p.wav');
    if (!File.fromUri(uri).existsSync()) allAssets = false;
  }
  check('all 9 contour WAV assets exist', allAssets);

  // Generator: deterministic, in range.
  final t1 = MciGenerator(seed: 4).next();
  final t2 = MciGenerator(seed: 4).next();
  check('generator deterministic', t1.targetIndex == t2.targetIndex);
  check('target in 0..8', t1.targetIndex >= 0 && t1.targetIndex < 9);
  check('assetFor path format',
      t1.assetFor(0) == 'assets/stimuli/mci_${kContourPatterns[0]}.wav');

  // Session scoring.
  final session = MciSession(maxTrials: 5);
  final trial = MciTrial(targetIndex: 2); // 'flat'
  check('correct choice scores correct',
      session.submit(trial, 2, latencyMs: 800));
  check('wrong choice scores incorrect',
      !session.submit(trial, 0, latencyMs: 800));
  check(
      'records pattern', session.records.first.parameters['pattern'] == 'flat');
  check('records 9 choices', session.records.first.parameters['choices'] == 9);
  check('accuracy = 1/2', (session.accuracy - 0.5).abs() < 1e-9);
  check(
      'trial json has no volume key',
      !session.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks mci checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks mci checks');
    exit(1);
  }
}
