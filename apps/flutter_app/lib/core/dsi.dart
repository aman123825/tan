/// Dichotic Sentence Identification (DSI) logic (pure Dart).
///
/// Each trial presents a *different* short sentence to each ear at the same
/// time (dichotic). Two response paradigms are supported:
///   • [DsiMode.freeRecall]: identify BOTH sentences from a closed set of six.
///   • [DsiMode.directed]: identify only the cued ear's sentence from six.
/// Results are tracked per ear and an ear advantage (right − left, in points)
/// is derived (Fifer et al., 1983).
///
/// SAFETY: nothing here changes master volume. Each sentence is synthesised as
/// a speech-like placeholder (a labelled demonstration proxy — NOT recorded
/// speech and not validated clinical DSI material) and combined with
/// [encodeWavStereo16] so the per-ear split is preserved. Verified headlessly.
library;

import 'dart:math';
import 'dart:typed_data';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Ear a stimulus is delivered to.
enum DsiEar { left, right }

extension DsiEarInfo on DsiEar {
  String get label => this == DsiEar.left ? 'LEFT' : 'RIGHT';
  String get id => this == DsiEar.left ? 'left' : 'right';
}

/// DSI response paradigm.
enum DsiMode {
  /// Report BOTH sentences (order-independent).
  freeRecall,

  /// Report only the cued ear's sentence.
  directed,
}

/// Ten short sentences used by the demonstration DSI.
const List<String> kDsiSentences = <String>[
  'the boy runs home',
  'she reads a book',
  'the dog is black',
  'we eat rice today',
  'open the red door',
  'birds fly very high',
  'he drinks cold water',
  'the sun is bright',
  'put the cup down',
  'they walk to school',
];

/// Synthesises a mono speech-like placeholder for [sentence] (one
/// amplitude-shaped tone burst per word at a per-sentence base pitch). A
/// labelled demonstration proxy — NOT recorded speech.
List<double> dsiSentencePlaceholder(String sentence, {int sampleRate = kSampleRate}) {
  final words = sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final rng = Random(sentence.hashCode & 0x7fffffff);
  final basePitch = 140.0 + rng.nextInt(80); // 140–220 Hz "voice"
  final out = <double>[];
  for (final w in words) {
    final durSec = (0.13 + w.length * 0.02).clamp(0.11, 0.30);
    final f = basePitch * (0.85 + rng.nextDouble() * 0.5);
    final fundamental =
        tone(seconds: durSec, freqHz: f, amp: 0.24, sampleRate: sampleRate);
    final harmonic =
        tone(seconds: durSec, freqHz: f * 2, amp: 0.07, sampleRate: sampleRate);
    for (var j = 0; j < fundamental.length; j++) {
      out.add(fundamental[j] + (j < harmonic.length ? harmonic[j] : 0.0));
    }
    out.addAll(silence(0.05, sampleRate));
  }
  return out;
}

/// Builds a dichotic stereo DSI stimulus: [leftSentence] in the left ear,
/// [rightSentence] in the right ear, at once. Returns a 16-bit stereo WAV.
Uint8List buildDsiStimulus({
  required String leftSentence,
  required String rightSentence,
  int sampleRate = kSampleRate,
}) {
  final l = dsiSentencePlaceholder(leftSentence, sampleRate: sampleRate);
  final r = dsiSentencePlaceholder(rightSentence, sampleRate: sampleRate);
  return encodeWavStereo16(l, r, sampleRate: sampleRate);
}

/// One DSI trial: the sentence in each ear, the cued ear (used in directed
/// mode) and a shuffled closed set of six sentences (including both targets).
class DsiTrial {
  const DsiTrial({
    required this.leftSentence,
    required this.rightSentence,
    required this.cuedEar,
    required this.choices,
  });

  final String leftSentence;
  final String rightSentence;
  final DsiEar cuedEar;
  final List<String> choices;

