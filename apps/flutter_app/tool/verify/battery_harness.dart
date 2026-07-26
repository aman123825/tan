// Headless verification for composite battery aggregation.
//
//   dart run tool/verify/battery_harness.dart
import 'dart:io';

import '../../lib/core/battery.dart';

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
  check('empty battery scores 0', batteryOverall(const []) == 0);
  check('single stage passes through',
      batteryOverall(const [BatteryStageResult('a', 0.75)]) == 0.75);
  check(
      'mean of stages',
      (batteryOverall(const [
                    BatteryStageResult('a', 1.0),
                    BatteryStageResult('b', 0.5),
                    BatteryStageResult('c', 0.0),
                  ]) -
                  0.5)
              .abs() <
          1e-9);
  check(
      'result carries label + accuracy',
      const BatteryStageResult('gap', 0.9).label == 'gap' &&
          const BatteryStageResult('gap', 0.9).accuracy == 0.9);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks battery checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks battery checks');
    exit(1);
  }
}
