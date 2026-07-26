/// Builds the CAPD report from real on-device session history.
///
/// Turns [SessionRecord]s (which carry each session's headline metric — see
/// `core/session_summary.dart`) into [ReportTest] rows, a [NarrativeInput] for
/// the rule-based narrative, and the most recent staircase trajectory for the
/// trajectory plot. The latest session per test is used. Where a published
/// reference exists the row is banded through `core/norms.dart`; tests without
/// a defensible reference are included as "Recorded" (no status is invented).
///
/// Research summaries on uncalibrated audio — never a diagnosis.
library;

import '../../core/confusion_matrix.dart';
import '../../core/narrative_report.dart';
import '../../core/norms.dart';
import '../../data/session_history.dart';
import 'enhanced_report_page.dart';

/// Everything the report page needs, built from real history.
class ReportData {
  const ReportData({
    required this.tests,
    required this.narrative,
    required this.sessionCount,
    this.staircase,
    this.confusionMatrix,
    this.confusionSessionCount = 0,
  });

  final List<ReportTest> tests;
  final NarrativeInput narrative;
  final int sessionCount;
  final StaircaseRun? staircase;

  /// REAL aggregated response confusions across stored sessions (null when no
  /// session carries confusion pairs — the report then omits the section).
  final ConfusionMatrix? confusionMatrix;

  /// Number of sessions contributing to [confusionMatrix].
  final int confusionSessionCount;
}

/// Aggregates the persisted per-trial (target, response) pairs of [history]
/// into one confusion matrix. Returns the matrix and the number of
/// contributing sessions; (null, 0) when no session carries pairs.
(ConfusionMatrix?, int) aggregateConfusions(List<SessionRecord> history) {
  final m = ConfusionMatrix();
  var sessions = 0;
  for (final r in history) {
    final pairs = r.confusions;
    if (pairs == null || pairs.isEmpty) continue;
    sessions++;
    for (final p in pairs) {
      if (p.length < 2) continue;
      m.record(p[0], p[1]);
    }
  }
  return m.total == 0 ? (null, 0) : (m, sessions);
}

/// Indices where the trajectory's direction of change flips (display markers;
/// the engine's own reversal bookkeeping is what produced the threshold).
List<int> reversalIndicesOf(List<double> values) {
  final out = <int>[];
  var lastSign = 0;
  for (var i = 1; i < values.length; i++) {
    final d = values[i] - values[i - 1];
    if (d == 0) continue;
    final sign = d > 0 ? 1 : -1;
    if (lastSign != 0 && sign != lastSign) out.add(i - 1);
    lastSign = sign;
  }
  return out;
}

ReportStatus _statusOf(NormBand band) => switch (band) {
      NormBand.betterThanTypical => ReportStatus.normal,
      NormBand.withinTypical => ReportStatus.normal,
      NormBand.slightlyBelowTypical => ReportStatus.borderline,
      NormBand.belowTypical => ReportStatus.below,
      NormBand.insufficient => ReportStatus.info,
    };

