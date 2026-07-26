/// Research-only normative interpretation of measured thresholds and scores.
///
/// IMPORTANT — READ THIS FIRST
/// This is NOT a diagnosis and NOT a clinical result. The reference bands below
/// come from published literature on *validated clinical procedures*. HearBloom
/// presents *demonstration* stimuli on *uncalibrated* home audio, so an
/// interpretation here is illustrative context only — it situates a result
/// against the literature so a learner/clinician can see the ballpark, nothing
/// more. No dB HL, no diagnosis, and results are never pooled across output
/// devices. Every band carries its citation.
///
/// This logic is mirrored 1:1 in `packages/protocol_engine/norms.py` and
/// checked headlessly by `tool/verify/norms_harness.dart`.
library;

/// Where a measured value falls relative to published reference data.
enum NormBand {
  betterThanTypical,
  withinTypical,
  slightlyBelowTypical,
  belowTypical,
  insufficient,
}

extension NormBandInfo on NormBand {
  /// A short, non-clinical label suitable for a chip/badge.
  String get label => switch (this) {
        NormBand.betterThanTypical => 'Better than typical',
        NormBand.withinTypical => 'Within typical range',
        NormBand.slightlyBelowTypical => 'Slightly below typical',
        NormBand.belowTypical => 'Below typical range',
        NormBand.insufficient => 'Not enough data',
      };

  /// True for the two "at or above expectation" bands (UI can tint green).
  bool get isFavorable =>
      this == NormBand.betterThanTypical || this == NormBand.withinTypical;
}

/// The outcome of a normative comparison: a band plus a plain-language detail
/// and the literature it is based on.
class NormResult {
  const NormResult(this.band, this.detail, this.citation);

  const NormResult.insufficient()
      : band = NormBand.insufficient,
        detail = 'Complete more trials (enough reversals) to estimate a '
            'threshold before it can be compared with reference data.',
        citation = '';

  final NormBand band;
  final String detail;
  final String citation;

  String get label => band.label;
  bool get isInsufficient => band == NormBand.insufficient;
}

/// Research-derived reference bands. Every threshold here is *task-relative and
/// illustrative* because the stimuli/calibration are not clinical.
class Norms {
  const Norms._();

  /// Temporal gap-detection threshold (ms); lower = finer temporal resolution.
  ///
  /// Reference: Gaps-in-Noise (GIN) normal approximated-threshold ≤ 6 ms
  /// (Musiek et al., 2005); normal-hearing young adults average ≈ 4.2–5.4 ms
  /// (Int. J. Audiol., 2008; Samelli & Schochat, 2008).
  static NormResult gapMs(double? ms) {
    if (ms == null) return const NormResult.insufficient();
    const cite = 'GIN norms: Musiek et al., 2005; Int. J. Audiol. 2008';
    if (ms <= 4) {
      return const NormResult(NormBand.betterThanTypical,
          'A gap threshold ≤ 4 ms is at the fine end of normal-adult GIN data.',
          cite);
    }
    if (ms <= 6) {
      return const NormResult(NormBand.withinTypical,
          '≤ 6 ms is the normal GIN cut-off for adults.', cite);
    }
    if (ms <= 10) {
      return const NormResult(NormBand.slightlyBelowTypical,
          '6–10 ms is just outside the typical adult GIN range.', cite);
    }
    return const NormResult(NormBand.belowTypical,
        '> 10 ms is well outside typical adult GIN temporal resolution.', cite);
  }

  /// Frequency / pitch-discrimination threshold (semitones); lower = finer.
  ///
  /// Reference concept: the frequency difference limen (DL) at ~1 kHz is on the
  /// order of a few Hz for trained listeners (Wier, Jesteadt & Green, 1977).
  /// Bands here are task-relative for a 3AFC oddball on uncalibrated audio.
  static NormResult frequencySemitones(double? st) {
    if (st == null) return const NormResult.insufficient();
    const cite = 'Frequency DL concept: Wier, Jesteadt & Green, 1977 '
        '(task-relative, illustrative)';
    if (st <= 0.5) {
      return const NormResult(NormBand.betterThanTypical,
          'Resolving < ~0.5 semitone is a fine pitch difference.', cite);
    }
    if (st <= 1) {
      return const NormResult(NormBand.withinTypical,
          '≈ 1 semitone is a solid pitch-discrimination result for this task.',
          cite);
    }
    if (st <= 2) {
      return const NormResult(NormBand.slightlyBelowTypical,
          '1–2 semitones is a coarser pitch difference.', cite);
    }
    return const NormResult(NormBand.belowTypical,
        '> 2 semitones indicates coarse pitch discrimination on this task.',
        cite);
  }

