// Headless verification harness for the temporal gap-detection logic.
//
//   dart run tool/verify/gap_harness.dart
import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/gap_detection.dart';

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
  // Generator determinism + range.
  final a = ThreeIntervalGenerator(seed: 9).next();
  final b = ThreeIntervalGenerator(seed: 9).next();
  check('generator deterministic', a.targetInterval == b.targetInterval);
  check('target in range', a.targetInterval >= 0 && a.targetInterval < 3);

  // Session adaptation on the gap staircase (start 20 ms, Levitt step 4->1,
  // 2-down/1-up): 20 -> 20 -> 16 (down by 4) -> 18 (up by reduced step 2).
  final session = GapDetectionSession(maxTrials: 100);
  final t0 = ThreeIntervalTrial(targetInterval: 0);
  check('starts at 20 ms', session.currentGapMs == 20);
  session.submit(t0, 0, latencyMs: 500); // correct #1 -> no move
  check('no move after 1 correct', session.currentGapMs == 20);
  session.submit(t0, 0, latencyMs: 500); // correct #2 -> harder (down by step 4)
  check('harder after 2 correct', session.currentGapMs == 16);
  session.submit(t0, 1, latencyMs: 500); // wrong -> easier (up by reduced step)
  check('easier after wrong (step reduced to 2)', session.currentGapMs == 18);
  check('accuracy = 2/3', (session.accuracy - 2 / 3).abs() < 1e-9);
  check('first trial presented at 20 ms',
      session.records.first.parameters['gap_ms'] == 20);
  check('third trial presented at 16 ms',
      session.records[2].parameters['gap_ms'] == 16);
  check(
      'trial json has no volume key',
      !session.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Sequence structure: length and gap presence in the target interval.
  const intervalSeconds = 0.4;
  const gapBetween = 0.25;
  final intervalSamples = (intervalSeconds * kSampleRate).round();
  final sepSamples = (gapBetween * kSampleRate).round();
  const gapMs = 50.0;
  final seq = buildGapSequence(
    targetInterval: 1,
    gapMs: gapMs,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 5,
  );
  final expectedLen = 3 * intervalSamples + 2 * sepSamples;
  check('sequence length = 3 bursts + 2 separators', seq.length == expectedLen);

  final zeros = seq.where((x) => x == 0.0).length;
  final sepZeros = 2 * sepSamples;
  final gapSamples = gapSampleCount(gapMs);
  check('gap adds silence beyond the separators',
      zeros >= sepZeros + gapSamples && zeros <= sepZeros + gapSamples + 8);

  final seq2 = buildGapSequence(
    targetInterval: 1,
    gapMs: gapMs,
    intervalSeconds: intervalSeconds,
    gapBetweenSeconds: gapBetween,
    seed: 5,
  );
  check('sequence deterministic for same seed', _eq(seq, seq2));

  // WAV encode the sequence (integration with the synth layer).
  final wav = encodeWav16(seq);
  check('sequence encodes to a WAV of expected size',
      wav.length == 44 + seq.length * 2);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks gap checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks gap checks');
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
