/// Headline-result extraction for completed sessions (pure Dart).
///
/// A staircase session's *accuracy* is deliberately pinned near the rule's
/// target proportion (≈ 70.7% for 2-down/1-up — Levitt, 1971), so accuracy is
/// the WRONG number to report for adaptive tests. This module maps each known
/// session type to its scientifically meaningful headline metric — the
/// engine's reversal-based threshold, per-ear percents, LiSN-S advantage
/// measures, etc. — so on-device history (and everything built on it: report,
/// trends, FHIR export) carries the real result.
///
/// Pure Dart so it can be verified headlessly; adding a session type here is
/// the single place that teaches persistence about its score.
library;

import 'audiogram.dart';
import 'binaural_fusion.dart';
import 'closed_set.dart';
import 'figure_ground.dart';
import 'competing_sentences.dart';
import 'compressed_speech.dart';
import 'dichotic.dart';
import 'dsi.dart';
import 'filtered_speech.dart';
import 'gap_detection.dart';
import 'hint_sin.dart';
import 'interval_task.dart';
import 'lisns.dart';
import 'mci.dart';
import 'mld_test.dart';
import 'modulation_detection.dart';
import 'music_perception.dart';
import 'pattern_test.dart';
import 'psychoacoustics.dart';
import 'protocol_engine.dart';
import 'rgdt.dart';
import 'sequence_entry.dart';
import 'speech_in_noise.dart';
import 'ssw.dart';
import 'tinnitus/residual_inhibition.dart';
import 'training/sentence_closure.dart';

/// The extracted headline result of one completed session.
class SessionMetric {
  const SessionMetric({
    required this.display,
    this.value,
    this.unit,
    this.sub,
    this.trajectory,
    this.trajectoryCorrect,
    this.chanceLevel,
    this.higherIsBetter = true,
  });

  /// Formatted for display, e.g. `'3.2 ms'`, `'−2.0 dB SNR'`, `'L 78% / R 92%'`.
  final String display;

  /// The primary numeric value (threshold, percent, span…), for trends.
  final double? value;

  /// Unit of [value] (`ms`, `dB`, `dB SNR`, `%`, `st`, `digits`…).
  final String? unit;

  /// Named sub-scores (per-ear, per-condition, advantage measures).
  final Map<String, double>? sub;

  /// Adapted-parameter value at each presented trial (staircase trajectory).
  final List<double>? trajectory;

  /// Per-trial correctness aligned with [trajectory].
  final List<bool>? trajectoryCorrect;

  /// The task's guess rate (1/n for an nAFC task, 0 for open-set scoring),
  /// when known — the γ floor for a psychometric-function fit.
  final double? chanceLevel;

  /// Whether a larger [value] means better performance. False for thresholds
  /// and SNR/JND measures (smaller = finer), true for percents/spans/MLD.
  /// Trend views need this to label progress correctly.
  final bool higherIsBetter;
}

/// Formats a number with one decimal, dropping a trailing `.0`.
String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Formats a signed value (`+1.5`, `−2`, `0`).
String _fmtSigned(double v) => '${v > 0 ? '+' : ''}${_fmt(v)}';

/// Extracts the staircase trajectory (parameter at presentation + correctness)
/// from trial records, using [paramKey] in each record's `parameters` map.
(List<double>, List<bool>)? _trajOf(List<TrialRecord> records, String paramKey) {
  final values = <double>[];
  final correct = <bool>[];
  for (final r in records) {
    final v = r.parameters[paramKey];
    if (v is num) {
      values.add(v.toDouble());
      correct.add(r.correct);
    }
  }
  return values.isEmpty ? null : (values, correct);
}

SessionMetric? _adaptive(
  double? threshold,
  String unit,
  List<TrialRecord> records,
  String paramKey, {
  bool signed = false,
  double? chance,
}) {
  final traj = _trajOf(records, paramKey);
  if (threshold == null) {
    // Staircase did not converge (too few reversals): no threshold to report.
    // Keep the trajectory so the report can still plot the partial run.
    return traj == null
        ? null
        : SessionMetric(
            display: 'no threshold',
            trajectory: traj.$1,
            trajectoryCorrect: traj.$2,
            chanceLevel: chance,
            higherIsBetter: false,
          );
  }
  return SessionMetric(
    display: '${signed ? _fmtSigned(threshold) : _fmt(threshold)} $unit',
    value: threshold,
    unit: unit,
    trajectory: traj?.$1,
    trajectoryCorrect: traj?.$2,
    chanceLevel: chance,
    // Every staircase here adapts toward the smallest detectable parameter:
    // a lower threshold is finer performance.
    higherIsBetter: false,
  );
}

SessionMetric _perEar(int leftPercent, int rightPercent, double overall) =>
    SessionMetric(
      display: 'L $leftPercent% / R $rightPercent%',
      value: overall * 100,
      unit: '%',
      sub: <String, double>{
        'left': leftPercent.toDouble(),
        'right': rightPercent.toDouble(),
      },
    );

