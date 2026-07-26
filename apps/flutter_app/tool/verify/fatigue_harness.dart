// Headless verification for the fatigue scale.
//
//   dart run tool/verify/fatigue_harness.dart
import 'dart:io';

import '../../lib/core/fatigue.dart';

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
  check('range is 0..10', FatigueScale.min == 0 && FatigueScale.max == 10);
  check('valid within range',
      FatigueScale.isValid(0) && FatigueScale.isValid(10));
  check('invalid below', !FatigueScale.isValid(-1));
  check('invalid above', !FatigueScale.isValid(11));
  check('clamp low', FatigueScale.clamp(-5) == 0);
  check('clamp high', FatigueScale.clamp(99) == 10);
  check('clamp identity', FatigueScale.clamp(7) == 7);
  check('bucket none', FatigueScale.bucket(0) == 'None');
  check('bucket mild', FatigueScale.bucket(2) == 'Mild');
  check('bucket moderate', FatigueScale.bucket(5) == 'Moderate');
  check('bucket high', FatigueScale.bucket(8) == 'High');
  check('bucket severe', FatigueScale.bucket(10) == 'Severe');
  check('bucket clamps out-of-range', FatigueScale.bucket(50) == 'Severe');

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks fatigue checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks fatigue checks');
    exit(1);
  }
}
