/// Pure-Dart psychoacoustic PCM synthesis (no Flutter, no audio plugin).
///
/// Mirrors the structural intent of `tools/generate_stimuli.py` (48 kHz, mono,
/// 16-bit) for on-device stimulus generation. Kept dependency-free so it can be
/// verified headlessly (`tool/verify/audio_harness.dart`): sample buffers are
/// plain `List<double>` in [-1, 1] and [encodeWav16] emits a valid RIFF/WAVE
/// byte buffer that an audio player can stream.
library;

import 'dart:math';
import 'dart:typed_data';

/// Standard sample rate for generated stimuli (matches the Python generator).
const int kSampleRate = 48000;

/// Number of samples for [gapMs] at [sampleRate].
int gapSampleCount(double gapMs, [int sampleRate = kSampleRate]) =>
    (gapMs / 1000.0 * sampleRate).round();

/// Seeded white noise of [seconds] duration, amplitude [amp], in [-amp, amp].
/// Deterministic for a given [seed].
List<double> whiteNoise({
  required double seconds,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final rng = Random(seed);
  final n = (seconds * sampleRate).round();
  return List<double>.generate(n, (_) => amp * (rng.nextDouble() * 2 - 1));
}

/// White noise with a silent gap of [gapMs] centred in the buffer — the
/// temporal gap-detection stimulus. Returns a new buffer.
List<double> noiseWithGap({
  required double seconds,
  required double gapMs,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final samples = whiteNoise(
    seconds: seconds,
    amp: amp,
    seed: seed,
    sampleRate: sampleRate,
  );
  final gap = gapSampleCount(gapMs, sampleRate);
  if (gap <= 0) return samples;
  final mid = samples.length ~/ 2;
  final start = (mid - gap ~/ 2).clamp(0, samples.length);
  final end = (start + gap).clamp(0, samples.length);
  for (var i = start; i < end; i++) {
    samples[i] = 0.0;
  }
  return samples;
}

/// [seconds] of silence.
List<double> silence(double seconds, [int sampleRate = kSampleRate]) =>
    List<double>.filled((seconds * sampleRate).round(), 0.0);

/// A pure sine tone at [freqHz] with short raised-cosine fades to avoid clicks.
List<double> tone({
  required double seconds,
  required double freqHz,
  double amp = 0.2,
  double fadeMs = 8,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  final fade = (fadeMs / 1000 * sampleRate).round().clamp(0, n ~/ 2);
  final out = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    var a = amp * sin(2 * pi * freqHz * i / sampleRate);
    if (fade > 0) {
      if (i < fade) {
        a *= 0.5 * (1 - cos(pi * i / fade));
      } else if (i >= n - fade) {
        a *= 0.5 * (1 - cos(pi * (n - 1 - i) / fade));
      }
    }
    out[i] = a;
  }
  return out;
}

/// Frequency (Hz) shifted from [baseHz] by [semitones] (equal temperament).
double shiftSemitones(double baseHz, double semitones) =>
    baseHz * pow(2, semitones / 12).toDouble();

/// Linear modulation depth (0..1) from a dB value. 0 dB = full depth (1.0),
/// more negative = shallower (mirrors the Python generator: depth=10^(dB/20)).
double modulationDepthLinear(double depthDb) =>
    pow(10, depthDb / 20).toDouble().clamp(0.0, 1.0);

/// Amplitude-modulation gain envelope in [1 - depth, 1] at [rateHz].
List<double> amEnvelope({
  required double seconds,
  required double rateHz,
  required double depthDb,
  int sampleRate = kSampleRate,
}) {
  final depth = modulationDepthLinear(depthDb);
  final n = (seconds * sampleRate).round();
  return List<double>.generate(
    n,
    (i) =>
        (1 - depth) +
        depth * (0.5 + 0.5 * sin(2 * pi * rateHz * i / sampleRate)),
  );
}

/// Amplitude-modulated (sinusoidally-gated) white noise — the modulation
/// detection stimulus. At `depthDb == 0` the noise is fully modulated; very
/// negative values are nearly steady.
List<double> amNoise({
  required double seconds,
  required double rateHz,
  required double depthDb,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final noise = whiteNoise(
      seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
  final env = amEnvelope(
    seconds: seconds,
    rateHz: rateHz,
    depthDb: depthDb,
    sampleRate: sampleRate,
  );
  return <double>[for (var i = 0; i < noise.length; i++) noise[i] * env[i]];
}

/// Concatenates sample buffers in order.
List<double> concat(List<List<double>> parts) {
  final out = <double>[];
  for (final p in parts) {
    out.addAll(p);
  }
  return out;
}

/// Peak-normalized per-frame RMS envelope of [samples] in [frames] equal
/// windows (each 0..1) — the data behind the presentation-only stimulus
/// level meter. Returns an empty list for an empty buffer.
List<double> levelEnvelope(List<double> samples, {int frames = 30}) {
  if (samples.isEmpty || frames <= 0) return const <double>[];
  final out = List<double>.filled(frames, 0);
  final frameLen = (samples.length / frames).ceil();
  var peak = 0.0;
  for (var f = 0; f < frames; f++) {
    final start = f * frameLen;
    if (start >= samples.length) break;
    final end = (start + frameLen).clamp(0, samples.length);
    var acc = 0.0;
    for (var i = start; i < end; i++) {
      acc += samples[i] * samples[i];
    }
    final v = sqrt(acc / (end - start));
    out[f] = v;
    if (v > peak) peak = v;
  }
  if (peak > 0) {
    for (var f = 0; f < frames; f++) {
      out[f] /= peak;
    }
  }
  return out;
}

/// Root-mean-square level of a buffer (0 for empty).
double rms(List<double> samples) {
  if (samples.isEmpty) return 0;
  var acc = 0.0;
  for (final x in samples) {
    acc += x * x;
  }
  return sqrt(acc / samples.length);
}

/// Encodes mono samples in [-1, 1] to a 16-bit PCM WAV byte buffer (RIFF/WAVE).
Uint8List encodeWav16(List<double> samples, {int sampleRate = kSampleRate}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);

  void putAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  putAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little); // ChunkSize
  putAscii(8, 'WAVE');
  putAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
  bytes.setUint16(20, 1, Endian.little); // AudioFormat = PCM
  bytes.setUint16(22, 1, Endian.little); // NumChannels = mono
  bytes.setUint32(24, sampleRate, Endian.little); // SampleRate
  bytes.setUint32(28, sampleRate * 2, Endian.little); // ByteRate = sr*ch*bytes
  bytes.setUint16(32, 2, Endian.little); // BlockAlign = ch*bytes
  bytes.setUint16(34, 16, Endian.little); // BitsPerSample
  putAscii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little); // Subchunk2Size

  var offset = 44;
  for (final x in samples) {
    final v = (x.clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(offset, v, Endian.little);
    offset += 2;
  }
  return bytes.buffer.asUint8List();
}

/// A decoded mono PCM buffer.
class DecodedPcm {
  const DecodedPcm(this.samples, this.sampleRate);

  final List<double> samples; // mono, in [-1, 1]
  final int sampleRate;
}

/// Decodes a 16-bit PCM WAV byte buffer to mono samples in [-1, 1].
///
/// Scans RIFF chunks rather than assuming the `data` chunk at offset 44 (e.g.
/// Windows SAPI writes an extended `fmt ` chunk). Multi-channel audio uses the
/// first channel.
DecodedPcm decodeWav16(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  var channels = 1;
  var sampleRate = kSampleRate;
  var bits = 16;
  int? dataOffset;
  int? dataSize;
  var p = 12;
  while (p + 8 <= bytes.length) {
    final id = tag(p);
    final size = view.getUint32(p + 4, Endian.little);
    final body = p + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataSize = size;
    }
    p = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataOffset == null || dataSize == null) {
    throw const FormatException('no data chunk');
  }
  if (bits != 16) {
    throw FormatException('unsupported bit depth: $bits');
  }
  final end = (dataOffset + dataSize).clamp(0, bytes.length);
  final frameStride = 2 * (channels < 1 ? 1 : channels);
  final out = <double>[];
  for (var i = dataOffset; i + frameStride <= end; i += frameStride) {
    out.add(view.getInt16(i, Endian.little) / 32768.0); // first channel
  }
  return DecodedPcm(out, sampleRate);
}

/// Mixes [speech] (the signal) with [noise] at a target [snrDb], returning a
/// peak-normalized buffer the length of [speech]. Noise is scaled so that
/// `20*log10(rmsSpeech / rmsNoiseScaled) == snrDb`, then looped/truncated to
/// fit. Both buffers should share a sample rate.
///
/// SAFETY: this adapts the speech-to-noise ratio; it never changes master
/// volume. Peak-normalization prevents clipping without boosting level on
/// wrong answers.
List<double> mixAtSnr(
  List<double> speech,
  List<double> noise,
  double snrDb, {
  double peak = 0.9,
}) {
  if (speech.isEmpty || noise.isEmpty) return List<double>.of(speech);
  final sRms = rms(speech);
  final nRms = rms(noise);
  if (sRms <= 0 || nRms <= 0) return List<double>.of(speech);
  final targetNoiseRms = sRms / pow(10, snrDb / 20);
  final gain = targetNoiseRms / nRms;
  final out = List<double>.filled(speech.length, 0.0);
  for (var i = 0; i < speech.length; i++) {
    out[i] = speech[i] + noise[i % noise.length] * gain;
  }
  var mx = 0.0;
  for (final x in out) {
    final a = x.abs();
    if (a > mx) mx = a;
  }
  if (mx > peak) {
    final k = peak / mx;
    for (var i = 0; i < out.length; i++) {
      out[i] *= k;
    }
  }
  return out;
}

/// Encodes two channels ([left], [right]) to a 16-bit PCM stereo WAV byte
/// buffer (RIFF/WAVE). The shorter channel is zero-padded to the longer. Used
/// for dichotic (different-signal-per-ear) presentation; the left/right split
/// is preserved so per-ear results stay separable.
Uint8List encodeWavStereo16(
  List<double> left,
  List<double> right, {
  int sampleRate = kSampleRate,
}) {
  final frames = left.length > right.length ? left.length : right.length;
  final dataSize = frames * 4; // 2 channels * 2 bytes
  final bytes = ByteData(44 + dataSize);

  void putAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  int s16(List<double> ch, int i) {
    if (i >= ch.length) return 0;
    return (ch[i].clamp(-1.0, 1.0) * 32767).round();
  }

  putAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  putAscii(8, 'WAVE');
  putAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 2, Endian.little); // 2 channels
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 4, Endian.little); // ByteRate = sr*ch*bytes
  bytes.setUint16(32, 4, Endian.little); // BlockAlign = ch*bytes
  bytes.setUint16(34, 16, Endian.little);
  putAscii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);

  var offset = 44;
  for (var i = 0; i < frames; i++) {
    bytes.setInt16(offset, s16(left, i), Endian.little);
    bytes.setInt16(offset + 2, s16(right, i), Endian.little);
    offset += 4;
  }
  return bytes.buffer.asUint8List();
}
