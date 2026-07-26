/// Random Gap Detection Test (RGDT) protocol logic (pure Dart).
///
/// At each of four frequencies (500, 1000, 2000, 4000 Hz) the listener hears a
/// pair of brief tone bursts separated by a silent gap and reports whether they
/// perceived "one sound" or "two sounds". Catch trials with no gap guard against
/// a "two" response bias. The gap-detection threshold at a frequency is the
/// smallest gap the listener reliably detects (≥ [detectionCriterion], default
/// 2/3); the combined threshold is the mean across frequencies.
///
/// Reference: adults typically ≤ 10 ms, children ≤ 20 ms (Keith, 2000 — RGDT).
/// Task-relative and illustrative on uncalibrated audio; never a diagnosis.
///
/// Flutter-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import 'protocol_engine.dart';

/// The four test frequencies (Hz).
const List<double> kRgdtFrequencies = <double>[500, 1000, 2000, 4000];

/// The ascending gap durations (ms) probed at each frequency.
const List<double> kRgdtGaps = <double>[2, 5, 10, 15, 20, 25, 30, 40];

/// A single RGDT trial: a [frequencyHz] tone pair separated by [gapMs]. A
/// [gapMs] of 0 is a catch trial (a single continuous sound → "one sound").
class RgdtTrial {
  const RgdtTrial({required this.frequencyHz, required this.gapMs});

  final double frequencyHz;
  final double gapMs;

  bool get hasGap => gapMs > 0;

  /// The listener is correct if their "two sounds" report matches whether a
  /// gap was actually present.
  bool isCorrect(bool heardTwo) => heardTwo == hasGap;
}

/// Deterministic generator: for each frequency (in ascending block order) it
/// emits [presentationsPerGap] trials at every gap plus [catchPerFrequency]
/// no-gap catch trials, shuffled within the frequency block.
class RgdtGenerator {
  RgdtGenerator({
    this.frequencies = kRgdtFrequencies,
    this.gaps = kRgdtGaps,
    this.presentationsPerGap = 3,
    this.catchPerFrequency = 2,
    int seed = 0,
  }) {
    final rng = Random(seed);
    for (final f in frequencies) {
      final block = <RgdtTrial>[];
      for (final g in gaps) {
        for (var i = 0; i < presentationsPerGap; i++) {
          block.add(RgdtTrial(frequencyHz: f, gapMs: g));
        }
      }
      for (var i = 0; i < catchPerFrequency; i++) {
        block.add(RgdtTrial(frequencyHz: f, gapMs: 0));
      }
      block.shuffle(rng);
      _trials.addAll(block);
    }
  }

  final List<double> frequencies;
  final List<double> gaps;
  final int presentationsPerGap;
  final int catchPerFrequency;

  final List<RgdtTrial> _trials = <RgdtTrial>[];

  int _index = 0;

  int get totalTrials => _trials.length;
  bool get isComplete => _index >= _trials.length;

  RgdtTrial next() => _trials[_index++];
}

/// Sequences and scores an RGDT run, computing per-frequency and combined
/// gap-detection thresholds.
class RgdtSession {
  RgdtSession({
    this.moduleId = 'auditory',
    this.groupId = 'random_gap_detection',
    this.frequencies = kRgdtFrequencies,
    this.gaps = kRgdtGaps,
    this.detectionCriterion = 2 / 3,
    this.totalTrials = 0,
  });

  final String moduleId;
  final String groupId;
  final List<double> frequencies;
  final List<double> gaps;

  /// Fraction of gap-trials at a gap that must be detected ("two sounds") for
  /// that gap to count as reliably detected.
  final double detectionCriterion;

  /// Optional planned trial count (for progress display); 0 = unknown.
  final int totalTrials;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    RgdtTrial trial,
    bool heardTwo, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(heardTwo);
    records.add(
      TrialRecord(
        target: trial.hasGap ? 'two' : 'one',
        response: heardTwo ? 'two' : 'one',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'frequency_hz': trial.frequencyHz,
          'gap_ms': trial.gapMs,
          'has_gap': trial.hasGap,
        },
      ),
    );
    return correct;
  }

  /// Detection rate (fraction reporting "two sounds") among gap-trials at
  /// [frequencyHz] and [gapMs]. Returns null if that cell has no trials.
  double? detectionRate(double frequencyHz, double gapMs) {
    final cell = records.where((r) =>
        r.parameters['frequency_hz'] == frequencyHz &&
        r.parameters['gap_ms'] == gapMs);
    if (cell.isEmpty) return null;
    final two = cell.where((r) => r.response == 'two').length;
    return two / cell.length;
  }

  /// Smallest gap (ms) at [frequencyHz] whose detection rate meets
  /// [detectionCriterion]; null if none reached criterion yet.
  double? thresholdForFrequency(double frequencyHz) {
    final sorted = List<double>.of(gaps)..sort();
    for (final g in sorted) {
      final rate = detectionRate(frequencyHz, g);
      if (rate != null && rate >= detectionCriterion) return g;
    }
    return null;
  }

  /// Per-frequency thresholds (only frequencies that reached criterion).
  Map<double, double> get perFrequencyThresholds {
    final out = <double, double>{};
    for (final f in frequencies) {
      final t = thresholdForFrequency(f);
      if (t != null) out[f] = t;
    }
    return out;
  }

  /// Mean of the per-frequency thresholds, or null if none reached criterion.
  double? get combinedThresholdMs {
    final vals = perFrequencyThresholds.values;
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }
}
