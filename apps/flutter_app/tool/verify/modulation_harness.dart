// Headless verification harness for amplitude-modulation detection.
//
//   dart run tool/verify/modulation_harness.dart
import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/modulation_detection.dart';

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

double _max(List<double> xs) => xs.reduce((a, b) => a > b ? a : b);
double _min(List<double> xs) => xs.reduce((a, b) => a < b ? a : b);

void main() {
  // Envelope semantics: 0 dB = full depth (0..1); -40 dB = nearly steady (~1).
  final full = amEnvelope(seconds: 0.2, rateHz: 20, depthDb: 0);
  check('full-depth envelope peaks near 1', (_max(full) - 1.0).abs() < 1e-6);
  check('full-depth envelope troughs near 0', _min(full) < 0.02);

  final shallow = amEnvelope(seconds: 0.2, rateHz: 20, depthDb: -40);
  check('shallow envelope stays near 1', _min(shallow) > 0.98);
  check('depth(0dB)=1', (modulationDepthLinear(0) - 1.0).abs() < 1e-9);
  check('depth(-40dB)=0.01', (modulationDepthLinear(-40) - 0.01).abs() < 1e-6);

  // amNoise = whiteNoise * envelope, deterministic and bounded.
  final n = amNoise(seconds: 0.1, rateHz: 20, depthDb: -6, amp: 0.2, seed: 5);
  final n2 = amNoise(seconds: 0.1, rateHz: 20, depthDb: -6, amp: 0.2, seed: 5);
  check('amNoise deterministic', _eq(n, n2));
  check(
      'amNoise within amplitude bound', n.every((x) => x.abs() <= 0.2 + 1e-9));
  final base = whiteNoise(seconds: 0.1, amp: 0.2, seed: 5);
  final env = amEnvelope(seconds: 0.1, rateHz: 20, depthDb: -6);
  var product = true;
  for (var i = 0; i < n.length; i++) {
    if ((n[i] - base[i] * env[i]).abs() > 1e-9) product = false;
  }
  check('amNoise equals noise * envelope', product);

  // Session adaptation on the modulation staircase (start -6 dB, Levitt step
  // 4->1): -6 -> -6 -> -10 (down by 4) -> -8 (up by reduced step 2).
  final s = ModulationDetectionSession(maxTrials: 100);
  final t0 = ThreeIntervalTrial(targetInterval: 0);
  check('starts at -6 dB', s.currentDepthDb == -6);
  s.submit(t0, 0, latencyMs: 500); // correct #1 -> no move
  check('no move after 1 correct', s.currentDepthDb == -6);
  s.submit(t0, 0, latencyMs: 500); // correct #2 -> harder (deeper negative)
  check('harder after 2 correct', s.currentDepthDb == -10);
  s.submit(t0, 1, latencyMs: 500); // wrong -> easier (up by reduced step)
  check('easier after wrong (step reduced to 2)', s.currentDepthDb == -8);
  check('records carry depth_db', s.records.first.parameters['depth_db'] == -6);
  check('records carry rate_hz', s.records.first.parameters['rate_hz'] == 20);
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Sequence structure.
  const intervalSeconds = 0.4;
  const gapBetween = 0.25;
  final intervalSamples = (intervalSeconds * kSampleRate).round();
  final sepSamples = (gapBetween * kSampleRate).round();
  final seq = buildModulationSequence(
    targetInterval: 1,
    depthDb: -6,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 3,
  );
  check('sequence length = 3 bursts + 2 separators',
      seq.length == 3 * intervalSamples + 2 * sepSamples);
  final seq2 = buildModulationSequence(
    targetInterval: 1,
    depthDb: -6,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 3,
  );
  check('sequence deterministic', _eq(seq, seq2));
  check('sequence encodes to WAV',
      encodeWav16(seq).length == 44 + seq.length * 2);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks modulation checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks modulation checks');
    exit(1);
  }
}

bool _eq(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
