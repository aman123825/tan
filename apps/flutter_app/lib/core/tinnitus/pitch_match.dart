/// Tinnitus pitch-matching by 2AFC binary search (pure Dart).
///
/// The listener hears two tones and picks the one *closer to their tinnitus*.
/// The search range is halved (in log-frequency space) toward the chosen side
/// each trial, converging on a matched frequency in ~10–18 trials over the
/// 125 Hz – 16 kHz range (≈ 7 octaves).
///
/// This is a subjective self-report matching aid for research/education — it is
/// not a diagnosis and does not change master volume. Flutter-free so it can be
/// unit-tested headlessly.
library;

import 'dart:math' as math;

import '../protocol_engine.dart';

/// Geometric mean of two positive frequencies (midpoint in log space).
double geoMean(double a, double b) => math.sqrt(a * b);

/// Sequences a binary-search tinnitus pitch match.
class PitchMatchSession {
  PitchMatchSession({
    this.moduleId = 'tinnitus',
    this.groupId = 'pitch_match',
    this.minHz = 125,
    this.maxHz = 16000,
    this.maxTrials = 18,
  })  : assert(minHz > 0 && maxHz > minHz),
        _low = minHz,
        _high = maxHz;

  final String moduleId;
  final String groupId;
  final double minHz;
  final double maxHz;
  final int maxTrials;

  double _low;
  double _high;

  final List<TrialRecord> records = <TrialRecord>[];

  /// Current search range (Hz).
  double get rangeLowHz => _low;
  double get rangeHighHz => _high;

  /// The midpoint of the current range (log space).
  double get midHz => geoMean(_low, _high);

  /// The two candidate frequencies presented this trial: [lowerHz] represents
  /// the lower half of the range, [higherHz] the upper half.
  double get lowerHz => geoMean(_low, midHz);
  double get higherHz => geoMean(midHz, _high);

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  /// Width of the current range in octaves — a convergence indicator.
  double get rangeOctaves => math.log(_high / _low) / math.ln2;

  /// Complete after the trial budget, or once the range is narrower than a
  /// quarter-octave (already a precise subjective match).
  bool get isComplete => records.length >= maxTrials || rangeOctaves <= 0.25;

  /// The matched frequency (geometric centre of the final range).
  double get matchedHz => midHz;

  /// Records a choice and narrows the range. [choseHigher] is true when the
  /// listener picked [higherHz] as closer to their tinnitus.
  void submit(bool choseHigher, {int latencyMs = 0}) {
    final chosen = choseHigher ? higherHz : lowerHz;
    records.add(
      TrialRecord(
        target: 'subjective',
        response: chosen.toStringAsFixed(1),
        correct: true, // subjective match — no right/wrong
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'lower_hz': lowerHz,
          'higher_hz': higherHz,
          'chose_higher': choseHigher,
          'range_low_hz': _low,
          'range_high_hz': _high,
        },
      ),
    );
    final mid = midHz;
    if (choseHigher) {
      _low = mid;
    } else {
      _high = mid;
    }
  }
}
