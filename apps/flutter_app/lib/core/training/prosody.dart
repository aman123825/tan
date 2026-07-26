/// Prosody-training protocol logic (pure Dart, Flutter-free).
///
/// Three tasks probe supra-segmental (prosodic) hearing using *synthesized*
/// speech-like buzzes — a labelled demonstration proxy, NOT recorded speech and
/// not validated clinical stimuli:
///
///   1. Question vs Statement — the same syllables with a rising (question) or
///      falling (statement) final intonation contour.
///   2. Stressed word — a two-word phrase where either the first or the second
///      word carries the emphasis (louder, higher, longer).
///   3. Emotion — happy (high, fast), sad (low, slow) or angry (loud, choppy).
///
/// Difficulty adapts by shrinking the prosodic cue (a subtler pitch excursion /
/// emphasis / emotional contrast) as the listener improves. Adaptation only
/// ever changes the cue salience — never master volume.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';

/// The three prosody sub-tasks.
enum ProsodyTask { questionStatement, stress, emotion }

extension ProsodyTaskInfo on ProsodyTask {
  String get label => switch (this) {
        ProsodyTask.questionStatement => 'Question or statement?',
        ProsodyTask.stress => 'Which word was stressed?',
        ProsodyTask.emotion => 'How did it sound?',
      };

  /// Closed-set answer labels for this task (index order is the answer key).
  List<String> get choices => switch (this) {
        ProsodyTask.questionStatement => const ['Statement', 'Question'],
        ProsodyTask.stress => const ['First word', 'Second word'],
        ProsodyTask.emotion => const ['Happy', 'Sad', 'Angry'],
      };

  int get choiceCount => choices.length;
}

/// A single prosody trial: the [task], the correct answer index into
/// `task.choices`, and the cue magnitude in effect (semitones of pitch
/// excursion / emphasis strength — smaller = harder).
class ProsodyTrial {
  const ProsodyTrial({
    required this.task,
    required this.answerIndex,
    required this.cueSemitones,
  });

  final ProsodyTask task;
  final int answerIndex;
  final double cueSemitones;

  List<String> get choices => task.choices;

  bool isCorrect(int chosenIndex) => chosenIndex == answerIndex;
}

/// A soft glottal-buzz "syllable": a fundamental plus two harmonics, shaped by
/// a raised-cosine envelope. A speech-like demonstration tone, not real speech.
List<double> _syllable({
  required double f0,
  required double seconds,
  double amp = 0.24,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  if (n <= 0) return <double>[];
  final out = List<double>.filled(n, 0.0);
  const weights = <double>[1.0, 0.5, 0.28];
  final norm = amp / weights.reduce((a, b) => a + b);
  final fade = (0.02 * sampleRate).round().clamp(1, n ~/ 2);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var s = 0.0;
    for (var h = 0; h < weights.length; h++) {
      s += weights[h] * sin(2 * pi * f0 * (h + 1) * t);
    }
    s *= norm;
    if (i < fade) {
      s *= 0.5 * (1 - cos(pi * i / fade));
    } else if (i >= n - fade) {
      s *= 0.5 * (1 - cos(pi * (n - 1 - i) / fade));
    }
    out[i] = s;
  }
  return out;
}

/// Synthesizes the audio for a prosody [trial]. Deterministic for given inputs.
///
///  * [ProsodyTask.questionStatement]: five equal syllables; the last one rises
///    (question) or falls (statement) by [ProsodyTrial.cueSemitones].
///  * [ProsodyTask.stress]: two words (two syllables each). The stressed word is
///    louder, higher (by the cue) and longer.
///  * [ProsodyTask.emotion]: F0 register, tempo and articulation vary by
///    emotion; the cue scales how far from neutral each emotion is pushed.
List<double> synthesizeProsody(
  ProsodyTrial trial, {
  double baseF0 = 130,
  int sampleRate = kSampleRate,
}) {
  switch (trial.task) {
    case ProsodyTask.questionStatement:
      return _questionStatement(trial, baseF0, sampleRate);
    case ProsodyTask.stress:
      return _stress(trial, baseF0, sampleRate);
    case ProsodyTask.emotion:
      return _emotion(trial, baseF0, sampleRate);
  }
}

List<double> _questionStatement(
    ProsodyTrial trial, double baseF0, int sampleRate) {
  final isQuestion = trial.answerIndex == 1;
  const nSyll = 5;
  const syll = 0.22;
  const gap = 0.05;
  final parts = <List<double>>[];
  for (var i = 0; i < nSyll; i++) {
    if (i > 0) parts.add(silence(gap, sampleRate));
    // Neutral body drifts down very slightly; the final syllable carries the
    // question/statement cue.
    var semis = -0.4 * i;
    if (i == nSyll - 1) {
      semis += isQuestion ? trial.cueSemitones : -trial.cueSemitones;
    }
    parts.add(_syllable(
      f0: shiftSemitones(baseF0, semis),
      seconds: syll,
      sampleRate: sampleRate,
    ));
  }
  return concat(parts);
}