/// Units for [IntervalTaskSession.paramName] values used across the app.
const Map<String, String> _intervalUnits = <String, String>{
  'delta_db': 'dB',
  'delta_semitones': 'st',
  'delta_ms': 'ms',
  'depth_db': 'dB',
  'gap_ms': 'ms',
  'rate_ratio': '×',
  'tone_level_db': 'dB',
  'itd_us': 'µs',
  'ild_db': 'dB',
  'ripple_period_oct': 'oct',
  'irn_iterations': 'iter',
  'onset_shift_ms': 'ms',
};

/// Extracts persistable (target, response) label pairs from completed trial
/// [records] — the raw material of a REAL confusion matrix. Pairs whose
/// labels are interval choices (`interval_1`…) carry no identity information
/// and are skipped, as are blank/timed-out responses and very long open-set
/// strings. Correct answers are kept (the matrix diagonal). Returns null when
/// nothing usable remains; capped at [maxPairs] to bound record size.
List<List<String>>? confusionPairsOf(
  List<TrialRecord> records, {
  int maxPairs = 60,
}) {
  final pairs = <List<String>>[];
  for (final r in records) {
    final t = r.target.trim(), resp = r.response.trim();
    if (t.isEmpty || resp.isEmpty) continue;
    if (t.startsWith('interval_') || resp.startsWith('interval_')) continue;
    if (t.length > 24 || resp.length > 24) continue; // open-set sentences etc.
    pairs.add(<String>[t, resp]);
    if (pairs.length >= maxPairs) break;
  }
  return pairs.isEmpty ? null : pairs;
}

