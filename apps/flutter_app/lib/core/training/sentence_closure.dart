/// Auditory-verbal sentence-closure training (pure Dart).
///
/// A sentence is presented with its final word masked (noise/silence in the
/// page); the listener uses sentence context to pick the completing word from
/// four choices (4AFC). This trains top-down linguistic prediction — using
/// meaning to fill acoustic gaps (schema induction).
///
/// Deterministic generator over an original sentence bank; scores as 4AFC.
/// Flutter-free so it can be unit-tested headlessly.
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart';

/// A sentence-closure bank entry: a [frame] with a `___` blank, the correct
/// [answer], and three context-plausible-but-wrong [distractors].
class SentenceClosureItem {
  const SentenceClosureItem(this.frame, this.answer, this.distractors);

  final String frame;
  final String answer;
  final List<String> distractors;
}

/// Original sentence bank (highly predictable final word from context).
const List<SentenceClosureItem> kSentenceClosureBank = <SentenceClosureItem>[
  SentenceClosureItem('The dog chased the ___.', 'cat', ['book', 'lamp', 'song']),
  SentenceClosureItem('She poured the milk into a ___.', 'glass', ['shoe', 'road', 'cloud']),
  SentenceClosureItem('We watched the birds fly in the ___.', 'sky', ['sink', 'chair', 'plate']),
  SentenceClosureItem('He wrote his name with a ___.', 'pen', ['fork', 'brick', 'leaf']),
  SentenceClosureItem('The baby slept in the ___.', 'crib', ['oven', 'truck', 'pool']),
  SentenceClosureItem('Please turn off the ___ before bed.', 'light', ['grass', 'river', 'stone']),
  SentenceClosureItem('The chef cooked dinner in the ___.', 'kitchen', ['garden', 'library', 'stadium']),
  SentenceClosureItem('We planted flowers in the ___.', 'garden', ['pocket', 'ceiling', 'engine']),
  SentenceClosureItem('The teacher wrote on the ___.', 'board', ['ocean', 'pillow', 'ladder']),
  SentenceClosureItem('I drank a cup of hot ___.', 'tea', ['sand', 'wire', 'rock']),
  SentenceClosureItem('The rain fell from the dark ___.', 'clouds', ['floors', 'spoons', 'shirts']),
  SentenceClosureItem('He kicked the soccer ___.', 'ball', ['moon', 'desk', 'coat']),
  SentenceClosureItem('She brushed her ___ every morning.', 'teeth', ['fence', 'clock', 'boat']),
  SentenceClosureItem('The fish swam in the ___.', 'water', ['closet', 'meadow', 'attic']),
  SentenceClosureItem('We drove the car down the ___.', 'road', ['spoon', 'cloud', 'shelf']),
  SentenceClosureItem('The sun is very bright at ___.', 'noon', ['ink', 'wool', 'clay']),
  SentenceClosureItem('He read a bedtime ___ to the kids.', 'story', ['hammer', 'bicycle', 'blanket']),
  SentenceClosureItem('The farmer milked the ___.', 'cow', ['van', 'pin', 'jet']),
  SentenceClosureItem('She wore a warm ___ in winter.', 'coat', ['drum', 'lake', 'nail']),
  SentenceClosureItem('The bee landed on the ___.', 'flower', ['engine', 'window', 'pocket']),
  SentenceClosureItem('We roasted marshmallows over the ___.', 'fire', ['book', 'sock', 'map']),
  SentenceClosureItem('The bird built a ___ in the tree.', 'nest', ['boat', 'lamp', 'cup']),
  SentenceClosureItem('He hammered the ___ into the wood.', 'nail', ['cloud', 'apple', 'river']),
  SentenceClosureItem('The doctor listened to my ___.', 'heart', ['fence', 'wagon', 'candle']),
];

/// One sentence-closure trial: a [frame] with a blank, the four [choices], the
/// [correctIndex] and the canonical [answer].
class SentenceClosureTrial {
  const SentenceClosureTrial({
    required this.frame,
    required this.choices,
    required this.correctIndex,
    required this.answer,
  });

