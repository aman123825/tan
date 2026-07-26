// Headless verification harness for pitch discrimination (tone synth + 3AFC).
//
//   dart run tool/verify/pitch_harness.dart
import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/pitch_discrimination.dart';

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

int _zeroCrossings(List<double> s) {
  var count = 0;
  for (var i = 1; i < s.length; i++) {
    if ((s[i - 1] <= 0 && s[i] > 0) || (s[i - 1] >= 0 && s[i] < 0)) count++;
  }
  return count;
}

void main() {
  // Tone frequency verified via zero-crossings (~2*f*seconds).
  const seconds = 0.5;
  final t440 = tone(seconds: seconds, freqHz: 440);
  final crossings = _zeroCrossings(t440);
  final estFreq = crossings / (2 * seconds);
  check('tone length', t440.length == (seconds * kSampleRate).round());
  check(
      'tone within amplitude bound', t440.every((x) => x.abs() <= 0.2 + 1e-9));
  check('tone frequency ~440 Hz (zero-crossings)', (estFreq - 440).abs() <= 3);
  check('tone deterministic',
      _zeroCrossings(tone(seconds: seconds, freqHz: 440)) == crossings);
  check('faded ends start/finish near zero',
      t440.first.abs() < 1e-6 && t440.last.abs() < 1e-6);

  // Semitone shift: +12 semitones doubles frequency.
  check('12 semitones doubles frequency',
      (shiftSemitones(440, 12) - 880).abs() < 1e-9);
  check('0 semitones is identity', shiftSemitones(440, 0) == 440);

  // Session adaptation (start 6 st, Levitt step 2->0.25, 2-down/1-up):
  // 6 -> 6 -> 4 (down by 2) -> 5 (up by reduced step 1).
  final s = PitchDiscriminationSession(maxTrials: 100);
  final t0 = ThreeIntervalTrial(targetInterval: 0);
  check('starts at 6 semitones', s.currentDeltaSemitones == 6);
  s.submit(t0, 0, latencyMs: 500);
  check('no move after 1 correct', s.currentDeltaSemitones == 6);
  s.submit(t0, 0, latencyMs: 500);
  check('harder (smaller delta) after 2 correct', s.currentDeltaSemitones == 4);
  s.submit(t0, 1, latencyMs: 500);
  check('easier after wrong (step reduced to 1)', s.currentDeltaSemitones == 5);
  check('records delta_semitones',
      s.records.first.parameters['delta_semitones'] == 6);
  check('records reference_hz',
      s.records.first.parameters['reference_hz'] == 440);
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Sequence structure.
  const toneSeconds = 0.4;
  const gapBetween = 0.2;
  final toneSamples = (toneSeconds * kSampleRate).round();
  final sepSamples = (gapBetween * kSampleRate).round();
  final seq = buildOddballSequence(
    targetInterval: 1,
    referenceHz: 440,
    deltaSemitones: 6,
    toneSeconds: toneSeconds,
    gapBetweenSeconds: gapBetween,
  );
  check('sequence length = 3 tones + 2 gaps',
      seq.length == 3 * toneSamples + 2 * sepSamples);
  final seq2 = buildOddballSequence(
    targetInterval: 1,
    referenceHz: 440,
    deltaSemitones: 6,
    toneSeconds: toneSeconds,
    gapBetweenSeconds: gapBetween,
  );
  check('sequence deterministic', _eq(seq, seq2));
  check('sequence encodes to WAV',
      encodeWav16(seq).length == 44 + seq.length * 2);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks pitch checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks pitch checks');
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
