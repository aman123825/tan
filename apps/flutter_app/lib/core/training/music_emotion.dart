/// Emotion-in-music training protocol logic (pure Dart, Flutter-free).
///
/// A short melody (4–8 notes) is synthesized in one of four affective styles
/// and identified in a four-alternative forced choice:
///
///   * Happy — major key, fast tempo.
///   * Sad   — minor key, slow tempo.
///   * Tense — dissonant intervals (semitones / tritones), medium tempo.
///   * Calm  — consonant intervals (thirds / fifths / octaves), very slow.
///
/// Melodies are synthesized with pure tones — a labelled demonstration proxy,
/// not validated clinical stimuli. Nothing here changes master volume.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';

/// The four musical emotions.
enum MusicEmotion { happy, sad, tense, calm }

extension MusicEmotionInfo on MusicEmotion {
  String get label => switch (this) {
        MusicEmotion.happy => 'Happy',
        MusicEmotion.sad => 'Sad',
        MusicEmotion.tense => 'Tense',
        MusicEmotion.calm => 'Calm',
      };

  String get emoji => switch (this) {
        MusicEmotion.happy => '😊',
        MusicEmotion.sad => '😢',
        MusicEmotion.tense => '😬',
        MusicEmotion.calm => '😌',
      };
}

/// Musical parameters for an emotion: the semitone [intervals] it draws notes
/// from, plus [noteSeconds] and [gapSeconds] (tempo/articulation).
class MusicEmotionSpec {
  const MusicEmotionSpec(this.intervals, this.noteSeconds, this.gapSeconds);

  final List<int> intervals;
  final double noteSeconds;
  final double gapSeconds;
}

/// Style table. Happy=major/fast, Sad=minor/slow, Tense=dissonant/medium,
/// Calm=consonant/very-slow.
const Map<MusicEmotion, MusicEmotionSpec> kMusicEmotionSpecs =
    <MusicEmotion, MusicEmotionSpec>{
  // Major scale degrees — bright, quick.
  MusicEmotion.happy: MusicEmotionSpec(<int>[0, 2, 4, 5, 7, 9, 12], 0.22, 0.04),
  // Natural-minor degrees — darker, slow.
  MusicEmotion.sad: MusicEmotionSpec(<int>[0, 2, 3, 5, 7, 8, 10], 0.46, 0.10),
  // Semitones + tritone — dissonant, medium.
  MusicEmotion.tense: MusicEmotionSpec(<int>[0, 1, 6, 7, 8, 13], 0.30, 0.05),
  // Consonant intervals (thirds/fifths/octave) — very slow.
  MusicEmotion.calm: MusicEmotionSpec(<int>[0, 4, 7, 12, 16], 0.66, 0.16),
};

MusicEmotionSpec musicEmotionSpec(MusicEmotion e) =>
    kMusicEmotionSpecs[e] ?? kMusicEmotionSpecs[MusicEmotion.happy]!;

List<double> _peakNorm(List<double> x, [double peak = 0.85]) {
  var mx = 0.0;
  for (final v in x) {
    if (v.abs() > mx) mx = v.abs();
  }
  if (mx > 0) {
    final k = peak / mx;
    for (var i = 0; i < x.length; i++) {
      x[i] *= k;
    }
  }
  return x;
}

/// Synthesizes a melody for [emotion] with [noteCount] notes drawn
/// deterministically from [rng]. Uses pure tones at the emotion's tempo.
List<double> melodyForEmotion(
  MusicEmotion emotion, {
  required int noteCount,
  required Random rng,
  double rootHz = 262.0,
  int sampleRate = kSampleRate,
}) {
  final spec = musicEmotionSpec(emotion);
  final parts = <List<double>>[];
  // Calm/sad tend to fall; happy tends to rise — bias the walk a little.
  for (var i = 0; i < noteCount; i++) {
    if (i > 0) parts.add(silence(spec.gapSeconds, sampleRate));
    final degree = spec.intervals[rng.nextInt(spec.intervals.length)];
    parts.add(tone(
      seconds: spec.noteSeconds,
      freqHz: shiftSemitones(rootHz, degree.toDouble()),
      amp: 0.24,
      sampleRate: sampleRate,
    ));
  }
  return _peakNorm(concat(parts));
}

/// A single emotion-in-music trial (4AFC over all four emotions).
class MusicEmotionTrial {
  const MusicEmotionTrial({
    required this.target,
    required this.choices,
    required this.targetIndex,
    required this.noteCount,
    required this.seed,
  });

  final MusicEmotion target;
  final List<MusicEmotion> choices;
  final int targetIndex;
  final int noteCount;

  /// Seed for deterministic melody synthesis.
  final int seed;

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;

  /// Synthesizes this trial's melody.
  List<double> synthesize({double rootHz = 262.0, int sampleRate = kSampleRate}) =>
      melodyForEmotion(target,
          noteCount: noteCount,
          rng: Random(seed),
          rootHz: rootHz,
          sampleRate: sampleRate);
}

/// Deterministic emotion-in-music trial generator (4AFC).
class MusicEmotionGenerator {
  MusicEmotionGenerator({int seed = 0}) : _rng = Random(seed), _seed = seed;

  final Random _rng;
  final int _seed;
  int _n = 0;

  MusicEmotionTrial next() {
    final choices = List<MusicEmotion>.of(MusicEmotion.values)..shuffle(_rng);
    final targetIndex = _rng.nextInt(choices.length);
    final noteCount = 4 + _rng.nextInt(5); // 4..8
    _n++;
    return MusicEmotionTrial(
      target: choices[targetIndex],
      choices: choices,
      targetIndex: targetIndex,
      noteCount: noteCount,
      seed: _seed * 1000 + _n,
    );
  }
}

/// Emotion-in-music session (20 trials by default). A straightforward 4AFC
/// identification run; reports accuracy and streaks.
class MusicEmotionSession {
  MusicEmotionSession({this.maxTrials = 20});

  final int maxTrials;

  int _correct = 0;
  int _completed = 0;
  int _streak = 0;
  int _bestStreak = 0;
  final List<bool> results = <bool>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get correctCount => _correct;
  int get currentStreak => _streak;
  int get bestStreak => _bestStreak;
  bool get isComplete => _completed >= maxTrials;
  double get accuracy => _completed == 0 ? 0 : _correct / _completed;
  int get percent => (accuracy * 100).round();

  bool submit(MusicEmotionTrial trial, int chosenIndex) {
    final correct = trial.isCorrect(chosenIndex);
    _completed++;
    if (correct) {
      _correct++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
    } else {
      _streak = 0;
    }
    results.add(correct);
    return correct;
  }
}
