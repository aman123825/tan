/// Tinnitus Minimum Masking Level (MML) by ascending method (pure Dart).
///
/// Broadband noise is presented at increasing level until the listener reports
/// their tinnitus is masked ("Tinnitus is gone"). The lowest masking level is
/// recorded, then re-approached from below a few times and averaged. Result is
/// a relative "dB" MML — subjective and uncalibrated, not a diagnosis, and it
/// never changes master volume. Flutter-free (unit-testable headlessly).
library;

import 'dart:math' as math;

import '../protocol_engine.dart';

/// The listener's report about whether the noise masks the tinnitus.
enum MaskingResponse { stillHear, gone }

/// Sequences an ascending minimum-masking-level run.
class MmlSession {
  MmlSession({
    this.moduleId = 'tinnitus',
    this.groupId = 'mml',
    this.startDb = 0,
    this.step = 4,
    this.minDb = 0,
    this.maxDb = 40,
    this.maxTrials = 25,
    this.samplesToFinish = 3,
  }) : _levelDb = startDb.clamp(minDb, maxDb).toDouble();

  final String moduleId;
  final String groupId;
  final double startDb;
  final double step;
  final double minDb;
  final double maxDb;
  final int maxTrials;

  /// Number of ascending "gone" thresholds to average.
  final int samplesToFinish;

  double _levelDb;
  final List<double> _thresholds = <double>[];
  final List<TrialRecord> records = <TrialRecord>[];

  /// Relative level (dB) of the noise to present next.
  double get levelDb => _levelDb;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  /// The number of masking thresholds collected so far.
  int get samplesCollected => _thresholds.length;

  bool get isComplete =>
      records.length >= maxTrials || _thresholds.length >= samplesToFinish;

  /// Minimum masking level (dB): mean of the ascending "gone" thresholds, or
  /// the current level if none were reached (e.g. capped at [maxDb]).
  double get mmlDb {
    if (_thresholds.isNotEmpty) {
      return _thresholds.reduce((a, b) => a + b) / _thresholds.length;
    }
    return _levelDb;
  }

  void submit(MaskingResponse response, {int latencyMs = 0}) {
    records.add(
      TrialRecord(
        target: 'tinnitus_masking',
        response: response.name,
        correct: true, // subjective
        latencyMs: latencyMs,
        parameters: <String, Object?>{'level_db': _levelDb},
      ),
    );
    switch (response) {
      case MaskingResponse.stillHear:
        // Not yet masked → raise the noise. If we've hit the ceiling, record
        // the cap as a threshold so the run can finish.
        if (_levelDb >= maxDb) {
          _thresholds.add(_levelDb);
        } else {
          _levelDb = (_levelDb + step).clamp(minDb, maxDb).toDouble();
        }
      case MaskingResponse.gone:
        // Masked → record this ascending threshold, then drop below it and
        // re-approach to confirm.
        _thresholds.add(_levelDb);
        _levelDb =
            (_levelDb - step * 2).clamp(minDb, maxDb).toDouble();
    }
  }

  /// Standard deviation of the collected thresholds (precision indicator).
  double? get mmlSd {
    if (_thresholds.length < 2) return null;
    final m = mmlDb;
    final v = _thresholds
            .map((x) => (x - m) * (x - m))
            .reduce((a, b) => a + b) /
        _thresholds.length;
    return math.sqrt(v);
  }
}
