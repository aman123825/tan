/// Auditory-Closure *training* protocol logic (pure Dart).
///
/// A spoken word has a central portion replaced by white noise (as if part of
/// the signal were lost). The listener must "fill in" the missing piece and
/// identify the word from a closed set of four. The proportion of the word
/// masked adapts: a two-correct streak raises the mask (harder), a wrong answer
/// lowers it (easier), bounded to [minMask] .. [maxMask].
///
/// SAFETY: adaptation changes the masked *fraction* of the word, never master
/// volume. The DSP helper is pure and audio-plugin-free so it can be verified
/// headlessly.
library;

import 'dart:math';

import '../audio/pcm_synth.dart' show kSampleRate, whiteNoise, rms;
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// Replaces the central [maskFraction] (0..1) of [samples] with white noise
/// whose RMS matches the original signal, modelling a mid-word signal dropout.
/// The mask is level-matched (not louder) so it never boosts output level.
List<double> maskMiddle(
  List<double> samples,
  double maskFraction, {
  int seed = 7,
}) {
  final frac = maskFraction.clamp(0.0, 1.0);
  if (frac <= 0 || samples.isEmpty) return List<double>.of(samples);
  final out = List<double>.of(samples);
  final maskLen = (samples.length * frac).round();
  if (maskLen <= 0) return out;
  final start = ((samples.length - maskLen) / 2).round().clamp(0, samples.length);
  final end = (start + maskLen).clamp(0, samples.length);
  final signalRms = rms(samples);
  // amp 1.0 white noise has RMS ~0.577; scale to match the word's RMS so the
  // masking noise is at a comparable level, never louder.
  final noise = whiteNoise(
    seconds: (end - start) / kSampleRate,
    amp: signalRms <= 0 ? 0.2 : (signalRms / 0.577).clamp(0.0, 0.95),
    seed: seed,
  );
  for (var i = start; i < end; i++) {
    out[i] = i - start < noise.length ? noise[i - start] : 0.0;
  }
  return out;
}

/// A single auditory-closure trial: the target [word] plus the closed set of
/// [choices] (always contains [word]).
class AuditoryClosureTrial {
  AuditoryClosureTrial({required this.word, required this.choices})
      : assert(choices.contains(word));

  final String word;
  final List<String> choices;

  int get targetIndex => choices.indexOf(word);

  bool isCorrect(int chosenIndex) => chosenIndex == targetIndex;
}

/// Deterministic generator: draws a target word and [choiceCount] - 1 distinct
/// distractors from [pool].
class AuditoryClosureGenerator {
  AuditoryClosureGenerator({
    required this.pool,
    int seed = 0,
    this.choiceCount = 4,
  })  : assert(pool.length >= choiceCount),
        _rng = Random(seed);

  final List<String> pool;
  final int choiceCount;
  final Random _rng;

  AuditoryClosureTrial next() {
    final ti = _rng.nextInt(pool.length);
    final word = pool[ti];
    final choices = <String>[word];
    final available = List<int>.generate(pool.length, (i) => i)
      ..remove(ti)
      ..shuffle(_rng);
    for (final idx in available) {
      if (choices.length >= choiceCount) break;
      choices.add(pool[idx]);
    }
    choices.shuffle(_rng);
    return AuditoryClosureTrial(word: word, choices: choices);
  }
}

/// Sequences and scores an auditory-closure run with adaptive mask fraction.
class AuditoryClosureSession {
  AuditoryClosureSession({
    this.moduleId = 'auditory',
    this.groupId = 'auditory_closure',
    this.startMask = 0.30,
    this.minMask = 0.30,
    this.maxMask = 0.60,
    this.maskStep = 0.10,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  })  : assert(minMask <= startMask && startMask <= maxMask),
        _mask = startMask,
        _maxMaskReached = startMask;

  final String moduleId;
  final String groupId;
  final double startMask;
  final double minMask;
  final double maxMask;
  final double maskStep;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  double _mask;
  double _maxMaskReached;
  int _consecutiveCorrect = 0;

  /// Masked fraction (0..1) for the next trial.
  double get currentMask => _mask;
  int get currentMaskPercent => (_mask * 100).round();

  /// Largest mask fraction the listener handled correctly-streaked up to.
  double get maxMaskReached => _maxMaskReached;
  int get maxMaskPercent => (_maxMaskReached * 100).round();

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  int get percent => (accuracy * 100).round();

  double _clampMask(double v) {
    final clamped = v.clamp(minMask, maxMask).toDouble();
    return double.parse(clamped.toStringAsFixed(2));
  }

  bool submit(
    AuditoryClosureTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final maskAtPresentation = _mask;
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(
      TrialRecord(
        target: trial.word,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{'mask_fraction': maskAtPresentation},
      ),
    );
    if (correct) {
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= 2) {
        _mask = _clampMask(_mask + maskStep);
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _mask = _clampMask(_mask - maskStep);
    }
    if (_mask > _maxMaskReached) _maxMaskReached = _mask;
    return correct;
  }
}
