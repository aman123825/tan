// Headless verification harness for WAV decode + speech-in-noise mixing.
//
//   dart run tool/verify/speech_harness.dart
import 'dart:io';
import 'dart:math';

import '../../lib/core/audio/pcm_synth.dart';

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

const List<String> _words = [
  'bell', 'ball', 'bat', 'bag', 'pen', 'pin', 'cup', 'cap', //
];

void main() {
  // 1) encode -> decode round-trip.
  final original = tone(seconds: 0.05, freqHz: 440, amp: 0.5);
  final wav = encodeWav16(original, sampleRate: 22050);
  final decoded = decodeWav16(wav);
  check('round-trip sample rate', decoded.sampleRate == 22050);
  check('round-trip length', decoded.samples.length == original.length);
  var maxErr = 0.0;
  for (var i = 0; i < original.length; i++) {
    final e = (decoded.samples[i] - original[i]).abs();
    if (e > maxErr) maxErr = e;
  }
  check('round-trip within 16-bit quantisation', maxErr < 1e-3);

  // 2) Real SAPI word assets decode (chunk-scanning; data not at offset 44).
  var allDecode = true;
  var wordRate = 0;
  for (final w in _words) {
    final uri =
        Platform.script.resolve('../../assets/stimuli/speech/word_$w.wav');
    final f = File.fromUri(uri);
    if (!f.existsSync()) {
      allDecode = false;
      continue;
    }
    final d = decodeWav16(f.readAsBytesSync());
    if (d.samples.isEmpty) allDecode = false;
    wordRate = d.sampleRate;
  }
  check('all 8 word assets exist and decode', allDecode);
  check('word assets decode at a valid speech rate',
      wordRate >= 16000 && wordRate <= 48000);

  // 3) SNR mixing behaviour.
  final speech = tone(seconds: 0.4, freqHz: 300, amp: 0.3);
  final noise = whiteNoise(seconds: 0.4, amp: 0.2, seed: 5);
  final sRms = rms(speech);

  final at0 = mixAtSnr(speech, noise, 0);
  check('mix length equals speech length', at0.length == speech.length);
  // Uncorrelated speech+noise at 0 dB SNR -> rms ~ sRms*sqrt(2).
  check('SNR 0 dB: combined rms ~ sqrt(2)*speech',
      (rms(at0) - sRms * sqrt(2)).abs() / (sRms * sqrt(2)) < 0.15);

  final atHigh = mixAtSnr(speech, noise, 20);
  check('SNR +20 dB: barely any noise (rms ~ speech)',
      (rms(atHigh) - sRms).abs() / sRms < 0.12);

  final atLow = mixAtSnr(speech, noise, -6);
  check('SNR -6 dB: more noise than speech', rms(atLow) > sRms);

  // 4) Peak-normalisation keeps output within range (no clipping/boosting).
  check('mixed output stays within [-1, 1]',
      atLow.every((x) => x.abs() <= 1.0 + 1e-9));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks speech checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks speech checks');
    exit(1);
  }
}
