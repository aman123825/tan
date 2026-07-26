import 'dart:math';
import 'dart:typed_data';

import 'pcm_synth.dart';

/// Synthesize a Duration Pattern Test sequence (3 tones at 1000 Hz).
/// Pattern string: 'L'=long (500ms), 'S'=short (250ms).
/// Returns mono PCM samples at [sampleRate].
List<double> synthesizeDpt(
  String pattern, {
  int sampleRate = kSampleRate,
  double freqHz = 1000,
  double amplitude = 0.6,
  double isiSeconds = 0.3,
  double riseFallMs = 10,
}) {
  final samples = <double>[];
  final isiSamples = (isiSeconds * sampleRate).round();

  for (var i = 0; i < pattern.length; i++) {
    final durationMs = pattern[i] == 'L' ? 500.0 : 250.0;
    final durationSamples = (durationMs / 1000 * sampleRate).round();
    final riseFallSamples = (riseFallMs / 1000 * sampleRate).round();

    // Generate tone with rise/fall envelope
    for (var s = 0; s < durationSamples; s++) {
      final t = s / sampleRate;
      var env = 1.0;
      if (s < riseFallSamples) {
        env = s / riseFallSamples; // rise
      } else if (s > durationSamples - riseFallSamples) {
        env = (durationSamples - s) / riseFallSamples; // fall
      }
      samples.add(amplitude * env * sin(2 * pi * freqHz * t));
    }

    // Add ISI silence (except after last tone)
    if (i < pattern.length - 1) {
      samples.addAll(List<double>.filled(isiSamples, 0));
    }
  }
  return samples;
}

/// Synthesize a Frequency Pattern Test sequence (3 tones at 880/1122 Hz).
/// Pattern string: 'H'=high (1122Hz), 'L'=low (880Hz).
/// Duration: 150ms each, ISI: 150ms.
List<double> synthesizeFpt(
  String pattern, {
  int sampleRate = kSampleRate,
  double highHz = 1122,
  double lowHz = 880,
  double amplitude = 0.6,
  double durationMs = 150,
  double isiMs = 150,
  double riseFallMs = 10,
}) {
  final samples = <double>[];
  final isiSamples = (isiMs / 1000 * sampleRate).round();
  final durationSamples = (durationMs / 1000 * sampleRate).round();
  final riseFallSamples = (riseFallMs / 1000 * sampleRate).round();

  for (var i = 0; i < pattern.length; i++) {
    final freq = pattern[i] == 'H' ? highHz : lowHz;

    for (var s = 0; s < durationSamples; s++) {
      final t = s / sampleRate;
      var env = 1.0;
      if (s < riseFallSamples) {
        env = s / riseFallSamples;
      } else if (s > durationSamples - riseFallSamples) {
        env = (durationSamples - s) / riseFallSamples;
      }
      samples.add(amplitude * env * sin(2 * pi * freq * t));
    }

    if (i < pattern.length - 1) {
      samples.addAll(List<double>.filled(isiSamples, 0));
    }
  }
  return samples;
}

/// Encode mono samples to a stereo WAV with signal only in the specified ear.
/// [ear] is 'left', 'right', or 'both'.
Uint8List encodeMonauralWav(
  List<double> samples, {
  required String ear,
  int sampleRate = kSampleRate,
}) {
  final left = ear == 'right' ? List<double>.filled(samples.length, 0) : samples;
  final right = ear == 'left' ? List<double>.filled(samples.length, 0) : samples;
  return encodeWavStereo16(left, right, sampleRate: sampleRate);
}
