/// Auto-generated narrative report (pure Dart, Flutter-free).
///
/// Turns a set of measured test results into a plain-language paragraph by
/// rule — NOT AI. Each domain (temporal processing, binaural interaction,
/// speech-in-noise, dichotic listening, auditory memory) is compared with
/// age-referenced bands via [interpretWithAge], phrased as a sentence, then a
/// Buffalo-style profile and recommendations are appended, e.g.:
///
///   "Temporal processing is below age norms (GIN 8 ms, DPT 55% RE / 60% LE).
///    Binaural interaction is within normal limits (MLD 12 dB). Speech-in-noise
///    performance is mildly impaired (SRT +2 dB). Profile: Auditory Decoding
///    deficit. Recommended: phonemic training, FM system in classroom,
///    preferential seating."
///
/// This is a research summary, not a clinical diagnosis.
library;

import 'norms.dart';

/// The measured inputs for a narrative report. All test values are optional;
/// only provided domains are described.
class NarrativeInput {
  const NarrativeInput({
    this.ageYears = 30,
    this.ginMs,
    this.dptRightPct,
    this.dptLeftPct,
    this.fptPct,
    this.mldDb,
    this.sinSnrDb,
    this.ddtRightPct,
    this.ddtLeftPct,
    this.digitSpan,
  });

  final int ageYears;

  /// Gaps-in-noise threshold (ms; lower is better).
  final double? ginMs;

  /// Duration-pattern-test scores per ear (%).
  final double? dptRightPct;
  final double? dptLeftPct;

  /// Frequency-pattern-test score (%).
  final double? fptPct;

  /// Masking-level difference (dB; higher is better).
  final double? mldDb;

  /// Speech-in-noise SRT / SNR-50 (dB; lower is better).
  final double? sinSnrDb;

  /// Dichotic-digits scores per ear (%).
  final double? ddtRightPct;
  final double? ddtLeftPct;

  /// Forward digit span (digits).
  final int? digitSpan;
}

/// The Buffalo-style profiles the narrative can assign.
enum NarrativeProfile {
  auditoryDecoding,
  integration,
  toleranceFadingMemory,
  prosodic,
  withinNormalLimits,
}

extension NarrativeProfileInfo on NarrativeProfile {
  String get title => switch (this) {
        NarrativeProfile.auditoryDecoding => 'Auditory Decoding',
        NarrativeProfile.integration => 'Integration',
        NarrativeProfile.toleranceFadingMemory => 'Tolerance-Fading Memory',
        NarrativeProfile.prosodic => 'Prosodic',
        NarrativeProfile.withinNormalLimits => 'Within Normal Limits',
      };
}

/// The structured output of the generator.
class NarrativeReport {
  const NarrativeReport({
    required this.domainSentences,
    required this.profile,
    required this.recommendations,
  });

  /// One sentence per described domain.
  final List<String> domainSentences;
  final NarrativeProfile profile;
  final List<String> recommendations;

  /// The full narrative paragraph (domains + profile + recommendations).
  String get paragraph {
    final b = StringBuffer(domainSentences.join(' '));
    if (domainSentences.isNotEmpty) b.write(' ');
    if (profile == NarrativeProfile.withinNormalLimits) {
      b.write('Profile: all tested domains within normal limits.');
    } else {
      b.write('Profile: ${profile.title} deficit.');
    }
    if (recommendations.isNotEmpty) {
      b.write(' Recommended: ${recommendations.join(', ')}.');
    }
    return b.toString();
  }
}

/// Rank a band by severity (higher = worse); insufficient is ignored (-1).
int _severity(NormBand band) => switch (band) {
      NormBand.betterThanTypical => 0,
      NormBand.withinTypical => 1,
      NormBand.slightlyBelowTypical => 2,
      NormBand.belowTypical => 3,
      NormBand.insufficient => -1,
    };

/// A plain-language verdict phrase for a band.
String _verdict(NormBand band) => switch (band) {
      NormBand.betterThanTypical => 'within normal limits',
      NormBand.withinTypical => 'within normal limits',
      NormBand.slightlyBelowTypical => 'mildly impaired',
      NormBand.belowTypical => 'below age norms',
      NormBand.insufficient => 'not assessed',
    };

/// The worst (most severe) band among a set of measured values for one domain,
/// or null if none were provided.
NormBand? _worstBand(int ageYears, String test, List<double?> values) {
  NormBand? worst;
  for (final v in values) {
    if (v == null) continue;
    final band = interpretWithAge(test: test, ageYears: ageYears, value: v).band;
    if (band == NormBand.insufficient) continue;
    if (worst == null || _severity(band) > _severity(worst)) worst = band;
  }
  return worst;
}

bool _affected(NormBand? b) =>
    b == NormBand.slightlyBelowTypical || b == NormBand.belowTypical;

String _fmtSigned(double v) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}';

