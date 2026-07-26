// Headless verification harness for modulation-rate discrimination.
//
//   dart run tool/verify/rate_harness.dart
import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/modulation_rate.dart';

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

bool _eq(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  // Session adaptation on the ratio staircase (start 2.0, step 0.2).
  final s = ModulationRateSession(maxTrials: 100);
  final t0 = ThreeIntervalTrial(targetInterval: 0);
  check('starts at ratio 2.0', (s.currentRatio - 2.0).abs() < 1e-9);
  s.submit(t0, 0, latencyMs: 500);
  check('no move after 1 correct', (s.currentRatio - 2.0).abs() < 1e-9);
  s.submit(t0, 0, latencyMs: 500);
  check('harder (smaller ratio) after 2 correct',
      (s.currentRatio - 1.8).abs() < 1e-9);
  s.submit(t0, 1, latencyMs: 500);
  check('easier after wrong', (s.currentRatio - 2.0).abs() < 1e-9);
  check('records rate_ratio', s.records.first.parameters['rate_ratio'] == 2.0);
  check('records reference_rate_hz',
      s.records.first.parameters['reference_rate_hz'] == 20);
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Rate distinction: reference vs oddball envelopes differ.
  final refEnv = amEnvelope(seconds: 0.2, rateHz: 20, depthDb: -3);
  final oddEnv = amEnvelope(seconds: 0.2, rateHz: 40, depthDb: -3);
  check('reference and oddball rate envelopes differ', !_eq(refEnv, oddEnv));

  // Sequence structure.
  const intervalSeconds = 0.5;
  const gapBetween = 0.25;
  final intervalSamples = (intervalSeconds * kSampleRate).round();
  final sepSamples = (gapBetween * kSampleRate).round();
  final seq = buildRateOddballSequence(
    targetInterval: 1,
    referenceRateHz: 20,
    ratio: 2,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 3,
  );
  check('sequence length = 3 bursts + 2 gaps',
      seq.length == 3 * intervalSamples + 2 * sepSamples);
  final seq2 = buildRateOddballSequence(
    targetInterval: 1,
    referenceRateHz: 20,
    ratio: 2,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 3,
  );
  check('sequence deterministic', _eq(seq, seq2));
  check('sequence encodes to WAV',
      encodeWav16(seq).length == 44 + seq.length * 2);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks rate checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks rate checks');
    exit(1);
  }
}