  /// Amplitude-modulation-detection threshold (dB re: 20·log₁₀ m); more negative
  /// = detecting shallower modulation = better temporal-envelope sensitivity.
  ///
  /// Reference: temporal modulation transfer functions show best sensitivity of
  /// roughly −20 to −26 dB at low modulation rates for broadband-noise carriers
  /// (Viemeister, 1979; Bacon & Viemeister, 1985). Task-relative here.
  static NormResult amDepthDb(double? db) {
    if (db == null) return const NormResult.insufficient();
    const cite = 'TMTF: Viemeister, 1979; Bacon & Viemeister, 1985 '
        '(task-relative)';
    if (db <= -20) {
      return const NormResult(NormBand.betterThanTypical,
          'Detecting ≤ −20 dB modulation approaches published TMTF sensitivity.',
          cite);
    }
    if (db <= -12) {
      return const NormResult(NormBand.withinTypical,
          '−12 to −20 dB is a good modulation-detection result for this task.',
          cite);
    }
    if (db <= -6) {
      return const NormResult(NormBand.slightlyBelowTypical,
          '−6 to −12 dB is shallower sensitivity than the published best.',
          cite);
    }
    return const NormResult(NormBand.belowTypical,
        'Requiring > −6 dB (deep) modulation indicates reduced sensitivity.',
        cite);
  }

  /// Speech-in-noise threshold — the adaptive SNR (dB) at the tracked point;
  /// lower = understanding speech at a worse (noisier) SNR = better.
  ///
  /// Reference *concept*: QuickSIN SNR-loss bands (0–3 dB normal/near-normal,
  /// 3–7 mild, 7–15 moderate; Killion et al., 2004). Our measure is an absolute
  /// 4AFC word-in-noise SNR, not QuickSIN SNR-loss, so bands are task-relative.
  static NormResult speechSnrDb(double? db) {
    if (db == null) return const NormResult.insufficient();
    const cite = 'cf. QuickSIN SNR-loss, Killion et al., 2004 '
        '(task-relative absolute SNR)';
    if (db <= 0) {
      return const NormResult(NormBand.betterThanTypical,
          'Understanding at ≤ 0 dB SNR is strong speech-in-noise performance.',
          cite);
    }
    if (db <= 4) {
      return const NormResult(NormBand.withinTypical,
          '0–4 dB SNR at threshold is a typical result for this task.', cite);
    }
    if (db <= 8) {
      return const NormResult(NormBand.slightlyBelowTypical,
          '4–8 dB SNR suggests more favourable SNR is needed than typical.',
          cite);
    }
    return const NormResult(NormBand.belowTypical,
        'Needing > 8 dB SNR indicates difficulty with speech in noise.', cite);
  }

  /// Dichotic-digits score per ear (percent correct); higher = better.
  ///
  /// Reference: Dichotic Digits Test normal cut-off for adults (> 12 y) ≈ 90%
  /// per ear, with a small right-ear advantage (Musiek, 1983).
  static NormResult dichoticPercent(double? percent) {
    if (percent == null) return const NormResult.insufficient();
    const cite = 'DDT norms: Musiek, 1983 (adults ≈ ≥ 90%/ear)';
    if (percent >= 95) {
      return const NormResult(NormBand.betterThanTypical,
          '≥ 95% per ear is at the top of the adult DDT range.', cite);
    }
    if (percent >= 90) {
      return const NormResult(NormBand.withinTypical,
          '≥ 90% per ear is the normal adult DDT cut-off.', cite);
    }
    if (percent >= 80) {
      return const NormResult(NormBand.slightlyBelowTypical,
          '80–90% per ear is just below the adult DDT cut-off.', cite);
    }
    return const NormResult(NormBand.belowTypical,
        '< 80% per ear is below the typical adult DDT range.', cite);
  }