List<double> _stress(ProsodyTrial trial, double baseF0, int sampleRate) {
  final stressSecond = trial.answerIndex == 1;
  // Two words; each word is two syllables. Word gap is longer than syllable gap.
  final parts = <List<double>>[];
  for (var w = 0; w < 2; w++) {
    final stressed = (w == 1) == stressSecond;
    if (w > 0) parts.add(silence(0.12, sampleRate));
    for (var s = 0; s < 2; s++) {
      if (s > 0) parts.add(silence(0.04, sampleRate));
      final semis = stressed ? trial.cueSemitones : 0.0;
      final amp = stressed ? 0.3 : 0.18;
      final dur = stressed ? 0.26 : 0.2;
      parts.add(_syllable(
        f0: shiftSemitones(baseF0, semis),
        seconds: dur,
        amp: amp,
        sampleRate: sampleRate,
      ));
    }
  }
  return concat(parts);
}

List<double> _emotion(ProsodyTrial trial, double baseF0, int sampleRate) {
  // Scale the emotional push by the cue (fraction of a fixed maximum), so the
  // staircase can make emotions less caricatured (harder) over time.
  final k = (trial.cueSemitones / 6.0).clamp(0.2, 1.0);
  final parts = <List<double>>[];
  switch (trial.answerIndex) {
    case 0: // happy — high register, fast, gently rising, smooth
      const nSyll = 6;
      final register = 4.0 * k; // semitones up
      for (var i = 0; i < nSyll; i++) {
        if (i > 0) parts.add(silence(0.03, sampleRate));
        parts.add(_syllable(
          f0: shiftSemitones(baseF0, register + i * 0.8 * k),
          seconds: 0.14,
          amp: 0.24,
          sampleRate: sampleRate,
        ));
      }
    case 1: // sad — low register, slow, descending
      const nSyll = 4;
      final register = -4.0 * k;
      for (var i = 0; i < nSyll; i++) {
        if (i > 0) parts.add(silence(0.14, sampleRate));
        parts.add(_syllable(
          f0: shiftSemitones(baseF0, register - i * 1.0 * k),
          seconds: 0.34,
          amp: 0.2,
          sampleRate: sampleRate,
        ));
      }
    default: // angry — loud, choppy/staccato, mid register
      const nSyll = 5;
      for (var i = 0; i < nSyll; i++) {
        if (i > 0) parts.add(silence(0.10 * k + 0.02, sampleRate));
        parts.add(_syllable(
          f0: shiftSemitones(baseF0, 1.0 * k * (i.isEven ? 1 : -1)),
          seconds: 0.12,
          amp: 0.2 + 0.14 * k,
          sampleRate: sampleRate,
        ));
      }
  }
  return concat(parts);
}

/// Deterministic prosody-trial generator for a single task. The cue magnitude
/// is supplied by the session's staircase.
class ProsodyGenerator {
  ProsodyGenerator({required this.task, int seed = 0}) : _rng = Random(seed);

  final ProsodyTask task;
  final Random _rng;

  ProsodyTrial next(double cueSemitones) => ProsodyTrial(
        task: task,
        answerIndex: _rng.nextInt(task.choiceCount),
        cueSemitones: cueSemitones,
      );
}

/// Adaptive prosody-training session (20 trials by default).
///
/// The cue magnitude follows a 2-down / 1-up staircase between [maxCue] (easy)
/// and [minCue] (hard): two correct answers shrink the cue (harder), one wrong
/// answer grows it (easier). Reports accuracy and the smallest cue reliably
/// discriminated. Adaptation changes only the cue, never master volume.
class ProsodySession {
  ProsodySession({
    this.task = ProsodyTask.questionStatement,
    this.maxTrials = 20,
    this.maxCue = 6.0,
    this.minCue = 0.5,
    this.step = 0.5,
    double? startCue,
  }) : cue = startCue ?? 4.0;

  final ProsodyTask task;
  final int maxTrials;
  final double maxCue;
  final double minCue;
  final double step;

  /// Current cue magnitude (semitones of excursion / emphasis).
  double cue;

  int _correct = 0;
  int _completed = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _consecutiveCorrect = 0;
  double _minCueCorrect = double.infinity;
  final List<bool> results = <bool>[];

  int get completedTrials => _completed;
  int get trialNumber => _completed + 1;
  int get correctCount => _correct;
  int get currentStreak => _streak;
  int get bestStreak => _bestStreak;
  bool get isComplete => _completed >= maxTrials;
  double get accuracy => _completed == 0 ? 0 : _correct / _completed;
  int get percent => (accuracy * 100).round();

  /// Smallest cue the listener answered correctly, or null if none yet — a
  /// research-only "prosodic sensitivity" indicator (smaller = better).
  double? get bestCue =>
      _minCueCorrect.isFinite ? _minCueCorrect : null;

  bool submit(ProsodyTrial trial, int chosenIndex) {
    final correct = trial.isCorrect(chosenIndex);
    _completed++;
    if (correct) {
      _correct++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      _consecutiveCorrect++;
      if (trial.cueSemitones < _minCueCorrect) {
        _minCueCorrect = trial.cueSemitones;
      }
      if (_consecutiveCorrect >= 2) {
        _consecutiveCorrect = 0;
        cue = (cue - step).clamp(minCue, maxCue);
      }
    } else {
      _streak = 0;
      _consecutiveCorrect = 0;
      cue = (cue + step).clamp(minCue, maxCue);
    }
    results.add(correct);
    return correct;
  }
}