/// Task-relative percent banding for tests without a published age norm here.
ReportStatus _percentStatus(double pct,
    {required double normal, required double below}) {
  if (pct >= normal) return ReportStatus.normal;
  if (pct >= below) return ReportStatus.borderline;
  return ReportStatus.below;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// The most recent record per group id, newest history first.
Map<String, SessionRecord> latestPerGroup(List<SessionRecord> history) {
  final latest = <String, SessionRecord>{};
  for (final r in history) {
    // History is stored most-recent first; keep the first per group.
    latest.putIfAbsent(r.groupId, () => r);
  }
  return latest;
}

/// Builds report data from history, or null when there is nothing to report.
ReportData? buildReportData(List<SessionRecord> history, {int ageYears = 30}) {
  if (history.isEmpty) return null;
  final latest = latestPerGroup(history);
  final tests = <ReportTest>[];

  void addAged({
    required SessionRecord r,
    required String name,
    required String normKey,
    required double value,
    required String score,
    String ear = 'Both',
    BuffaloProfile? profile,
  }) {
    final res = interpretWithAge(test: normKey, ageYears: ageYears, value: value);
    tests.add(ReportTest(
      name: name,
      score: score,
      norm: normSummary(test: normKey, ageYears: ageYears),
      status: _statusOf(res.band),
      ear: ear,
      profile: profile,
    ));
  }

  void addPerEarAged(SessionRecord r, String name, String normKey,
      BuffaloProfile profile) {
    final sub = r.subScores;
    if (sub == null || (!sub.containsKey('left') && !sub.containsKey('right'))) {
      if (r.metricValue != null) {
        addAged(
            r: r,
            name: name,
            normKey: normKey,
            value: r.metricValue!,
            score: r.metric ?? '${_fmt(r.metricValue!)}%',
            profile: profile);
      }
      return;
    }
    for (final entry in const [('left', 'Left'), ('right', 'Right')]) {
      final v = sub[entry.$1];
      if (v == null) continue;
      addAged(
        r: r,
        name: '$name — ${entry.$2}',
        normKey: normKey,
        value: v,
        score: '${_fmt(v)}%',
        ear: entry.$2,
        profile: profile,
      );
    }
  }

  void addPercent({
    required SessionRecord r,
    required String name,
    required double normal,
    required double below,
    required String normText,
    BuffaloProfile? profile,
  }) {
    final pct = r.metricValue ?? r.accuracy * 100;
    tests.add(ReportTest(
      name: name,
      score: r.metric ?? '${pct.round()}%',
      norm: normText,
      status: _percentStatus(pct, normal: normal, below: below),
      ear: 'Both',
      profile: profile,
    ));
  }

  // --- Temporal resolution ---
  final gap = latest['gap'];
  final rgdt = latest['random_gap_detection'];
  final ginRecord = gap ?? rgdt;
  if (gap?.metricValue != null) {
    addAged(
        r: gap!,
        name: 'Gap Detection',
        normKey: 'gin',
        value: gap.metricValue!,
        score: gap.metric!,
        profile: BuffaloProfile.auditoryDecoding);
  }
  if (rgdt?.metricValue != null) {
    addAged(
        r: rgdt!,
        name: 'Random Gap Detection (RGDT)',
        normKey: 'gin',
        value: rgdt.metricValue!,
        score: rgdt.metric!,
        profile: BuffaloProfile.auditoryDecoding);
  }

  // --- Temporal patterning ---
  final dpt = latest['duration_pattern'];
  if (dpt != null) {
    addPerEarAged(dpt, 'Duration Pattern Test', 'dpt', BuffaloProfile.prosodic);
  }
  final fpt = latest['frequency_pattern'];
  if (fpt != null) {
    addPerEarAged(fpt, 'Frequency Pattern Test', 'fpt', BuffaloProfile.prosodic);
  }

  // --- Binaural interaction ---
  final mld = latest['masking_level_difference'];
  if (mld?.metricValue != null) {
    addAged(
        r: mld!,
        name: 'Masking Level Difference',
        normKey: 'mld',
        value: mld.metricValue!,
        score: mld.metric!,
        profile: BuffaloProfile.integration);
  }
  final fusion = latest['binaural_fusion'];
  if (fusion != null) {
    addPercent(
        r: fusion,
        name: 'Binaural Fusion',
        normal: 70,
        below: 60,
        normText: '≥ 70% (task-relative)',
        profile: BuffaloProfile.integration);
  }

  // --- Dichotic listening ---
  final ddt = latest['dichotic_digits'];
  if (ddt != null) {
    addPerEarAged(ddt, 'Dichotic Digits', 'ddt', BuffaloProfile.integration);
  }
  final dsi = latest['dsi'];
  if (dsi != null) {
    addPerEarAged(dsi, 'Dichotic Sentence Identification', 'ddt',
        BuffaloProfile.integration);
  }
  final ssw = latest['ssw'];
  if (ssw?.metricValue != null) {
    addPercent(
        r: ssw!,
        name: 'Staggered Spondaic Words',
        normal: 90,
        below: 80,
        normText: 'cf. ≥ 90% (task-relative)',
        profile: BuffaloProfile.integration);
  }
  final cst = latest['competing_sentences'];
  if (cst != null) {
    addPerEarAged(cst, 'Competing Sentences', 'ddt', BuffaloProfile.integration);
  }

  // --- Speech in noise / degraded speech ---
  for (final entry in const [
    ('sentence_noise', 'Sentences in Noise (SNR)'),
    ('word', 'Words in Noise (SNR)'),
    ('hint_sentences', 'HINT Sentences (SRT)'),
  ]) {
    final r = latest[entry.$1];
    if (r?.metricValue != null && r!.metricUnit == 'dB SNR') {
      addAged(
          r: r,
          name: entry.$2,
          normKey: 'sin',
          value: r.metricValue!,
          score: r.metric!,
          profile: BuffaloProfile.toleranceFadingMemory);
    }
  }
  final filtered = latest['filtered_speech'];
  if (filtered != null) {
    addPercent(
        r: filtered,
        name: 'Low-pass Filtered Speech',
        normal: 70,
        below: 60,
        normText: '≥ 70% (task-relative)',
        profile: BuffaloProfile.auditoryDecoding);
  }
  final compressed = latest['compressed_speech'];
  if (compressed != null) {
    addPercent(
        r: compressed,
        name: 'Time-compressed Speech',
        normal: 75,
        below: 60,
        normText: '≥ 75% (task-relative)',
        profile: BuffaloProfile.auditoryDecoding);
  }

  // --- Spatial processing (LiSN-S style advantages) ---
  final lisn = latest['lisn_s'];
  if (lisn?.subScores != null) {
    final sub = lisn!.subScores!;
    final spatial = sub['spatial'];
    if (spatial != null) {
      tests.add(ReportTest(
        name: 'LiSN-S Spatial Advantage',
        score: '${spatial >= 0 ? '+' : ''}${_fmt(spatial)} dB',
        norm: 'cf. Cameron & Dillon, 2007 (task-relative)',
        status: spatial >= 8
            ? ReportStatus.normal
            : spatial >= 5
                ? ReportStatus.borderline
                : ReportStatus.below,
        ear: 'Both',
        profile: BuffaloProfile.integration,
      ));
    }
    final talker = sub['talker'];
    if (talker != null) {
      tests.add(ReportTest(
        name: 'LiSN-S Talker Advantage',
        score: '${talker >= 0 ? '+' : ''}${_fmt(talker)} dB',
        norm: 'cf. Cameron & Dillon, 2007 (task-relative)',
        status: talker >= 3
            ? ReportStatus.normal
            : talker >= 1
                ? ReportStatus.borderline
                : ReportStatus.below,
        ear: 'Both',
        profile: BuffaloProfile.integration,
      ));
    }
  }

  // --- Auditory memory ---
  final span = latest['digit_span'];
  if (span?.metricValue != null) {
    final s = span!.metricValue!;
    tests.add(ReportTest(
      name: 'Digit Span (forward)',
      score: span.metric ?? '${s.round()} digits',
      norm: '≥ 6 digits',
      status: s >= 6
          ? ReportStatus.normal
          : s >= 5
              ? ReportStatus.borderline
              : ReportStatus.below,
      ear: '—',
      profile: BuffaloProfile.toleranceFadingMemory,
    ));
  }

  // --- Psychoacoustic thresholds with adult reference bands ---
  final jnd = latest['frequency_jnd'];
  if (jnd?.metricValue != null) {
    final res = Norms.frequencySemitones(jnd!.metricValue);
    tests.add(ReportTest(
      name: 'Frequency Discrimination (JND)',
      score: jnd.metric!,
      norm: '≈ ≤ 1 st (task-relative)',
      status: _statusOf(res.band),
      ear: 'Both',
      profile: BuffaloProfile.prosodic,
    ));
  }
  final mod = latest['modulation_depth'];
  if (mod?.metricValue != null) {
    final res = Norms.amDepthDb(mod!.metricValue);
    tests.add(ReportTest(
      name: 'Modulation Detection',
      score: mod.metric!,
      norm: '≈ ≤ −12 dB (task-relative)',
      status: _statusOf(res.band),
      ear: 'Both',
      profile: BuffaloProfile.auditoryDecoding,
    ));
  }

  // --- Everything else measured: recorded, no invented status ---
  const handled = <String>{
    'gap', 'random_gap_detection', 'duration_pattern', 'frequency_pattern',
    'masking_level_difference', 'binaural_fusion', 'dichotic_digits', 'dsi',
    'ssw', 'competing_sentences', 'sentence_noise', 'word', 'hint_sentences',
    'filtered_speech', 'compressed_speech', 'lisn_s', 'digit_span',
    'frequency_jnd', 'modulation_depth',
  };
  for (final e in latest.entries) {
    if (handled.contains(e.key)) continue;
    final r = e.value;
    tests.add(ReportTest(
      name: r.title,
      score: r.metric ?? '${(r.accuracy * 100).round()}%',
      norm: '—',
      status: ReportStatus.info,
      ear: '—',
    ));
  }

  // --- Narrative input from the same latest results ---
  final narrative = NarrativeInput(
    ageYears: ageYears,
    ginMs: ginRecord?.metricValue,
    dptRightPct: dpt?.subScores?['right'],
    dptLeftPct: dpt?.subScores?['left'],
    fptPct: fpt?.metricValue,
    mldDb: mld?.metricValue,
    sinSnrDb: latest['sentence_noise']?.metricValue ??
        latest['word']?.metricValue ??
        latest['hint_sentences']?.metricValue,
    ddtRightPct: ddt?.subScores?['right'],
    ddtLeftPct: ddt?.subScores?['left'],
    digitSpan: span?.metricValue?.round(),
  );

  // --- Most recent staircase trajectory for the plot ---
  StaircaseRun? staircase;
  for (final r in history) {
    final traj = r.trajectory;
    if (traj != null && traj.length >= 4) {
      staircase = StaircaseRun(
        title: '${r.title} staircase (latest run)',
        values: traj,
        reversalIndices: reversalIndicesOf(traj),
        unit: r.metricUnit ?? '',
        threshold: r.metricValue,
        correct: r.trajectoryCorrect,
        chanceLevel: r.chanceLevel,
      );
      break;
    }
  }

  final (confusionMatrix, confusionSessions) = aggregateConfusions(history);

  return ReportData(
    tests: tests,
    narrative: narrative,
    sessionCount: history.length,
    staircase: staircase,
    confusionMatrix: confusionMatrix,
    confusionSessionCount: confusionSessions,
  );
}