  /// Guessing-corrected proportion for an n-alternative forced-choice task
  /// (Abbott's formula / high-threshold correction): removes the 1/n chance
  /// floor so a score reflects performance *above guessing*. Clamped to [0, 1].
  static double chanceCorrected(double observed, int alternatives) {
    if (alternatives < 2) return observed.clamp(0.0, 1.0);
    final chance = 1 / alternatives;
    final c = (observed - chance) / (1 - chance);
    return c < 0 ? 0.0 : (c > 1 ? 1.0 : c);
  }
}


// ---------------------------------------------------------------------------
// Age-stratified normative interpretation
// ---------------------------------------------------------------------------
//
// The single-value functions above use adult reference bands. Real CAPD
// batteries are age-stratified: the same score is "typical" for a 7-year-old
// but "below typical" for an adult, and older adults' temporal / speech-in-noise
// performance declines again. The cut-offs below derive from the KEY NORMATIVE
// REFERENCE TABLE in UPGRADE_PLAN.md — its explicit anchors are Adults (18–50)
// and Children (7–11) — with standard developmental/aging adjustments applied
// to the intermediate (11–17) and older (51+) bands. Research-only and
// illustrative on uncalibrated audio; never a diagnosis.

/// Age bands for age-stratified normative lookup.
enum AgeBand {
  years7to8,
  years9to10,
  years11to12,
  years13to17,
  years18to50,
  years51to65,
  years65plus,
}

extension AgeBandInfo on AgeBand {
  /// Human-readable label for the band.
  String get label => switch (this) {
        AgeBand.years7to8 => '7–8 years',
        AgeBand.years9to10 => '9–10 years',
        AgeBand.years11to12 => '11–12 years',
        AgeBand.years13to17 => '13–17 years',
        AgeBand.years18to50 => '18–50 years',
        AgeBand.years51to65 => '51–65 years',
        AgeBand.years65plus => '65+ years',
      };
}

/// Resolves an age in whole years to its [AgeBand]. Ages below 7 fall back to
/// the youngest (7–8) band — these tests are not normed below ~7 years.
AgeBand ageBandFor(int years) {
  if (years <= 8) return AgeBand.years7to8;
  if (years <= 10) return AgeBand.years9to10;
  if (years <= 12) return AgeBand.years11to12;
  if (years <= 17) return AgeBand.years13to17;
  if (years <= 50) return AgeBand.years18to50;
  if (years <= 65) return AgeBand.years51to65;
  return AgeBand.years65plus;
}

/// Per-band cut-offs. [normal] is the "within typical" boundary; [abnormal] is
/// the "below typical range" boundary. Their direction depends on
/// [_AgeTestNorm.higherIsBetter].
class _BandCut {
  const _BandCut(this.normal, this.abnormal);
  final double normal;
  final double abnormal;
}

/// One age-stratified test's reference data.
class _AgeTestNorm {
  const _AgeTestNorm({
    required this.name,
    required this.unit,
    required this.higherIsBetter,
    required this.betterMargin,
    required this.citation,
    required this.bands,
  });

  final String name;
  final String unit; // 'ms', '%', 'dB', 'dB SNR-loss'
  final bool higherIsBetter;
  final double betterMargin; // beyond `normal` counts as better-than-typical
  final String citation;
  final Map<AgeBand, _BandCut> bands;
}

