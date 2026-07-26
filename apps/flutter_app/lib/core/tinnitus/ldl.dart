/// Hyperacusis Loudness Discomfort Level (LDL) screen (pure Dart).
///
/// Tones are presented ascending (soft → louder in 5 dB steps) at each of a set
/// of frequencies. The listener presses "Too loud!" when the sound becomes
/// uncomfortable, recording an LDL for that frequency; otherwise they continue
/// upward. A HARD SAFETY CAP limits the on-signal amplitude to
/// [kMaxSafeAmp] (0.7) — the level can never rise past the cap, and reaching it
/// records the cap as the LDL and moves on. The master-volume lock also applies.
///
/// Relative dB only (uncalibrated) — not a diagnosis, never a master-volume
/// change. Flutter-free (unit-testable headlessly).
library;

import '../protocol_engine.dart';
import 'tinnitus_store.dart';

/// The four screening frequencies (Hz).
const List<double> kLdlFrequencies = <double>[500, 1000, 2000, 4000];

/// Sequences an ascending LDL screen across [frequencies].
class LdlSession {
  LdlSession({
    this.moduleId = 'tinnitus',
    this.groupId = 'ldl',
    this.frequencies = kLdlFrequencies,
    this.startDb = 5,
    this.step = 5,
    this.minDb = 0,
    double amplitudeCap = kMaxSafeAmp,
  })  : _cap = amplitudeCap.clamp(0.0, kMaxSafeAmp),
        _levelDb = startDb {
    // Precompute the ceiling level for the (capped) amplitude.
    _capDb = amplitudeCapDb(cap: _cap);
  }

  final String moduleId;
  final String groupId;
  final List<double> frequencies;
  final double startDb;
  final double step;
  final double minDb;

  final double _cap;
  late final double _capDb;

  int _freqIndex = 0;
  double _levelDb;
  final Map<double, double> _ldl = <double, double>{};
  final List<TrialRecord> records = <TrialRecord>[];

  /// The frequency currently being screened (Hz).
  double get currentFrequencyHz =>
      frequencies[_freqIndex.clamp(0, frequencies.length - 1)];

  /// Relative level (dB) of the tone to present next.
  double get levelDb => _levelDb;

  /// The hard amplitude cap in force (never above [kMaxSafeAmp]).
  double get amplitudeCap => _cap;

  /// The relative-dB ceiling at which amplitude reaches the cap.
  double get capDb => _capDb;

  /// Safe on-signal amplitude for the current level (always ≤ [kMaxSafeAmp]).
  double get currentAmplitude => relativeDbToAmplitude(_levelDb, cap: _cap);

  /// True when the current level has reached the amplitude ceiling.
  bool get atCap => _levelDb >= _capDb;

  int get frequencyIndex => _freqIndex;
  int get frequencyCount => frequencies.length;
  int get completedTrials => records.length;

  bool get isComplete => _freqIndex >= frequencies.length;

  /// LDL results so far, keyed by frequency (Hz) → relative dB.
  Map<double, double> get results => Map<double, double>.unmodifiable(_ldl);

  void _record(String response, {required int latencyMs}) {
    records.add(
      TrialRecord(
        target: 'ldl_${currentFrequencyHz.round()}hz',
        response: response,
        correct: true, // subjective
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'frequency_hz': currentFrequencyHz,
          'level_db': _levelDb,
          'amplitude': currentAmplitude,
          'at_cap': atCap,
        },
      ),
    );
  }

  void _advanceFrequency() {
    _freqIndex++;
    _levelDb = startDb;
  }

  /// The listener finds the current level tolerable and wants it louder. Raises
  /// the level by [step]; if that reaches the amplitude cap, the cap level is
  /// recorded as the LDL for this frequency and the screen advances.
  void louder({int latencyMs = 0}) {
    if (isComplete) return;
    _record('tolerable', latencyMs: latencyMs);
    final next = _levelDb + step;
    if (next >= _capDb) {
      // Ceiling reached — cannot present louder. Record the cap and move on.
      _levelDb = _capDb;
      _ldl[currentFrequencyHz] = _capDb;
      _advanceFrequency();
    } else {
      _levelDb = next;
    }
  }

  /// The listener finds the current level uncomfortable. Records the LDL for
  /// this frequency and advances to the next.
  void tooLoud({int latencyMs = 0}) {
    if (isComplete) return;
    _record('too_loud', latencyMs: latencyMs);
    _ldl[currentFrequencyHz] = _levelDb;
    _advanceFrequency();
  }

  /// Mean LDL across measured frequencies (relative dB), or null if none.
  double? get meanLdlDb {
    if (_ldl.isEmpty) return null;
    return _ldl.values.reduce((a, b) => a + b) / _ldl.length;
  }
}
