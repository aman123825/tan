// Headless verification harness for the comfortable-level safety controller.
//
//   dart run tool/verify/safety_harness.dart
//
// Asserts the ANSD volume-safety invariants and exits non-zero on any failure.
import 'dart:io';

import '../../lib/core/safety.dart';

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

bool _throwsDenied(void Function() body) {
  try {
    body();
    return false;
  } on VolumeChangeDenied {
    return true;
  }
}

void main() {
  // auto_volume is always false.
  final c = ComfortableLevelController(initialLevel: 0.3);
  check('auto_volume is always false', c.autoVolume == false);
  check(
    'safetyState reports auto_volume false',
    c.safetyState()['auto_volume'] == false,
  );
  check(
    'safetyState reports absolute_thresholds false',
    c.safetyState()['absolute_thresholds'] == false,
  );

  // User calibration changes level while unlocked.
  check('user calibration sets level', c.setLevel(0.5) == 0.5);
  check('level reads back', c.level == 0.5);

  // Clamping to [min,max].
  check('clamp above max', c.setLevel(9.0) == 1.0);
  check('clamp below min', c.setLevel(-9.0) == 0.0);

  // Automatic source is always denied, even while unlocked.
  check(
    'automatic source denied',
    _throwsDenied(() => c.setLevel(0.9, source: VolumeChangeSource.automatic)),
  );

  // Lock prevents any change (even user calibration).
  c.setLevel(0.4);
  c.lock();
  check('locked reports isLocked', c.isLocked);
  check('locked blocks user calibration', _throwsDenied(() => c.setLevel(0.8)));
  check('level unchanged after blocked change', c.level == 0.4);

  // The core ANSD invariant: a full run of WRONG answers never raises volume.
  final levelBefore = c.level;
  var maxObserved = c.level;
  for (var i = 0; i < 100; i++) {
    c.registerResponse(correct: false);
    if (c.level > maxObserved) maxObserved = c.level;
  }
  check('100 wrong answers do not change level', c.level == levelBefore);
  check('level never rose during wrong-answer run', maxObserved <= levelBefore);

  // Correct answers also do not move master volume.
  for (var i = 0; i < 100; i++) {
    c.registerResponse(correct: true);
  }
  check('100 correct answers do not change level', c.level == levelBefore);

  // Unlock allows re-calibration again.
  c.unlock();
  check('unlock allows calibration', c.setLevel(0.6) == 0.6);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks safety checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks safety checks');
    exit(1);
  }
}
