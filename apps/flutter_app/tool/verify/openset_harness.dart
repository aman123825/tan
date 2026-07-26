// Headless verification harness for typed open-set recognition.
//
//   dart run tool/verify/openset_harness.dart
import 'dart:io';

import '../../lib/core/open_set.dart';

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
  // Normalization.
  check('lowercases + trims', normalizeResponse('  Bell ') == 'bell');
  check('strips punctuation', normalizeResponse('Bell!') == 'bell');
  check('collapses whitespace',
      normalizeResponse('the   red  pen') == 'the red pen');

  // Whole-word scoring.
  check('exact match scores 1',
      scoreResponse('bell', 'BELL', OpenSetScoreMode.wholeWord) == 1.0);
  check('mismatch scores 0',
      scoreResponse('bell', 'ball', OpenSetScoreMode.wholeWord) == 0.0);
  check('punctuation-insensitive match',
      scoreResponse('bell', ' bell. ', OpenSetScoreMode.wholeWord) == 1.0);

  // Word-accuracy scoring (phrases).
  check(
      'all words -> 1.0',
      scoreResponse('red pen', 'red pen', OpenSetScoreMode.wordAccuracy) ==
          1.0);
  check(
      'half words -> 0.5',
      (scoreResponse('red pen', 'red cup', OpenSetScoreMode.wordAccuracy) - 0.5)
              .abs() <
          1e-9);
  check(
      'order-independent',
      scoreResponse('red pen', 'pen red', OpenSetScoreMode.wordAccuracy) ==
          1.0);

  // Generator determinism.
  final g1 = OpenSetGenerator(const ['bell', 'ball', 'cup'], seed: 3).next();
  final g2 = OpenSetGenerator(const ['bell', 'ball', 'cup'], seed: 3).next();
  check('generator deterministic', g1 == g2);

  // Session.
  final s = OpenSetSession(maxTrials: 5);
  check('correct typed answer', s.submit('bell', 'Bell', latencyMs: 900));
  check('wrong typed answer', !s.submit('ball', 'bell', latencyMs: 900));
  check('accuracy = 1/2', (s.accuracy - 0.5).abs() < 1e-9);
  check('records score param', s.records.first.parameters['score'] == 1.0);
  check('quiet run has no snr_db',
      !s.records.first.parameters.containsKey('snr_db'));
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Noise variant records snr_db.
  final n = OpenSetSession(snrDb: 10, maxTrials: 5);
  n.submit('bell', 'bell', latencyMs: 500);
  check('noise run records snr_db', n.records.first.parameters['snr_db'] == 10);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks openset checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks openset checks');
    exit(1);
  }
}