  final String frame;
  final List<String> choices;
  final int correctIndex;
  final String answer;

  /// The frame with the blank shown as a bracketed placeholder.
  String get maskedFrame => frame.replaceAll('___', '⟨ ? ⟩');

  bool isCorrect(int i) => i == correctIndex;

  /// Convert to a shared [FourAlternativeTrial] for uniform scoring.
  FourAlternativeTrial toFourAfc() =>
      FourAlternativeTrial(choices: choices, targetIndex: correctIndex);
}

/// Deterministic generator over the sentence bank.
///
/// [next] takes the response-set size for the trial: 2–4 choices use the
/// item's own distractors; larger sets are padded with other bank items'
/// answer words (deterministic, no duplicates) — the response-set-size
/// continuum from easy closed-set to nearly-open-set responding.
class SentenceClosureGenerator {
  SentenceClosureGenerator({int seed = 0, List<SentenceClosureItem>? bank})
      : _rng = Random(seed),
        _bank = bank ?? kSentenceClosureBank;

  final Random _rng;
  final List<SentenceClosureItem> _bank;

  SentenceClosureTrial next({int choiceCount = 4}) {
    final item = _bank[_rng.nextInt(_bank.length)];
    final distractors = List<String>.of(item.distractors)..shuffle(_rng);
    final pool = <String>{item.answer};
    for (final d in distractors) {
      if (pool.length >= choiceCount) break;
      pool.add(d);
    }
    if (pool.length < choiceCount) {
      // Pad with other items' answers (seeded order, no duplicates).
      final extras = <String>[
        for (final other in _bank)
          if (!pool.contains(other.answer)) other.answer,
      ]..shuffle(_rng);
      for (final e in extras) {
        if (pool.length >= choiceCount) break;
        pool.add(e);
      }
    }
    final choices = pool.toList()..shuffle(_rng);
    return SentenceClosureTrial(
      frame: item.frame,
      choices: choices,
      correctIndex: choices.indexOf(item.answer),
      answer: item.answer,
    );
  }
}

/// The adaptive response-set sizes, easy → hard.
const List<int> kClosureChoiceLevels = <int>[2, 3, 4, 6, 8];

/// Sequences and scores a sentence-closure run.
///
/// Difficulty ADAPTS on response-set size (2 → 8 choices,
/// [kClosureChoiceLevels]) with a 2-up/1-down rule: two consecutive correct
/// answers widen the set (harder), one error narrows it (easier). SAFETY:
/// only the choice count adapts — never audio level.
class SentenceClosureSession {
  SentenceClosureSession({
    this.moduleId = 'openset',
    this.groupId = 'sentence_closure',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
    int startLevelIndex = 2,
  }) : _levelIndex =
            startLevelIndex.clamp(0, kClosureChoiceLevels.length - 1);

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];

  int _levelIndex;
  int _streak = 0;
  int _maxChoicesReached = 0;

  /// Response-set size for the next trial.
  int get currentChoiceCount => kClosureChoiceLevels[_levelIndex];

  /// The largest response set the listener reached this run.
  int get maxChoicesReached => _maxChoicesReached;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    SentenceClosureTrial trial,
    int chosenIndex, {
    required int latencyMs,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final choicesAtPresentation = trial.choices.length;
    if (choicesAtPresentation > _maxChoicesReached) {
      _maxChoicesReached = choicesAtPresentation;
    }
    records.add(
      TrialRecord(
        target: trial.answer,
        response: (chosenIndex >= 0 && chosenIndex < trial.choices.length)
            ? trial.choices[chosenIndex]
            : '',
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'frame': trial.frame,
          'choices': choicesAtPresentation,
        },
      ),
    );
    // 2-up/1-down on the response-set-size ladder.
    if (correct) {
      _streak++;
      if (_streak >= 2) {
        _streak = 0;
        if (_levelIndex < kClosureChoiceLevels.length - 1) _levelIndex++;
      }
    } else {
      _streak = 0;
      if (_levelIndex > 0) _levelIndex--;
    }
    return correct;
  }
}
