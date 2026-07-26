/// Music chord identification protocol logic (pure Dart).
///
/// A triad is synthesized additively (sum of pure tones at the chord's semitone
/// offsets from a randomized root) and the listener identifies its quality from
/// a closed set. This is an identification task (no staircase). The root varies
/// per trial so the cue is chord quality, not absolute pitch. Master volume is
/// never touched.
library;

import 'dart:math';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// A chord quality: [semitones] are offsets from the root (equal temperament).
class ChordType {
  const ChordType(this.id, this.label, this.semitones);

  final String id;
  final String label;
  final List<int> semitones;
}

/// The default four-way chord-quality choice set.
const List<ChordType> kChordChoices = <ChordType>[
  ChordType('major', 'Major', <int>[0, 4, 7]),
  ChordType('minor', 'Minor', <int>[0, 3, 7]),
  ChordType('diminished', 'Diminished', <int>[0, 3, 6]),
  ChordType('augmented', 'Augmented', <int>[0, 4, 8]),
];

/// Candidate root frequencies (A3, B3, C4, D4) so quality — not pitch — is the
/// cue.
const List<double> kChordRootsHz = <double>[220.0, 246.94, 261.63, 293.66];

/// Additively synthesizes a chord: the sum of pure tones at each semitone
/// offset from [rootHz], peak-normalized to avoid clipping.
List<double> chordStimulus({
  required double rootHz,
  required List<int> semitones,
  double seconds = 0.9,
  double amp = 0.18,
  int sampleRate = kSampleRate,
}) {
  final tones = <List<double>>[
    for (final s in semitones)
      tone(
        seconds: seconds,
        freqHz: shiftSemitones(rootHz, s.toDouble()),
        amp: amp,
        sampleRate: sampleRate,
      ),
  ];
  if (tones.isEmpty) return const <double>[];
  final n = tones.first.length;
  final out = List<double>.filled(n, 0.0);
  for (final t in tones) {
    for (var i = 0; i < n; i++) {
      out[i] += t[i];
    }
  }
  var mx = 0.0;
  for (final x in out) {
    final a = x.abs();
    if (a > mx) mx = a;
  }
  if (mx > 0.9) {
    final k = 0.9 / mx;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  return out;
}

/// A single chord-identification trial.
class ChordTrial {
  ChordTrial({
    required this.targetIndex,
    required this.rootHz,
    this.choices = kChordChoices,
  }) : assert(targetIndex >= 0 && targetIndex < choices.length);

  final int targetIndex;
  final double rootHz;
  final List<ChordType> choices;

  ChordType get target => choices[targetIndex];

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;

  /// The synthesized audio for this trial's chord.
  List<double> synth({int sampleRate = kSampleRate}) => chordStimulus(
        rootHz: rootHz,
        semitones: target.semitones,
        sampleRate: sampleRate,
      );
}

/// Deterministic generator selecting the target chord and a root per trial.
class ChordGenerator {
  ChordGenerator({
    int seed = 0,
    this.choices = kChordChoices,
    this.roots = kChordRootsHz,
  }) : _rng = Random(seed);

  final List<ChordType> choices;
  final List<double> roots;
  final Random _rng;

  ChordTrial next() => ChordTrial(
        targetIndex: _rng.nextInt(choices.length),
        rootHz: roots[_rng.nextInt(roots.length)],
        choices: choices,
      );
}

/// Sequences and scores a chord-identification run.
class ChordSession {
  ChordSession({
    this.moduleId = 'music',
    this.groupId = 'chord',
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
    ChordTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex].id
        : '';
    records.add(
      TrialRecord(
        target: trial.target.id,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'chord': trial.target.id,
          'root_hz': trial.rootHz,
          'choices': trial.choices.length,
        },
      ),
    );
    return correct;
  }
}
