// Headless verification harness for sequence-entry (digit-span) logic.
//
//   dart run tool/verify/sequence_harness.dart
import 'dart:io';

import '../../lib/core/sequence_entry.dart';

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
  // Generator: deterministic, correct length, within alphabet.
  final g1 = SequenceEntryGenerator(seed: 11);
  final g2 = SequenceEntryGenerator(seed: 11);
  final s1 = g1.next(5);
  final s2 = g2.next(5);
  check('generator deterministic', s1.join() == s2.join());
  check('generator length', s1.length == 5);
  check('digits within alphabet', s1.every((d) => '0123456789'.contains(d)));

  // Span ladder: 2 correct step up, wrong steps down, bounds respected.
  final ladder = SpanLadder(lengths: const [3, 5, 7]);
  check('starts at 3', ladder.currentLength == 3);
  ladder.submit(true);
  check('no step after 1 correct', ladder.currentLength == 3);
  ladder.submit(true);
  check('step up after 2 correct', ladder.currentLength == 5);
  ladder.submit(true);
  ladder.submit(true);
  check('step up to 7', ladder.currentLength == 7);
  ladder.submit(true);
  ladder.submit(true);
  check('clamped at top (7)', ladder.currentLength == 7);
  check('maxCorrectLength tracked', ladder.maxCorrectLength == 7);
  ladder.submit(false);
  check('step down after wrong', ladder.currentLength == 5);
  check('reversal counted', ladder.reversals >= 1);

  // Session: exact-match scoring, records length, no volume, span.
  final session = SequenceEntrySession(maxTrials: 10);
  check('session starts at length 3', session.currentLength == 3);
  final ok = session.submit(['3', '1', '4'], ['3', '1', '4'], latencyMs: 900);
  check('exact match is correct', ok);
  final wrongOrder =
      session.submit(['1', '2', '3'], ['3', '2', '1'], latencyMs: 900);
  check('wrong order is incorrect', !wrongOrder);
  final wrongLen = session.submit(['1', '2'], ['1', '2', '3'], latencyMs: 900);
  check('length mismatch is incorrect', !wrongLen);
  check(
      'records length param', session.records.first.parameters['length'] == 3);
  check('accuracy = 1/3', (session.accuracy - 1 / 3).abs() < 1e-9);
  check('maxSpan reflects a correct length-3 recall', session.maxSpan == 3);
  check(
      'trial json has no volume key',
      !session.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks sequence checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks sequence checks');
    exit(1);
  }
}
