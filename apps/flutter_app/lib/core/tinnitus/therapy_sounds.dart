/// Tinnitus sound-therapy signal generators (pure Dart).
///
/// Produces the noise colours and nature beds for the sound-therapy player, and
/// a biquad notch filter that removes energy at the listener's matched tinnitus
/// frequency ("notched sound therapy"). Dependency-free (uses
/// `core/audio/pcm_synth.dart`) so it can be unit-tested headlessly.
///
/// SAFETY: all generators target a modest amplitude; the player additionally
/// scales by a volume slider capped at [kMaxSafeAmp].
library;

import 'dart:math' as math;

import '../audio/pcm_synth.dart';
import 'tinnitus_store.dart';

/// The therapy sound choices.
enum TherapySound { white, pink, brown, rain, ocean }

extension TherapySoundInfo on TherapySound {
  String get label => switch (this) {
        TherapySound.white => 'White noise',
        TherapySound.pink => 'Pink noise',
        TherapySound.brown => 'Brown noise',
        TherapySound.rain => 'Rain',
        TherapySound.ocean => 'Ocean',
      };

  String get emoji => switch (this) {
        TherapySound.white => '⬜',
        TherapySound.pink => '🌸',
        TherapySound.brown => '🟫',
        TherapySound.rain => '🌧️',
        TherapySound.ocean => '🌊',
      };
}

/// Pink noise (≈ −3 dB/octave) via Paul Kellet's economical IIR filter on white
/// noise, peak-normalized to [amp].
List<double> pinkNoise({
  required double seconds,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final white = whiteNoise(seconds: seconds, amp: 1.0, seed: seed, sampleRate: sampleRate);
  final out = List<double>.filled(white.length, 0.0);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;
  for (var i = 0; i < white.length; i++) {
    final w = white[i];
    b0 = 0.99886 * b0 + w * 0.0555179;
    b1 = 0.99332 * b1 + w * 0.0750759;
    b2 = 0.96900 * b2 + w * 0.1538520;
    b3 = 0.86650 * b3 + w * 0.3104856;
    b4 = 0.55000 * b4 + w * 0.5329522;
    b5 = -0.7616 * b5 - w * 0.0168980;
    out[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
    b6 = w * 0.115926;
  }
  return _peakNormalize(out, amp);
}

/// Brown/red noise (≈ −6 dB/octave) via a leaky integrator on white noise,
/// peak-normalized to [amp].
List<double> brownNoise({
  required double seconds,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final white = whiteNoise(seconds: seconds, amp: 1.0, seed: seed, sampleRate: sampleRate);
  final out = List<double>.filled(white.length, 0.0);
  var last = 0.0;
  for (var i = 0; i < white.length; i++) {
    last = (last + 0.02 * white[i]) / 1.02;
    out[i] = last;
  }
  return _peakNormalize(out, amp);
}

/// Rain: hiss-like band-limited noise with sparse droplet emphasis.
List<double> rainNoise({
  required double seconds,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final white = whiteNoise(seconds: seconds, amp: 1.0, seed: seed, sampleRate: sampleRate);
  // High-pass by first-difference (emphasises hiss), then gentle low-pass.
  final out = List<double>.filled(white.length, 0.0);
  var prev = 0.0;
  var lp = 0.0;
  for (var i = 0; i < white.length; i++) {
    final hp = white[i] - prev;
    prev = white[i];
    lp += 0.35 * (hp - lp);
    out[i] = lp;
  }
  return _peakNormalize(out, amp);
}

/// Ocean: slow-swell amplitude-modulated, low-passed noise (whooshing surf).
List<double> oceanNoise({
  required double seconds,
  double amp = 0.2,
  int seed = 1,
  int sampleRate = kSampleRate,
}) {
  final white = whiteNoise(seconds: seconds, amp: 1.0, seed: seed, sampleRate: sampleRate);
  final out = List<double>.filled(white.length, 0.0);
  var lp = 0.0;
  const swellHz = 0.12; // ~8 s swell period
  for (var i = 0; i < white.length; i++) {
    lp += 0.02 * (white[i] - lp); // heavy low-pass → dull roar
    final env = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * swellHz * i / sampleRate));
    out[i] = lp * env;
  }
  return _peakNormalize(out, amp);
}

/// Applies an RBJ biquad notch at [freqHz] (removes energy at the tinnitus
/// pitch). [q] controls the notch width (higher = narrower).
List<double> notchFilter(
  List<double> x,
  double freqHz, {
  double q = 6,
  int sampleRate = kSampleRate,
}) {
  if (x.isEmpty || freqHz <= 0 || freqHz >= sampleRate / 2) {
    return List<double>.of(x);
  }
  final w0 = 2 * math.pi * freqHz / sampleRate;
  final cosW0 = math.cos(w0);
  final alpha = math.sin(w0) / (2 * q);
  const b0 = 1.0;
  final b1 = -2 * cosW0;
  const b2 = 1.0;
  final a0 = 1 + alpha;
  final a1 = -2 * cosW0;
  final a2 = 1 - alpha;
  final nb0 = b0 / a0, nb1 = b1 / a0, nb2 = b2 / a0;
  final na1 = a1 / a0, na2 = a2 / a0;
  final out = List<double>.filled(x.length, 0.0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final yi = nb0 * xi + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2;
    out[i] = yi;
    x2 = x1;
    x1 = xi;
    y2 = y1;
    y1 = yi;
  }
  return out;
}

/// Builds a therapy buffer of [type], optionally notched at [notchHz]. [amp] is
/// the target peak (the player scales it further, capped at [kMaxSafeAmp]).
List<double> buildTherapy(
  TherapySound type, {
  required double seconds,
  double amp = 0.4,
  int seed = 1,
  double? notchHz,
  int sampleRate = kSampleRate,
}) {
  List<double> base;
  switch (type) {
    case TherapySound.white:
      base = whiteNoise(seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
    case TherapySound.pink:
      base = pinkNoise(seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
    case TherapySound.brown:
      base = brownNoise(seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
    case TherapySound.rain:
      base = rainNoise(seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
    case TherapySound.ocean:
      base = oceanNoise(seconds: seconds, amp: amp, seed: seed, sampleRate: sampleRate);
  }
  if (notchHz != null && notchHz > 0) {
    base = notchFilter(base, notchHz, sampleRate: sampleRate);
    base = _peakNormalize(base, amp);
  }
  return base;
}

List<double> _peakNormalize(List<double> x, double peak) {
  var mx = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > mx) mx = a;
  }
  if (mx <= 0) return x;
  final k = peak / mx;
  for (var i = 0; i < x.length; i++) {
    x[i] *= k;
  }
  return x;
}
