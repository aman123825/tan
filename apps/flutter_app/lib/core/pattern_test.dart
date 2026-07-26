import 'dart:math';

import 'protocol_engine.dart';

/// How the listener reports a pattern.
///
///  * [labels] — classic linguistic labeling: choose "High–Low–High" etc.
///    from the 6-choice grid.
///  * [humBack] — the Buffalo/Musiek hummed-response condition: the listener
///    hums the pattern back aloud, then the sequence is revealed/replayed and
///    the reproduction is scored as matched / not matched (self- or
///    helper-scored here; examiner-scored clinically). Humming removes the
///    linguistic-labeling load, so intact humming with poor labeling points
///    to interhemispheric-transfer rather than pattern-perception deficits
///    (Musiek, Pinheiro & Wilson, 1980).
enum PatternResponseMode { labels, humBack }

/// A temporal pattern sequence (3 elements) for DPT or FPT.
class PatternTrial {
  const PatternTrial(this.pattern, this.ear);

  /// 3-character string: 'L'=long/low, 'S'=short/high. E.g. "LSL", "SLL".
  final String pattern;

  /// Which ear is being tested: 'left' or 'right'.
  final String ear;

  /// Human-readable label for this pattern.
  String get label => pattern.split('').map((c) => c == 'L' ? 'Long' : 'Short').join('–');
}

/// All valid 3-element patterns (excluding monotone LLL and SSS which are
/// not used clinically — Musiek 1994 uses only the 6 patterns with at least
/// one change).
const List<String> kDptPatterns = [
  'LLS', 'LSL', 'SLL', 'LSS', 'SLS', 'SSL',
];

const List<String> kFptPatterns = [
  'HHL', 'HLH', 'LHH', 'HLL', 'LHL', 'LLH',
];

/// Generates DPT or FPT trials in a randomized order.
class PatternGenerator {
  PatternGenerator({
    required this.patterns,
    required this.trialsPerEar,
    int seed = 0,
  }) : _rng = Random(seed);

  final List<String> patterns;
  final int trialsPerEar;
  final Random _rng;

  int _count = 0;

  /// Total trials = trialsPerEar * 2 (left + right).
  int get totalTrials => trialsPerEar * 2;

  bool get isComplete => _count >= totalTrials;

  PatternTrial next() {
    final ear = _count < trialsPerEar ? 'right' : 'left';
    final pattern = patterns[_rng.nextInt(patterns.length)];
    _count++;
    return PatternTrial(pattern, ear);
  }
}

/// Tracks a DPT or FPT session — stores responses, computes per-ear accuracy.
class PatternSession {
  PatternSession({
    required this.moduleId,
    required this.groupId,
    required this.testName,
    required this.trialsPerEar,
    this.responseMode = PatternResponseMode.labels,
  });

  final String moduleId;
  final String groupId;
  final String testName;
  final int trialsPerEar;
  final PatternResponseMode responseMode;

  final List<_PatternResult> _results = [];

  /// Per-trial event records for persistence/export (target = the presented
  /// pattern; response = the chosen pattern, or `hum-match`/`hum-mismatch`
  /// in hummed mode).
  final List<TrialRecord> records = <TrialRecord>[];

  int get completedTrials => _results.length;
  int get trialNumber => _results.length + 1;
  int get totalTrials => trialsPerEar * 2;
  bool get isComplete => _results.length >= totalTrials;

  void _record(PatternTrial trial, String chosen, bool correct, int latencyMs) {
    _results.add(_PatternResult(
      trial: trial,
      chosen: chosen,
      correct: correct,
      latencyMs: latencyMs,
    ));
    records.add(TrialRecord(
      target: trial.pattern,
      response: chosen,
      correct: correct,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'ear': trial.ear,
        'response_mode': responseMode.name,
      },
    ));
  }

  /// Submit a labeled response. Returns true if correct.
  bool submit(PatternTrial trial, String chosenPattern, {int latencyMs = 0}) {
    final correct = chosenPattern == trial.pattern;
    _record(trial, chosenPattern, correct, latencyMs);
    return correct;
  }

  /// Submit a hummed-response score: whether the reproduction [matched] the
  /// revealed pattern (self-/helper-scored). Returns [matched].
  bool submitHum(PatternTrial trial, {required bool matched, int latencyMs = 0}) {
    _record(trial, matched ? 'hum-match' : 'hum-mismatch', matched, latencyMs);
    return matched;
  }

  /// Accuracy for a specific ear (0.0–1.0).
  double accuracyForEar(String ear) {
    final earResults = _results.where((r) => r.trial.ear == ear);
    if (earResults.isEmpty) return 0;
    return earResults.where((r) => r.correct).length / earResults.length;
  }

  double get rightEarAccuracy => accuracyForEar('right');
  double get leftEarAccuracy => accuracyForEar('left');
  double get overallAccuracy {
    if (_results.isEmpty) return 0;
    return _results.where((r) => r.correct).length / _results.length;
  }

  /// Percent correct per ear (for norm comparison).
  int get rightEarPercent => (rightEarAccuracy * 100).round();
  int get leftEarPercent => (leftEarAccuracy * 100).round();
}

class _PatternResult {
  const _PatternResult({
    required this.trial,
    required this.chosen,
    required this.correct,
    required this.latencyMs,
  });

  final PatternTrial trial;
  final String chosen;
  final bool correct;
  final int latencyMs;
}

/// Age-stratified norms for DPT and FPT (Musiek 1994; various sources).
class PatternNorms {
  /// Returns the minimum % correct considered normal for the given age and test.
  static int normalCutoff({required String test, required int ageYears}) {
    if (test == 'dpt') {
      if (ageYears <= 8) return 50;
      if (ageYears <= 10) return 55;
      if (ageYears <= 12) return 60;
      if (ageYears <= 17) return 67;
      if (ageYears <= 50) return 73;
      if (ageYears <= 65) return 70;
      return 65; // 65+
    } else {
      // FPT
      if (ageYears <= 8) return 55;
      if (ageYears <= 10) return 60;
      if (ageYears <= 12) return 65;
      if (ageYears <= 17) return 72;
      if (ageYears <= 50) return 78;
      if (ageYears <= 65) return 73;
      return 68; // 65+
    }
  }

  /// Interpret a percent-correct score.
  static String interpret({
    required String test,
    required int ageYears,
    required int percentCorrect,
  }) {
    final cutoff = normalCutoff(test: test, ageYears: ageYears);
    if (percentCorrect >= cutoff + 10) return 'normal';
    if (percentCorrect >= cutoff) return 'borderline';
    if (percentCorrect >= cutoff - 15) return 'below normal';
    return 'significantly below normal';
  }
}