/// Maps a completed session object to its headline [SessionMetric], or null
/// when the type is unknown (callers fall back to plain accuracy).
SessionMetric? summarizeSession(Object? session) {
  switch (session) {
    case null:
      return null;

    // --- Adaptive threshold tasks (reversal-based threshold, NOT accuracy) ---
    case IntervalTaskSession s:
      return _adaptive(
        s.threshold,
        _intervalUnits[s.paramName] ?? s.paramName,
        s.records,
        s.paramName,
        chance: 1 / s.intervals,
      );
    case GapDetectionSession s:
      // 3AFC (choose the interval containing the gap).
      return _adaptive(s.thresholdGapMs, 'ms', s.records, 'gap_ms',
          chance: 1 / 3);
    case ModulationDetectionSession s:
      // 3AFC (choose the modulated interval).
      return _adaptive(s.thresholdDepthDb, 'dB', s.records, 'depth_db',
          chance: 1 / 3);
    case SpeechInNoiseSession s:
      // 4AFC word-in-noise.
      return _adaptive(s.thresholdSnrDb, 'dB SNR', s.records, 'snr_db',
          signed: true, chance: 1 / 4);
    case HintSinSession s:
      // Open-set typed sentences: no meaningful chance floor.
      return _adaptive(s.srtDb, 'dB SNR', s.records, 'snr_db',
          signed: true, chance: 0);
    case ClosedSetSession s:
      final t = s.thresholdSnrDb;
      if (t != null) {
        return _adaptive(t, 'dB SNR', s.records, 'snr_db', signed: true);
      }
      return SessionMetric(
        display: '${(s.accuracy * 100).round()}%',
        value: s.accuracy * 100,
        unit: '%',
      );

    // --- Per-ear scored tests ---
    case DichoticSession s:
      return _perEar(s.leftPercent, s.rightPercent, s.accuracy);
    case DsiSession s:
      return _perEar(s.leftPercent, s.rightPercent, s.accuracy);
    case PatternSession s:
      return _perEar(s.leftEarPercent, s.rightEarPercent, s.overallAccuracy);
    case CompetingSentenceSession s:
      return _perEar((s.leftAccuracy * 100).round(),
          (s.rightAccuracy * 100).round(), s.accuracy);
    case FilteredSpeechSession s:
      return _perEar(s.leftPercent, s.rightPercent, s.overallAccuracy);

    // --- Condition-structured tests ---
    case SswSession s:
      return SessionMetric(
        display: '${s.totalPercent}%',
        value: s.totalPercent.toDouble(),
        unit: '%',
        sub: <String, double>{
          for (final c in SswCondition.values)
            c.name: s.percent(c).toDouble(),
        },
      );
    case LisnsSession s:
      return SessionMetric(
        display: 'spatial adv ${_fmtSigned(s.spatialAdvantage)} dB',
        value: s.spatialAdvantage,
        unit: 'dB',
        sub: <String, double>{
          'talker': s.talkerAdvantage,
          'spatial': s.spatialAdvantage,
          'total': s.totalAdvantage,
          for (final c in LisnsCondition.values)
            if (s.srtFor(c) != null) 'srt_${c.name}': s.srtFor(c)!,
        },
      );
    case RgdtSession s:
      final t = s.combinedThresholdMs;
      return SessionMetric(
        display: t == null ? 'no threshold' : '${_fmt(t)} ms',
        value: t,
        unit: 'ms',
        sub: <String, double>{
          for (final e in s.perFrequencyThresholds.entries)
            '${e.key.round()}': e.value,
        },
        higherIsBetter: false,
      );
    case MldSession s:
      final mld = s.mldDb;
      return mld == null
          ? null
          : SessionMetric(display: '${_fmt(mld)} dB', value: mld, unit: 'dB');

    case TmtfSession s:
      final mean = s.meanThresholdDb;
      final measured = <double>[
        for (final r in s.rates)
          if (s.thresholdFor(r) != null) r,
      ];
      return SessionMetric(
        display: mean == null
            ? 'no threshold'
            : 'TMTF mean ${_fmt(mean)} dB (${measured.length} rates)',
        value: mean,
        unit: 'dB',
        sub: <String, double>{
          for (final r in s.rates)
            if (s.thresholdFor(r) != null)
              'r${r.round()}': s.thresholdFor(r)!,
        },
        // More negative depth thresholds = finer envelope sensitivity.
        higherIsBetter: false,
      );

    case BeatTapSession s:
      final sd = s.sdAsynchronyMs;
      return SessionMetric(
        display: sd == null ? 'too few taps' : 'SD ±${_fmt(sd)} ms',
        value: sd,
        unit: 'ms',
        sub: <String, double>{
          if (s.meanAsynchronyMs != null)
            'mean_async': s.meanAsynchronyMs!,
          'hit_pct': s.hitRate * 100,
          if (s.tempoRatio != null) 'tempo_ratio': s.tempoRatio!,
        },
        // A smaller asynchrony SD = steadier tapping.
        higherIsBetter: false,
      );

    case FigureGroundSession s:
      final p8 = s.percentFor(8), p0 = s.percentFor(0), m8 = s.percentFor(-8);
      String pf(double? v) => v == null ? '—' : '${v.round()}%';
      return SessionMetric(
        display: '+8: ${pf(p8)} · 0: ${pf(p0)} · −8: ${pf(m8)}',
        value: s.accuracy * 100,
        unit: '%',
        sub: <String, double>{
          if (p8 != null) 'snr_p8': p8,
          if (p0 != null) 'snr_0': p0,
          if (m8 != null) 'snr_m8': m8,
        },
      );

    case AudiogramSession s:
      final ptaR = s.ptaFor('right'), ptaL = s.ptaFor('left');
      final ptas = <double>[if (ptaR != null) ptaR, if (ptaL != null) ptaL];
      return SessionMetric(
        display: ptas.isEmpty
            ? 'incomplete'
            : 'PTA R ${ptaR == null ? '—' : _fmt(ptaR)} / '
                'L ${ptaL == null ? '—' : _fmt(ptaL)} dBFS',
        value: ptas.isEmpty
            ? null
            : ptas.reduce((a, b) => a + b) / ptas.length,
        unit: 'dBFS',
        sub: <String, double>{
          for (final ear in const [('right', 'R'), ('left', 'L')])
            for (final f in kAudiogramFrequencies)
              if (s.thresholdFor(ear.$1, f) != null)
                '${ear.$2}${f.round()}': s.thresholdFor(ear.$1, f)!,
          if (ptaR != null) 'pta_right': ptaR,
          if (ptaL != null) 'pta_left': ptaL,
          if (s.catchTrials > 0) 'false_alarm_pct': s.falseAlarmRate * 100,
        },
        // Lower (more negative) dBFS = a quieter tone detected = finer.
        higherIsBetter: false,
      );

    // --- Simple percent / span tests ---
    case BinauralFusionSession s:
      return SessionMetric(
          display: '${s.percent}%', value: s.percent.toDouble(), unit: '%');
    case CompressedSpeechSession s:
      return SessionMetric(
          display: '${s.percent}%', value: s.percent.toDouble(), unit: '%');
    case MciSession s:
      return SessionMetric(
        display: '${(s.accuracy * 100).round()}%',
        value: s.accuracy * 100,
        unit: '%',
      );
    case SequenceEntrySession s:
      return SessionMetric(
        display: '${s.maxSpan} digits',
        value: s.maxSpan.toDouble(),
        unit: 'digits',
      );
    case ResidualInhibitionSession s:
      return SessionMetric(
        display: s.depth == null
            ? 'no report'
            : s.positive
                ? 'RI ${s.depth!.name}'
                    '${s.returnSeconds == null ? '' : ' ${s.returnSeconds!.round()} s'}'
                : 'no RI',
        value: s.returnSeconds,
        unit: 's',
        sub: <String, double>{
          'masker_db': s.maskerDb,
          'positive': s.positive ? 1 : 0,
        },
      );

    case SentenceClosureSession s:
      final traj = _trajOf(s.records, 'choices');
      return SessionMetric(
        display:
            '${(s.accuracy * 100).round()}% (up to ${s.maxChoicesReached} '
            'choices)',
        value: s.accuracy * 100,
        unit: '%',
        sub: <String, double>{
          'max_choices': s.maxChoicesReached.toDouble(),
        },
        trajectory: traj?.$1,
        trajectoryCorrect: traj?.$2,
      );
  }
  return null;
}
