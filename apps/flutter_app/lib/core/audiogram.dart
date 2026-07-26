/// Screening audiogram session (pure Dart, Flutter-free).
///
/// A multi-frequency tone-detection screen: for each ear and each frequency
/// 250–8000 Hz, a modified Hughson-Westlake procedure (ASHA, 2005; Carhart &
/// Jerger, 1959) tracks the lowest presentation level the listener reports
/// hearing — level moves DOWN 10 dB after a "heard" response and UP 5 dB
/// after "not heard"; threshold is the lowest level answered "heard" on at
/// least 2 ascending presentations. Seeded catch trials (silence) estimate
/// the false-alarm rate.
///
/// Levels are **dB re: full scale (dBFS) on uncalibrated consumer audio** —
/// deliberately NOT dB HL. The plotted curve shows the *shape* across
/// frequency; absolute sensitivity needs a calibrated audiometer. Research
/// screening only — never a diagnosis.
///
/// SAFETY: presentation level is capped at [kMaxLevelDbfs] (−10 dBFS, linear
/// amplitude ≈ 0.32, well under the app-wide 0.7 cap) and only ever *rises*
/// in 5 dB steps after a "not heard" response. Master volume is never touched.
library;

import 'dart:math';

import 'protocol_engine.dart';

/// Test frequencies in Hz, in standard clinical presentation order (start at
/// 1 kHz, ascend, then the low frequencies — Carhart & Jerger, 1959).
const List<double> kAudiogramOrder = <double>[1000, 2000, 4000, 8000, 500, 250];

/// The same frequencies in ascending order (for plotting).
const List<double> kAudiogramFrequencies = <double>[
  250, 500, 1000, 2000, 4000, 8000,
];

/// Loudest allowed presentation level (dB re: full scale).
const double kMaxLevelDbfs = -10;

/// Quietest presentation level (below this the screen records "no response
/// needed" — the listener heard everything the transducer can meaningfully do).
const double kMinLevelDbfs = -80;

/// Starting level for every frequency.
const double kStartLevelDbfs = -40;

/// Linear amplitude for a level in dBFS (0 dBFS = 1.0).
double amplitudeFromDbfs(double dbfs) => pow(10, dbfs / 20).toDouble();

/// One frequency's modified Hughson-Westlake tracker.
///
/// down-10/up-5 with threshold = lowest level with ≥ 2 "heard" responses on
/// ascending presentations. Stops after [maxPresentations] or when 3
/// consecutive "not heard" responses occur at the level cap (no response).
class HughsonWestlakeTrack {
  HughsonWestlakeTrack({
    this.start = kStartLevelDbfs,
    this.maxLevel = kMaxLevelDbfs,
    this.minLevel = kMinLevelDbfs,
    this.maxPresentations = 20,
  }) : level = start;

  final double start;
  final double maxLevel;
  final double minLevel;
  final int maxPresentations;

  /// Level (dBFS) of the next presentation.
  double level;

  int presentations = 0;
  bool _lastMoveWasUp = false;
  int _noAtCap = 0;
  final Map<double, int> _ascendingYes = <double, int>{};

  /// Threshold in dBFS once found; null while running or when no response.
  double? threshold;

  /// True when the listener never responded at the level cap ("no response").
  bool noResponse = false;

  bool get isComplete =>
      threshold != null || noResponse || presentations >= maxPresentations;

  /// Submits one response at the current [level]. Returns the new level.
  double submit(bool heard) {
    if (isComplete) return level;
    presentations++;
    if (heard) {
      _noAtCap = 0;
      if (_lastMoveWasUp || presentations == 1) {
        // A response on an ascending run (the first presentation counts as
        // the start of an ascent from silence).
        final n = (_ascendingYes[level] ?? 0) + 1;
        _ascendingYes[level] = n;
        if (n >= 2) {
          threshold = level;
          return level;
        }
      }
      level = max(minLevel, level - 10);
      _lastMoveWasUp = false;
    } else {
      if (level >= maxLevel) {
        _noAtCap++;
        if (_noAtCap >= 3) {
          noResponse = true;
          return level;
        }
      }
      level = min(maxLevel, level + 5);
      _lastMoveWasUp = true;
    }
    if (presentations >= maxPresentations && threshold == null) {
      // Budget exhausted without a converged threshold: best-effort estimate
      // is the lowest level that ever got an ascending response, else none.
      final seen = _ascendingYes.keys.toList()..sort();
      if (seen.isNotEmpty) threshold = seen.first;
    }
    return level;
  }
}

/// One planned presentation: which ear/frequency, at what level, and whether
/// it is a silent catch trial.
class AudiogramPresentation {
  const AudiogramPresentation({
    required this.ear,
    required this.freqHz,
    required this.levelDbfs,
    required this.isCatch,
  });

