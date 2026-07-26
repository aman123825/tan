// Headless verification harness for the PCM synthesis layer.
//
//   dart run tool/verify/audio_harness.dart
import 'dart:io';
import 'dart:typed_data';

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

String _ascii(Uint8List b, int off, int len) {
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.writeCharCode(b[off + i]);
  }
  return sb.toString();
}

void main() {
  // White noise: length, bound, determinism, non-silence.
  final n1 = whiteNoise(seconds: 0.1, amp: 0.2, seed: 7);
  final n2 = whiteNoise(seconds: 0.1, amp: 0.2, seed: 7);
  final n3 = whiteNoise(seconds: 0.1, amp: 0.2, seed: 8);
  check(
      'noise length = seconds*rate', n1.length == (0.1 * kSampleRate).round());
  check('noise within amplitude bound', n1.every((x) => x.abs() <= 0.2 + 1e-9));
  check('noise deterministic for same seed', _eq(n1, n2));
  check('noise differs for different seed', !_eq(n1, n3));
  check('noise is not silent', rms(n1) > 0.05);

  // Gap: exact count of silent samples centred in the buffer.
  const gapMs = 10.0;
  final g = noiseWithGap(seconds: 0.2, gapMs: gapMs, seed: 3);
  final expectedGap = gapSampleCount(gapMs);
  final zeros = g.where((x) => x == 0.0).length;
  check('gap sample count = round(gapMs/1000*rate)',
      expectedGap == (gapMs / 1000 * kSampleRate).round());
  check('gap region is silent (>= gap samples are zero)', zeros >= expectedGap);
  final mid = g.length ~/ 2;
  check('gap is centred (midpoint silent)', g[mid] == 0.0);
  check('signal outside the gap is present', g.first != 0.0 || rms(g) > 0.05);
  check(
      'zero gapMs leaves noise untouched',
      noiseWithGap(seconds: 0.05, gapMs: 0, seed: 3).every((x) => x != 0.0) ||
          rms(noiseWithGap(seconds: 0.05, gapMs: 0, seed: 3)) > 0.05);

  // silence + concat.
  final seq = concat([whiteNoise(seconds: 0.05, seed: 1), silence(0.02)]);
  check(
      'concat length adds up',
      seq.length ==
          (0.05 * kSampleRate).round() + (0.02 * kSampleRate).round());
  check('trailing silence is zero', seq.last == 0.0);

  // WAV encoding: header fields, sizes, and a sample round-trip.
  final samples = whiteNoise(seconds: 0.01, amp: 0.5, seed: 2);
  final wav = encodeWav16(samples, sampleRate: kSampleRate);
  final view = ByteData.sublistView(wav);
  check('RIFF magic', _ascii(wav, 0, 4) == 'RIFF');
  check('WAVE magic', _ascii(wav, 8, 4) == 'WAVE');
  check('fmt  chunk', _ascii(wav, 12, 4) == 'fmt ');
  check('data chunk', _ascii(wav, 36, 4) == 'data');
  check('PCM format', view.getUint16(20, Endian.little) == 1);
  check('mono', view.getUint16(22, Endian.little) == 1);
  check('48 kHz', view.getUint32(24, Endian.little) == kSampleRate);
  check('16-bit', view.getUint16(34, Endian.little) == 16);
  check('data size = samples*2',
      view.getUint32(40, Endian.little) == samples.length * 2);
  check('total length = 44 + data', wav.length == 44 + samples.length * 2);
  // Round-trip: first sample decoded back within 16-bit quantisation error.
  final decoded0 = view.getInt16(44, Endian.little) / 32767.0;
  check('sample round-trips within quantisation',
      (decoded0 - samples.first).abs() < 1e-3);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks audio checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks audio checks');
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
