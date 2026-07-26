// Headless verification for dichotic digits + stereo WAV encoding.
//
//   dart run tool/verify/dichotic_harness.dart
import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/dichotic.dart';

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
  // Stereo WAV: 2 channels, correct sizes, decodes to the LEFT channel.
  final left = tone(seconds: 0.1, freqHz: 300, amp: 0.4, sampleRate: 8000);
  final right = tone(seconds: 0.1, freqHz: 900, amp: 0.4, sampleRate: 8000);
  final wav = encodeWavStereo16(left, right, sampleRate: 8000);
  check('stereo header says 2 channels', wav[22] == 2);
  check('stereo block align = 4', wav[32] == 4);
  final frames = left.length;
  check('stereo data size = frames*4', wav.length == 44 + frames * 4);
  // decodeWav16 reads the first (left) channel of a stereo file.
  final decodedLeft = decodeWav16(wav);
  check('stereo decodes left-channel frames',
      decodedLeft.samples.length == frames);

  // Padding: unequal channel lengths pad to the longer.
  final wav2 = encodeWavStereo16(
    tone(seconds: 0.05, freqHz: 300, sampleRate: 8000),
    tone(seconds: 0.1, freqHz: 300, sampleRate: 8000),
    sampleRate: 8000,
  );
  check('stereo pads to longer channel',
      wav2.length == 44 + (0.1 * 8000).round() * 4);

  // Generator: two distinct digits, valid ear, deterministic.
  final t = DichoticGenerator(seed: 4).next();
  check('digits differ', t.leftDigit != t.rightDigit);
  check('target digit matches cued ear',
      t.targetDigit == (t.targetEar == Ear.left ? t.leftDigit : t.rightDigit));
  final t2 = DichoticGenerator(seed: 4).next();
  check(
      'generator deterministic',
      t2.leftDigit == t.leftDigit &&
          t2.rightDigit == t.rightDigit &&
          t2.targetEar == t.targetEar);

  // Session scoring + per-ear tracking.
  final s = DichoticSession(maxTrials: 10);
  final left1 =
      DichoticTrial(leftDigit: '3', rightDigit: '7', targetEar: Ear.left);
  check('correct report', s.submit(left1, '3', latencyMs: 600));
  check('wrong report', !s.submit(left1, '7', latencyMs: 600));
  final right1 =
      DichoticTrial(leftDigit: '2', rightDigit: '9', targetEar: Ear.right);
  check('right-ear correct', s.submit(right1, '9', latencyMs: 600));
  check('overall accuracy 2/3', (s.accuracy - 2 / 3).abs() < 1e-9);
  check('left-ear accuracy 1/2', (s.leftAccuracy - 0.5).abs() < 1e-9);
  check('right-ear accuracy 1/1', (s.rightAccuracy - 1.0).abs() < 1e-9);
  check('records ear param', s.records.first.parameters['ear'] == 'left');
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks dichotic checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks dichotic checks');
    exit(1);
  }
}
