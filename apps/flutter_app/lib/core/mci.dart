/// Melodic Contour Identification (MCI) 9-choice protocol logic (pure Dart).
///
/// One of nine five-note pitch contours is played; the listener identifies its
/// shape from nine choices. This renderer uses the pre-generated pure-tone
/// contour assets shipped in `assets/stimuli/mci_*.wav` (real audio). Scoring is
/// exact choice; this is an identification task (no staircase). Master volume is
/// never touched.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// The nine contour patterns, matching the shipped `mci_<pattern>.wav` assets.
const List<String> kContourPatterns = <String>[
  'rise',
  'fall',
  'flat',
  'rise_fall',
  'fall_rise',
  'rise_flat',
  'flat_rise',
  'fall_flat',
  'flat_fall',
];

String contourLabel(String pattern) => switch (pattern) {
      'rise' => 'Rising',
      'fall' => 'Falling',
      'flat' => 'Flat',
      'rise_fall' => 'Rise–Fall',
      'fall_rise' => 'Fall–Rise',
      'rise_flat' => 'Rise–Flat',
      'flat_rise' => 'Flat–Rise',
      'fall_flat' => 'Fall–Flat',
      'flat_fall' => 'Flat–Fall',
      _ => pattern,
    };

String contourGlyph(String pattern) => switch (pattern) {
      'rise' => '↗',
      'fall' => '↘',
      'flat' => '→',
      'rise_fall' => '↗↘',
      'fall_rise' => '↘↗',
      'rise_flat' => '↗→',
      'flat_rise' => '→↗',
      'fall_flat' => '↘→',
      'flat_fall' => '→↘',
      _ => '?',
    };

/// A single MCI trial: which of [choices] contour was played.
class MciTrial {
  MciTrial({required this.targetIndex, this.choices = kContourPatterns})
      : assert(targetIndex >= 0 && targetIndex < choices.length);

  final int targetIndex;
  final List<String> choices;

  String get targetPattern => choices[targetIndex];

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;

  /// Asset path for the contour at [index].
  String assetFor(int index) => 'assets/stimuli/mci_${choices[index]}.wav';
}

/// Deterministic generator selecting which contour is the target.
class MciGenerator {
  MciGenerator({int seed = 0, this.patterns = kContourPatterns})
      : _rng = Random(seed);

  final List<String> patterns;
  final Random _rng;

  MciTrial next() =>
      MciTrial(targetIndex: _rng.nextInt(patterns.length), choices: patterns);
}

/// Sequences and scores an MCI identification run.
class MciSession {
  MciSession({
    this.moduleId = 'melodic',
    this.groupId = 'pure_tone_contour',
    this.maxTrials = 25,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    MciTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(
      TrialRecord(
        target: trial.targetPattern,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'pattern': trial.targetPattern,
          'choices': trial.choices.length,
        },
      ),
    );
    return correct;
  }
}