/// Generates a rule-based [NarrativeReport] from [input].
NarrativeReport generateNarrativeReport(NarrativeInput input) {
  final age = input.ageYears;
  final sentences = <String>[];

  // --- Temporal processing (GIN + DPT + FPT) ---
  final temporalBand = _worstBand(age, 'gin', [input.ginMs]) == null &&
          input.dptRightPct == null &&
          input.dptLeftPct == null &&
          input.fptPct == null
      ? null
      : _worstOfSeveral(age, [
          ('gin', input.ginMs),
          ('dpt', input.dptRightPct),
          ('dpt', input.dptLeftPct),
          ('fpt', input.fptPct),
        ]);
  if (temporalBand != null) {
    final details = <String>[];
    if (input.ginMs != null) {
      details.add('GIN ${input.ginMs!.toStringAsFixed(
          input.ginMs!.truncateToDouble() == input.ginMs! ? 0 : 1)} ms');
    }
    if (input.dptRightPct != null || input.dptLeftPct != null) {
      final parts = <String>[];
      if (input.dptRightPct != null) {
        parts.add('${input.dptRightPct!.round()}% RE');
      }
      if (input.dptLeftPct != null) {
        parts.add('${input.dptLeftPct!.round()}% LE');
      }
      details.add('DPT ${parts.join(' / ')}');
    }
    if (input.fptPct != null) details.add('FPT ${input.fptPct!.round()}%');
    sentences.add('Temporal processing is ${_verdict(temporalBand)}'
        '${details.isEmpty ? '' : ' (${details.join(', ')})'}.');
  }

  // --- Binaural interaction (MLD) ---
  final mldBand = _worstBand(age, 'mld', [input.mldDb]);
  if (mldBand != null) {
    sentences.add('Binaural interaction is ${_verdict(mldBand)} '
        '(MLD ${input.mldDb!.toStringAsFixed(
            input.mldDb!.truncateToDouble() == input.mldDb! ? 0 : 1)} dB).');
  }

  // --- Speech-in-noise (SIN / SRT) ---
  final sinBand = _worstBand(age, 'sin', [input.sinSnrDb]);
  if (sinBand != null) {
    sentences.add('Speech-in-noise performance is ${_verdict(sinBand)} '
        '(SRT ${_fmtSigned(input.sinSnrDb!)} dB).');
  }

  // --- Dichotic listening (DDT) ---
  final ddtBand = _worstBand(age, 'ddt', [input.ddtRightPct, input.ddtLeftPct]);
  if (ddtBand != null) {
    final parts = <String>[];
    if (input.ddtRightPct != null) {
      parts.add('${input.ddtRightPct!.round()}% RE');
    }
    if (input.ddtLeftPct != null) parts.add('${input.ddtLeftPct!.round()}% LE');
    sentences.add('Dichotic listening is ${_verdict(ddtBand)} '
        '(DDT ${parts.join(' / ')}).');
  }

  // --- Auditory memory (digit span; simple rule, no published norm key) ---
  NormBand? memoryBand;
  if (input.digitSpan != null) {
    final s = input.digitSpan!;
    memoryBand = s >= 6
        ? NormBand.withinTypical
        : s >= 5
            ? NormBand.slightlyBelowTypical
            : NormBand.belowTypical;
    sentences.add('Auditory memory is ${_verdict(memoryBand)} '
        '(digit span $s).');
  }

  // --- Profile classification (priority order) ---
  final profiles = <NarrativeProfile>{};
  if (_affected(temporalBand) || _affected(sinBand)) {
    profiles.add(NarrativeProfile.auditoryDecoding);
  }
  if (_affected(ddtBand) || _affected(mldBand)) {
    profiles.add(NarrativeProfile.integration);
  }
  if (_affected(memoryBand)) {
    profiles.add(NarrativeProfile.toleranceFadingMemory);
  }
  // A pattern-test-only weakness (DPT/FPT) with normal decoding hints prosodic.
  final prosodicOnly = (input.dptRightPct != null ||
          input.dptLeftPct != null ||
          input.fptPct != null) &&
      _affected(temporalBand) &&
      input.ginMs != null &&
      !_affected(_worstBand(age, 'gin', [input.ginMs]));
  if (prosodicOnly) profiles.add(NarrativeProfile.prosodic);

  const priority = <NarrativeProfile>[
    NarrativeProfile.auditoryDecoding,
    NarrativeProfile.integration,
    NarrativeProfile.toleranceFadingMemory,
    NarrativeProfile.prosodic,
  ];
  NarrativeProfile primary = NarrativeProfile.withinNormalLimits;
  for (final p in priority) {
    if (profiles.contains(p)) {
      primary = p;
      break;
    }
  }

  return NarrativeReport(
    domainSentences: sentences,
    profile: primary,
    recommendations: _recommendationsFor(profiles),
  );
}

/// Worst band across several (test, value) pairs.
NormBand? _worstOfSeveral(
    int ageYears, List<(String, double?)> tests) {
  NormBand? worst;
  for (final (test, value) in tests) {
    if (value == null) continue;
    final band =
        interpretWithAge(test: test, ageYears: ageYears, value: value).band;
    if (band == NormBand.insufficient) continue;
    if (worst == null || _severity(band) > _severity(worst)) worst = band;
  }
  return worst;
}

List<String> _recommendationsFor(Set<NarrativeProfile> profiles) {
  final recs = <String>[];
  if (profiles.contains(NarrativeProfile.auditoryDecoding)) {
    recs.addAll(const [
      'phonemic training',
      'FM system in classroom',
      'preferential seating',
    ]);
  }
  if (profiles.contains(NarrativeProfile.integration)) {
    recs.add('dichotic / binaural-integration training');
  }
  if (profiles.contains(NarrativeProfile.toleranceFadingMemory)) {
    recs.add('working-memory and sequencing practice');
  }
  if (profiles.contains(NarrativeProfile.prosodic)) {
    recs.add('prosody and temporal-patterning practice');
  }
  if (profiles.isNotEmpty) {
    recs.add('referral to a qualified audiologist for a calibrated assessment');
  }
  return recs;
}