  final String ear; // 'right' | 'left'
  final double freqHz;
  final double levelDbfs;
  final bool isCatch;

  /// Linear amplitude for synthesis (0 for a catch trial).
  double get amplitude => isCatch ? 0 : amplitudeFromDbfs(levelDbfs);
}

/// Sequences the whole screen: right ear then left, frequencies in
/// [kAudiogramOrder], one Hughson-Westlake track each, with seeded catch
/// trials (~1 in 6 presentations).
class AudiogramSession {
  AudiogramSession({
    this.moduleId = 'auditory',
    this.groupId = 'screening_audiogram',
    int seed = 0,
    this.maxPresentationsPerFrequency = 20,
  }) : _rng = Random(seed) {
    for (final ear in const ['right', 'left']) {
      for (final f in kAudiogramOrder) {
        _tracks['$ear-$f'] = HughsonWestlakeTrack(
            maxPresentations: maxPresentationsPerFrequency);
      }
    }
  }

  final String moduleId;
  final String groupId;
  final int maxPresentationsPerFrequency;
  final Random _rng;

  final Map<String, HughsonWestlakeTrack> _tracks =
      <String, HughsonWestlakeTrack>{};
  final List<TrialRecord> records = <TrialRecord>[];

  int _earIndex = 0; // 0 = right, 1 = left
  int _freqIndex = 0;
  int catchTrials = 0;
  int falseAlarms = 0;

  String get currentEar => _earIndex == 0 ? 'right' : 'left';
  double get currentFreqHz => kAudiogramOrder[_freqIndex];

  HughsonWestlakeTrack get _track =>
      _tracks['$currentEar-$currentFreqHz']!;

  bool get isComplete => _earIndex >= 2;

  int get completedTrials => records.length;

  /// Fraction of catch trials answered "heard" (0 when none presented yet).
  double get falseAlarmRate =>
      catchTrials == 0 ? 0 : falseAlarms / catchTrials;

  AudiogramPresentation? _pending;

  /// The next presentation to play (stable until [submit] is called).
  AudiogramPresentation? next() {
    if (isComplete) return null;
    if (_pending != null) return _pending;
    // ~1-in-6 seeded catch trials, never twice in a row (the staircase level
    // is unaffected by catches).
    final isCatch = _lastWasCatch ? false : _rng.nextInt(6) == 0;
    _pending = AudiogramPresentation(
      ear: currentEar,
      freqHz: currentFreqHz,
      levelDbfs: _track.level,
      isCatch: isCatch,
    );
    return _pending;
  }

  bool _lastWasCatch = false;

  /// Scores the pending presentation. Returns whether the answer was
  /// "correct" (heard a tone / rejected a catch); catch trials never move the
  /// staircase.
  bool submit(bool heard, {int latencyMs = 0}) {
    final p = _pending;
    if (p == null) return false;
    _pending = null;
    _lastWasCatch = p.isCatch;
    final bool correct;
    if (p.isCatch) {
      catchTrials++;
      if (heard) falseAlarms++;
      correct = !heard;
    } else {
      // "Correctness" for a detection screen is bookkeeping only (there is no
      // wrong answer to a real tone) — recorded as heard-or-not for export.
      correct = heard;
      _track.submit(heard);
      if (_track.isComplete) _advance();
    }
    records.add(TrialRecord(
      target: p.isCatch ? 'catch' : 'tone',
      response: heard ? 'heard' : 'not_heard',
      correct: correct,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'ear': p.ear,
        'freq_hz': p.freqHz,
        'level_dbfs': p.levelDbfs,
        'catch': p.isCatch,
      },
    ));
    return correct;
  }

  void _advance() {
    _freqIndex++;
    if (_freqIndex >= kAudiogramOrder.length) {
      _freqIndex = 0;
      _earIndex++;
    }
  }

  /// Threshold (dBFS) for [ear] at [freqHz]; null when not yet measured or no
  /// response at the cap.
  double? thresholdFor(String ear, double freqHz) =>
      _tracks['$ear-$freqHz']?.threshold;

  /// Whether [ear] at [freqHz] ended as "no response at the maximum level".
  bool noResponseFor(String ear, double freqHz) =>
      _tracks['$ear-$freqHz']?.noResponse ?? false;

  /// Pure-tone average (500/1000/2000 Hz) for [ear], or null when any of the
  /// three thresholds is missing.
  double? ptaFor(String ear) {
    var sum = 0.0;
    for (final f in const <double>[500, 1000, 2000]) {
      final t = thresholdFor(ear, f);
      if (t == null) return null;
      sum += t;
    }
    return sum / 3;
  }
}