/// Formats a cut-off / value without a trailing ".0".
String _fmtNorm(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

const Map<String, _AgeTestNorm> _ageNorms = <String, _AgeTestNorm>{
  // Gaps-in-Noise gap threshold (ms); lower = finer temporal resolution.
  'gin': _AgeTestNorm(
    name: 'GIN gap threshold',
    unit: 'ms',
    higherIsBetter: false,
    betterMargin: 2,
    citation: 'GIN age norms: Musiek et al., 2005 '
        '(adult ≤ 6 ms, child ≤ 8 ms; UPGRADE_PLAN normative table)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(8, 10),
      AgeBand.years9to10: _BandCut(8, 10),
      AgeBand.years11to12: _BandCut(7, 9),
      AgeBand.years13to17: _BandCut(6, 8),
      AgeBand.years18to50: _BandCut(6, 8),
      AgeBand.years51to65: _BandCut(7, 9),
      AgeBand.years65plus: _BandCut(8, 10),
    },
  ),
  // Duration Pattern Test (% correct per ear); higher = better.
  'dpt': _AgeTestNorm(
    name: 'Duration Pattern Test',
    unit: '%',
    higherIsBetter: true,
    betterMargin: 12,
    citation: 'DPT age norms: Musiek, 1994 '
        '(adult ≥ 73%, child ≥ 60%; UPGRADE_PLAN normative table)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(60, 50),
      AgeBand.years9to10: _BandCut(63, 53),
      AgeBand.years11to12: _BandCut(68, 58),
      AgeBand.years13to17: _BandCut(73, 60),
      AgeBand.years18to50: _BandCut(73, 60),
      AgeBand.years51to65: _BandCut(70, 58),
      AgeBand.years65plus: _BandCut(65, 55),
    },
  ),
  // Frequency Pattern Test (% correct per ear); higher = better.
  'fpt': _AgeTestNorm(
    name: 'Frequency Pattern Test',
    unit: '%',
    higherIsBetter: true,
    betterMargin: 12,
    citation: 'FPT age norms: Musiek, 1994 '
        '(adult ≥ 78%, child ≥ 65%; UPGRADE_PLAN normative table)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(65, 55),
      AgeBand.years9to10: _BandCut(68, 58),
      AgeBand.years11to12: _BandCut(73, 62),
      AgeBand.years13to17: _BandCut(78, 65),
      AgeBand.years18to50: _BandCut(78, 65),
      AgeBand.years51to65: _BandCut(74, 62),
      AgeBand.years65plus: _BandCut(70, 58),
    },
  ),
  // Masking Level Difference (dB); higher = more binaural release from masking.
  'mld': _AgeTestNorm(
    name: 'Masking Level Difference',
    unit: 'dB',
    higherIsBetter: true,
    betterMargin: 3,
    citation: 'MLD age norms: Wilson et al., 2003 '
        '(adult ≥ 10–12 dB, child ≥ 9 dB; UPGRADE_PLAN normative table)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(9, 6),
      AgeBand.years9to10: _BandCut(9, 6),
      AgeBand.years11to12: _BandCut(10, 6),
      AgeBand.years13to17: _BandCut(10, 6),
      AgeBand.years18to50: _BandCut(10, 6),
      AgeBand.years51to65: _BandCut(9, 6),
      AgeBand.years65plus: _BandCut(8, 5),
    },
  ),
  // Dichotic Digits Test (% correct per ear); higher = better.
  'ddt': _AgeTestNorm(
    name: 'Dichotic Digits Test',
    unit: '%',
    higherIsBetter: true,
    betterMargin: 5,
    citation: 'DDT age norms: Musiek, 1983 '
        '(adult ≥ 90%, age 7 ≥ 85%, age 10 ≥ 90%; UPGRADE_PLAN normative table)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(85, 75),
      AgeBand.years9to10: _BandCut(90, 80),
      AgeBand.years11to12: _BandCut(90, 80),
      AgeBand.years13to17: _BandCut(90, 80),
      AgeBand.years18to50: _BandCut(90, 80),
      AgeBand.years51to65: _BandCut(88, 78),
      AgeBand.years65plus: _BandCut(85, 75),
    },
  ),
  // Speech-in-noise SNR-loss (dB); lower = better (less SNR loss).
  'sin': _AgeTestNorm(
    name: 'speech-in-noise SNR-loss',
    unit: 'dB SNR-loss',
    higherIsBetter: false,
    betterMargin: 3,
    citation: 'SNR-loss bands: Killion et al., 2004 '
        '(0–3 dB normal; task-relative, age-adjusted per UPGRADE_PLAN)',
    bands: <AgeBand, _BandCut>{
      AgeBand.years7to8: _BandCut(4, 7),
      AgeBand.years9to10: _BandCut(4, 7),
      AgeBand.years11to12: _BandCut(3.5, 7),
      AgeBand.years13to17: _BandCut(3, 7),
      AgeBand.years18to50: _BandCut(3, 7),
      AgeBand.years51to65: _BandCut(5, 9),
      AgeBand.years65plus: _BandCut(7, 11),
    },
  ),
};

