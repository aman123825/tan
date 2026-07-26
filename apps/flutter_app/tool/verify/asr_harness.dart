// Headless verification for the optional ASR assistance seam.
//
//   dart run tool/verify/asr_harness.dart
import 'dart:io';

import '../../lib/core/asr.dart';

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

/// A deterministic fake engine used to verify the seam without a real model.
class _FakeAsr implements AsrProvider {
  _FakeAsr(this._result, {this.available = true});
  final AsrResult? _result;
  final bool available;
  int calls = 0;
  @override
  bool get isAvailable => available;
  @override
  Future<AsrResult?> listen() async {
    calls++;
    return _result;
  }
}

Future<void> main() async {
  // Disabled default: no availability, no result.
  const disabled = DisabledAsrProvider();
  check('disabled not available', !disabled.isAvailable);
  check('disabled returns null', await disabled.listen() == null);

  // Result model.
  const r = AsrResult('bell', confidence: 0.9);
  check('result transcript', r.transcript == 'bell');
  check('result confidence', r.confidence == 0.9);
  check('result default confidence', const AsrResult('x').confidence == 1.0);

  // Fake provider contract.
  final fake = _FakeAsr(const AsrResult('boat'));
  check('fake available', fake.isAvailable);
  final got = await fake.listen();
  check('fake transcribes', got?.transcript == 'boat');
  check('listen invoked once', fake.calls == 1);

  // A provider may be present but decline (no speech recognized).
  final empty = _FakeAsr(null);
  check('declining provider returns null', await empty.listen() == null);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks asr checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks asr checks');
    exit(1);
  }
}
