/// Multi-talker proxy voice variants (pure Dart).
///
/// The recorded demo corpus is a single synthesized voice; real multi-talker
/// recordings do not exist yet (UPGRADE_PLAN K1/K2). Until they do, speech
/// tasks can still train talker variability with deterministic pitch/rate
/// transposition of the one voice — the same proxy-voice mechanism the LiSN-S
/// implementation uses for its "different talker" masker (naive linear
/// resample: shorter = higher). Four fixed ratios approximate two lower
/// ("male-ish") and two higher ("female-ish") voices.
///
/// These are clearly-labelled SYNTHESIZED PROXY VOICES (`demo_only`), not
/// validated multi-talker stimuli. Presentation only — never affects scoring,
/// adaptation or master volume.
library;

import 'dart:math';

/// One proxy voice: a display label and the resample ratio applied to the
/// base recording (> 1 raises pitch and shortens; < 1 lowers and lengthens).
class VoiceVariant {
  const VoiceVariant(this.id, this.label, this.ratio);

  final String id;
  final String label;
  final double ratio;
}

/// The four proxy voices (v1 is the untransposed original).
const List<VoiceVariant> kVoiceVariants = <VoiceVariant>[
  VoiceVariant('v1', 'Voice A', 1.0),
  VoiceVariant('v2', 'Voice B', 0.84), // ≈ −3 st: lower, slower
  VoiceVariant('v3', 'Voice C', 1.12), // ≈ +2 st: higher, faster
  VoiceVariant('v4', 'Voice D', 0.92), // ≈ −1.4 st: slightly lower
];

/// Deterministically picks a voice for [trialIndex] (seeded rotation, so a
/// given seed hears the same voice sequence on every run).
VoiceVariant voiceForTrial(int seed, int trialIndex) {
  final rng = Random(seed * 92821 + trialIndex);
  return kVoiceVariants[rng.nextInt(kVoiceVariants.length)];
}

/// Applies [variant] to mono [samples] by naive linear-interpolation resample
/// (the LiSN-S different-talker transform). Ratio 1.0 returns a copy.
List<double> applyVoiceVariant(List<double> samples, VoiceVariant variant) {
  final ratio = variant.ratio;
  if (ratio == 1.0 || samples.length < 2) return List<double>.of(samples);
  final outLen = (samples.length / ratio).floor();
  final out = List<double>.filled(outLen, 0);
  for (var i = 0; i < outLen; i++) {
    final src = i * ratio;
    final i0 = src.floor();
    final frac = src - i0;
    final a = i0 < samples.length ? samples[i0] : 0.0;
    final b = (i0 + 1) < samples.length ? samples[i0 + 1] : 0.0;
    out[i] = a + (b - a) * frac;
  }
  return out;
}