/// Short display text for the "within typical" cut-off of [test] at
/// [ageYears], e.g. `'≤ 6 ms (18–50 years)'`. Presentation sugar only — the
/// banding logic lives in [interpretWithAge] (and its Python mirror); this
/// merely surfaces the same table's cut-off for a report column.
String normSummary({required String test, required int ageYears}) {
  final norm = _ageNorms[test.toLowerCase()];
  if (norm == null) return '—';
  final band = ageBandFor(ageYears);
  final cut = norm.bands[band]!;
  final dir = norm.higherIsBetter ? '≥' : '≤';
  return '$dir ${_fmtNorm(cut.normal)} ${norm.unit} (${band.label})';
}

/// Age-stratified normative interpretation.
///
/// [test] is one of `gin` (gap threshold ms), `dpt` / `fpt` / `ddt`
/// (% correct), `mld` (dB) or `sin` (SNR-loss dB). [ageYears] selects the age
/// band; [value] is the measured result. Returns a [NormResult] (band + plain
/// detail + citation). Unknown tests return an "insufficient" result rather
/// than a fabricated interpretation.
///
/// Research-only and illustrative on uncalibrated audio — never a diagnosis.
NormResult interpretWithAge({
  required String test,
  required int ageYears,
  required double value,
}) {
  final norm = _ageNorms[test.toLowerCase()];
  if (norm == null) {
    return NormResult(
      NormBand.insufficient,
      'No age-stratified reference is available for test "$test". '
          'Supported: gin, dpt, fpt, mld, ddt, sin.',
      '',
    );
  }
  final band = ageBandFor(ageYears);
  final cut = norm.bands[band]!;
  final label = band.label;
  final u = norm.unit;
  final normalStr = '${_fmtNorm(cut.normal)} $u';
  final abnormalStr = '${_fmtNorm(cut.abnormal)} $u';
  final valStr = '${_fmtNorm(value)} $u';

  NormBand resultBand;
  String detail;
  if (norm.higherIsBetter) {
    if (value >= cut.normal + norm.betterMargin) {
      resultBand = NormBand.betterThanTypical;
      detail = '$valStr exceeds the typical $label expectation '
          '(≥ $normalStr) for ${norm.name}.';
    } else if (value >= cut.normal) {
      resultBand = NormBand.withinTypical;
      detail = '$valStr is within the typical $label range '
          '(≥ $normalStr) for ${norm.name}.';
    } else if (value >= cut.abnormal) {
      resultBand = NormBand.slightlyBelowTypical;
      detail = '$valStr is just below the $label cut-off '
          '(≥ $normalStr) for ${norm.name}.';
    } else {
      resultBand = NormBand.belowTypical;
      detail = '$valStr is below the typical $label range '
          '(< $abnormalStr) for ${norm.name}.';
    }
  } else {
    if (value <= cut.normal - norm.betterMargin) {
      resultBand = NormBand.betterThanTypical;
      detail = '$valStr is finer than the typical $label expectation '
          '(≤ $normalStr) for ${norm.name}.';
    } else if (value <= cut.normal) {
      resultBand = NormBand.withinTypical;
      detail = '$valStr is within the typical $label range '
          '(≤ $normalStr) for ${norm.name}.';
    } else if (value <= cut.abnormal) {
      resultBand = NormBand.slightlyBelowTypical;
      detail = '$valStr is just outside the $label cut-off '
          '(≤ $normalStr) for ${norm.name}.';
    } else {
      resultBand = NormBand.belowTypical;
      detail = '$valStr is well outside the typical $label range '
          '(> $abnormalStr) for ${norm.name}.';
    }
  }
  return NormResult(resultBand, detail, norm.citation);
}
