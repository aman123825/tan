/// Tinnitus loudness matching by adaptive bracketing (pure Dart).
///
/// At the matched tinnitus frequency a tone is presented and the listener says
/// whether it is louder than, softer than, or about the same as their tinnitus.
/// "Louder" lowers the level, "softer" raises it, and the step halves at each
/// reversal so the level brackets the tinnitus loudness. The result is reported
/// as a relative "dB SL" (sensation level) figure — subjective and
/// uncalibrated, never a diagnosis, and never a master-volume change.
library;

import 'dart:math' as math;

import '../protocol_engine.dart';

/// The listener's judgement of the presented tone versus their tinnitus.
enum LoudnessResponse { louder, softer, same }

/// Sequences an adaptive loudness match at a fixed frequency.
class LoudnessMatchSession {
  LoudnessMatchSession({
    this.moduleId = 'tinnitus',
    this.groupId = 'loudness_match',
    required this.frequencyHz,
    this.startDb = 15,
    this.step = 6,
    this.minStep = 1,
    this.minDb = 0,
    this.maxDb = 40,
    this.maxTrials = 20,
    this.matchesToFinish = 3,
  })  : _levelDb = startDb.clamp(minDb, maxDb).toDouble(),
        _step = step;

  final String moduleId;
  final String groupId;
  final double frequencyHz;
  final double startDb;
  final double step;
  final double minStep;
  final double minDb;
  final double maxDb;
  final int maxTrials;

  /// How many "about the same" judgements end the run early.
  final int matchesToFinish;

  double _levelDb;
  double _step;
  int _lastDir = 0; // -1 after "louder", +1 after "softer"
  final List<double> _matches = <double>[];
  final List<TrialRecord> records = <TrialRecord>[];

  /// Relative level (dB SL) of the tone to present next.
  double get levelDb => _levelDb;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get isComplete =>
      records.length >= maxTrials || _matches.length >= matchesToFinish;

  /// Matched tinnitus loudness (dB SL): mean of the "same" judgements if any,
  /// otherwise the final bracketed level.
  double get matchedDb {
    if (_matches.isNotEmpty) {
      return _matches.reduce((a, b) => a + b) / _matches.length;
    }
    return _levelDb;
  }

  void submit(LoudnessResponse response, {int latencyMs = 0}) {
    records.add(
      TrialRecord(
        target: 'tinnitus_loudness',
        response: response.name,
        correct: true, // subjective
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'level_db': _levelDb,
          'frequency_hz': frequencyHz,
        },
      ),
    );
    switch (response) {
      case LoudnessResponse.louder:
        // Tone is louder than tinnitus → step down toward it.
        if (_lastDir == 1) _step = math.max(minStep, _step / 2);
        _lastDir = -1;
        _levelDb = (_levelDb - _step).clamp(minDb, maxDb).toDouble();
      case LoudnessResponse.softer:
        // Tone is softer than tinnitus → step up toward it.
        if (_lastDir == -1) _step = math.max(minStep, _step / 2);
        _lastDir = 1;
        _levelDb = (_levelDb + _step).clamp(minDb, maxDb).toDouble();
      case LoudnessResponse.same:
        _matches.add(_levelDb);
    }
  }
}
