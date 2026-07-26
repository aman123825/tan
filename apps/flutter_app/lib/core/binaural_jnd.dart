/// ITD / ILD lateralization JND measurement primitives (pure Dart).
///
/// Binaural cue sensitivity is measured as the just-noticeable interaural
/// difference in a 2-interval task: one interval is diotic (identical in both
/// ears — heard at the centre of the head), the other carries an interaural
/// time difference (whole-waveform delay of one ear) or an interaural level
/// difference (per-ear gain). The listener picks the interval that sounded
/// off-centre; a 2-down/1-up staircase converges on the ≈70.7%-correct JND
/// (cf. Klumpp & Eady, 1956; Mills, 1958; Yost & Dye, 1988).
///
/// ITD uses a 500 Hz tone (fine-structure ITD is a low-frequency cue); ILD
/// uses a broadband noise burst. Fractional-sample delays are realized by
/// linear interpolation, so sub-sample ITDs (< 20.8 µs at 48 kHz) present
/// correctly.
///
/// SAFETY: adaptation moves the interaural difference only — never level
/// beyond the fixed ±ILD/2 gains, never master volume.
library;

import 'dart:math';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';

/// Signal duration per interval (seconds).
const double kBinauralIntervalSeconds = 0.4;

/// ITD staircase: 500 µs start, Levitt-reduced 100 → 20 µs steps.
AdaptiveTrack itdTrack() => AdaptiveTrack(
      value: 500,
      min: 10,
      max: 900,
      step: 100,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 20,
    );

/// ILD staircase: 6 dB start, Levitt-reduced 2 → 0.5 dB steps.
AdaptiveTrack ildTrack() => AdaptiveTrack(
      value: 6,
      min: 0.25,
      max: 14,
      step: 2,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 0.5,
    );

/// Delays [x] by [delaySamples] (may be fractional; linear interpolation,
/// zeros before signal onset — including a correctly-interpolated sub-sample
/// onset ramp). Output length matches the input.
List<double> fractionalDelay(List<double> x, double delaySamples) {
  final out = List<double>.filled(x.length, 0);
  for (var i = 0; i < x.length; i++) {
    final src = i - delaySamples;
    if (src <= -1) continue;
    final i0 = src.floor();
    final frac = src - i0;
    final a = (i0 >= 0 && i0 < x.length) ? x[i0] : 0.0;
    final b = (i0 + 1 >= 0 && i0 + 1 < x.length) ? x[i0 + 1] : 0.0;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

/// A stereo pair (left, right) for one interval.
class StereoInterval {
  const StereoInterval(this.left, this.right);

  final List<double> left;
  final List<double> right;
}

/// One diotic (centred) 500 Hz tone interval.
StereoInterval diotticTone({double amp = 0.25, int sampleRate = kSampleRate}) {
  final s = tone(
      seconds: kBinauralIntervalSeconds,
      freqHz: 500,
      amp: amp,
      sampleRate: sampleRate);
  return StereoInterval(s, List<double>.of(s));
}

/// A 500 Hz tone lateralized by [itdUs] toward [leadingSide] ('left'|'right'):
/// the opposite ear's copy is delayed by the whole-waveform ITD.
StereoInterval itdTone(
  double itdUs, {
  required String leadingSide,
  double amp = 0.25,
  int sampleRate = kSampleRate,
}) {
  final s = tone(
      seconds: kBinauralIntervalSeconds,
      freqHz: 500,
      amp: amp,
      sampleRate: sampleRate);
  final delayed = fractionalDelay(s, itdUs * 1e-6 * sampleRate);
  return leadingSide == 'left'
      ? StereoInterval(s, delayed)
      : StereoInterval(delayed, s);
}

/// One diotic (centred) noise-burst interval (seeded, deterministic).
StereoInterval diotticNoise({
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final s = whiteNoise(
      seconds: kBinauralIntervalSeconds,
      amp: amp,
      seed: seed,
      sampleRate: sampleRate);
  return StereoInterval(s, List<double>.of(s));
}

/// A noise burst lateralized by [ildDb] toward [louderSide]: +ILD/2 dB gain on
/// that ear and −ILD/2 on the other (overall energy roughly constant).
StereoInterval ildNoise(
  double ildDb, {
  required String louderSide,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final s = whiteNoise(
      seconds: kBinauralIntervalSeconds,
      amp: amp,
      seed: seed,
      sampleRate: sampleRate);
  final up = pow(10, ildDb / 40).toDouble(); // +ILD/2 dB
  final down = 1 / up; // −ILD/2 dB
  final louder = <double>[for (final v in s) (v * up).clamp(-1.0, 1.0)];
  final softer = <double>[for (final v in s) v * down];
  return louderSide == 'left'
      ? StereoInterval(louder, softer)
      : StereoInterval(softer, louder);
}

/// Concatenates 2 stereo intervals (target at [targetIndex], reference at the
/// other slot) with [gapSeconds] of silence between, ready for
/// `encodeWavStereo16`.
StereoInterval assembleTwoIntervals({
  required StereoInterval reference,
  required StereoInterval target,
  required int targetIndex,
  double gapSeconds = 0.3,
  int sampleRate = kSampleRate,
}) {
  final gap = silence(gapSeconds, sampleRate);
  final first = targetIndex == 0 ? target : reference;
  final second = targetIndex == 0 ? reference : target;
  return StereoInterval(
    concat([first.left, gap, second.left]),
    concat([first.right, gap, second.right]),
  );
}