  String sentenceFor(DsiEar ear) =>
      ear == DsiEar.left ? leftSentence : rightSentence;

  /// The cued-ear target (directed mode).
  String get cuedSentence => sentenceFor(cuedEar);
}

/// Deterministic DSI trial generator. In directed mode the cued ear alternates
/// each trial for balance.
class DsiGenerator {
  DsiGenerator({int seed = 0, this.choiceCount = 6}) : _rng = Random(seed);

  final int choiceCount;
  final Random _rng;
  int _trial = 0;

  DsiTrial next({DsiEar? forceEar}) {
    final pool = List<String>.of(kDsiSentences)..shuffle(_rng);
    final left = pool[0];
    final right = pool[1];
    final distractors = pool.skip(2).take(choiceCount - 2).toList();
    final choices = <String>[left, right, ...distractors]..shuffle(_rng);
    final ear = forceEar ?? (_trial.isEven ? DsiEar.right : DsiEar.left);
    _trial++;
    return DsiTrial(
      leftSentence: left,
      rightSentence: right,
      cuedEar: ear,
      choices: choices,
    );
  }
}

/// Sequences and scores a DSI run, tracking per-ear accuracy.
class DsiSession {
  DsiSession({
    this.moduleId = 'auditory',
    this.groupId = 'dsi',
    this.dsiMode = DsiMode.freeRecall,
    this.maxTrials = 20,
    this.mode = ProtocolMode.test,
  });

  final String moduleId;
  final String groupId;
  final DsiMode dsiMode;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  int _leftCorrect = 0;
  int _leftTotal = 0;
  int _rightCorrect = 0;
  int _rightTotal = 0;

  bool get showsFeedback => mode == ProtocolMode.training;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;
  bool get isComplete => records.length >= maxTrials;

  bool hasEar(DsiEar ear) =>
      ear == DsiEar.left ? _leftTotal > 0 : _rightTotal > 0;

  double get leftAccuracy => _leftTotal == 0 ? 0 : _leftCorrect / _leftTotal;
  double get rightAccuracy => _rightTotal == 0 ? 0 : _rightCorrect / _rightTotal;
  int get leftPercent => (leftAccuracy * 100).round();
  int get rightPercent => (rightAccuracy * 100).round();

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Right-ear advantage in points (right% − left%). Positive = right ear
  /// stronger, the typical dichotic pattern.
  double get rightEarAdvantage => (rightAccuracy - leftAccuracy) * 100;

  /// Directed mode: score only the cued ear from a single [choice].
  bool submitDirected(DsiTrial trial, String choice, {required int latencyMs}) {
    final correct = choice == trial.cuedSentence;
    if (trial.cuedEar == DsiEar.left) {
      _leftTotal++;
      if (correct) _leftCorrect++;
    } else {
      _rightTotal++;
      if (correct) _rightCorrect++;
    }
    records.add(TrialRecord(
      target: trial.cuedSentence,
      response: choice,
      correct: correct,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'mode': 'directed',
        'cued_ear': trial.cuedEar.id,
      },
    ));
    return correct;
  }

  /// Free-recall mode: score BOTH ears from the [selected] sentences
  /// (order-independent). Returns whether both were correct.
  bool submitFreeRecall(
    DsiTrial trial,
    Set<String> selected, {
    required int latencyMs,
  }) {
    final leftOk = selected.contains(trial.leftSentence);
    final rightOk = selected.contains(trial.rightSentence);
    _leftTotal++;
    if (leftOk) _leftCorrect++;
    _rightTotal++;
    if (rightOk) _rightCorrect++;
    records.add(TrialRecord(
      target: '${trial.leftSentence} | ${trial.rightSentence}',
      response: selected.join(', '),
      correct: leftOk && rightOk,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'mode': 'free_recall',
        'left_correct': leftOk,
        'right_correct': rightOk,
      },
    ));
    return leftOk && rightOk;
  }
}
