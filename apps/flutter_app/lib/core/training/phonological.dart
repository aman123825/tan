/// Phonological-awareness training games (pure Dart).
///
/// Three child-friendly sub-games that train pre-literacy sound skills:
///  * Rhyming — pick the word that rhymes with the target (3AFC).
///  * Sound blending — blend spoken phonemes into a word (pick / type).
///  * Sound deletion — say a word with one sound removed (pick / type).
///
/// Deterministic generators (seeded) draw from small word banks; the session
/// scores per game. Flutter-free so it can be unit-tested headlessly; the page
/// maps trials to a child-friendly UI and speaks the prompt.
library;

import 'dart:math';

import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// The three phonological games.
enum PhonoGame { rhyming, blending, deletion }

extension PhonoGameInfo on PhonoGame {
  String get title => switch (this) {
        PhonoGame.rhyming => 'Rhyming',
        PhonoGame.blending => 'Sound Blending',
        PhonoGame.deletion => 'Sound Deletion',
      };

  String get groupId => switch (this) {
        PhonoGame.rhyming => 'phono_rhyming',
        PhonoGame.blending => 'phono_blending',
        PhonoGame.deletion => 'phono_deletion',
      };
}

/// One phonological trial: a [prompt], the item(s) to [speak], the closed-set
/// [choices], the [correctIndex] and the canonical [answer] (for typed input).
class PhonologicalTrial {
  const PhonologicalTrial({
    required this.game,
    required this.prompt,
    required this.speak,
    required this.choices,
    required this.correctIndex,
    required this.answer,
  });

  final PhonoGame game;
  final String prompt;

  /// Words or phoneme labels the page should present/speak (e.g. `['k','a','t']`).
  final List<String> speak;
  final List<String> choices;
  final int correctIndex;
  final String answer;

  bool isCorrectIndex(int i) => i == correctIndex;

  /// Normalized whole-word comparison for typed answers.
  bool isCorrectText(String typed) =>
      _normalize(typed) == _normalize(answer);

  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
}

/// A rhyming bank entry: a target and words that rhyme / do not rhyme with it.
class _RhymeItem {
  const _RhymeItem(this.target, this.rhymes, this.nonRhymes);
  final String target;
  final List<String> rhymes;
  final List<String> nonRhymes;
}

const List<_RhymeItem> _rhymeBank = <_RhymeItem>[
  _RhymeItem('cat', ['bat', 'hat', 'mat', 'rat'], ['dog', 'sun', 'cup', 'pen']),
  _RhymeItem('dog', ['log', 'fog', 'frog', 'hog'], ['cat', 'car', 'bed', 'top']),
  _RhymeItem('sun', ['run', 'bun', 'fun', 'gun'], ['moon', 'sky', 'cup', 'leg']),
  _RhymeItem('bee', ['tree', 'key', 'sea', 'knee'], ['bird', 'fish', 'hand', 'cup']),
  _RhymeItem('cake', ['lake', 'rake', 'snake', 'bake'], ['milk', 'ball', 'nose', 'fish']),
  _RhymeItem('ball', ['wall', 'tall', 'fall', 'call'], ['bat', 'cup', 'sun', 'dog']),
  _RhymeItem('star', ['car', 'jar', 'far', 'bar'], ['moon', 'tree', 'shoe', 'hand']),
  _RhymeItem('light', ['night', 'kite', 'bite', 'white'], ['dark', 'lamp', 'sun', 'book']),
  _RhymeItem('bug', ['rug', 'mug', 'hug', 'jug'], ['ant', 'fly', 'cup', 'bed']),
  _RhymeItem('house', ['mouse', 'blouse'], ['home', 'door', 'roof', 'wall']),
];

/// A blending bank entry: phonemes that blend into a [word], plus distractors.
class _BlendItem {
  const _BlendItem(this.phonemes, this.word, this.distractors);
  final List<String> phonemes;
  final String word;
  final List<String> distractors;
}

const List<_BlendItem> _blendBank = <_BlendItem>[
  _BlendItem(['k', 'a', 't'], 'cat', ['dog', 'cap', 'kit']),
  _BlendItem(['d', 'o', 'g'], 'dog', ['dig', 'cat', 'log']),
  _BlendItem(['s', 'u', 'n'], 'sun', ['sit', 'son', 'fun']),
  _BlendItem(['b', 'e', 'd'], 'bed', ['bad', 'bee', 'red']),
  _BlendItem(['f', 'i', 'sh'], 'fish', ['dish', 'fin', 'wish']),
  _BlendItem(['m', 'a', 'p'], 'map', ['mop', 'cap', 'man']),
  _BlendItem(['h', 'a', 't'], 'hat', ['hit', 'cat', 'hot']),
  _BlendItem(['c', 'u', 'p'], 'cup', ['cap', 'pup', 'cop']),
  _BlendItem(['p', 'e', 'n'], 'pen', ['pin', 'pan', 'ten']),
  _BlendItem(['b', 'u', 's'], 'bus', ['bug', 'bat', 'gus']),
];

/// A deletion bank entry: [word] minus [deletePhoneme] gives [answer].
class _DeleteItem {
  const _DeleteItem(this.word, this.deletePhoneme, this.answer, this.distractors);
  final String word;
  final String deletePhoneme;
  final String answer;
  final List<String> distractors;
}

const List<_DeleteItem> _deleteBank = <_DeleteItem>[
  _DeleteItem('cart', 'k', 'art', ['car', 'cat', 'tart']),
  _DeleteItem('spin', 's', 'pin', ['pit', 'spot', 'win']),
  _DeleteItem('stop', 's', 'top', ['step', 'pot', 'stop']),
  _DeleteItem('cup', 'k', 'up', ['cap', 'pup', 'cop']),
  _DeleteItem('gate', 'g', 'ate', ['gap', 'late', 'get']),
  _DeleteItem('block', 'b', 'lock', ['back', 'clock', 'rock']),
  _DeleteItem('snail', 's', 'nail', ['sail', 'mail', 'snap']),
  _DeleteItem('train', 't', 'rain', ['tan', 'brain', 'trap']),
  _DeleteItem('play', 'p', 'lay', ['pay', 'clay', 'plan']),
  _DeleteItem('fear', 'f', 'ear', ['far', 'hear', 'fee']),
];

/// Deterministic generator for one phonological [game].
class PhonologicalGenerator {
  PhonologicalGenerator(this.game, {int seed = 0}) : _rng = Random(seed);

  final PhonoGame game;
  final Random _rng;

  PhonologicalTrial next() {
    switch (game) {
      case PhonoGame.rhyming:
        return _rhyming();
      case PhonoGame.blending:
        return _blending();
      case PhonoGame.deletion:
        return _deletion();
    }
  }

  PhonologicalTrial _rhyming() {
    final item = _rhymeBank[_rng.nextInt(_rhymeBank.length)];
    final correct = item.rhymes[_rng.nextInt(item.rhymes.length)];
    final distractors = List<String>.of(item.nonRhymes)..shuffle(_rng);
    final choices = <String>[correct, distractors[0], distractors[1]]
      ..shuffle(_rng);
    return PhonologicalTrial(
      game: game,
      prompt: 'Which word rhymes with “${item.target.toUpperCase()}”?',
      speak: <String>[item.target],
      choices: choices,
      correctIndex: choices.indexOf(correct),
      answer: correct,
    );
  }

  PhonologicalTrial _blending() {
    final item = _blendBank[_rng.nextInt(_blendBank.length)];
    final distractors = List<String>.of(item.distractors)..shuffle(_rng);
    final choices = <String>[item.word, distractors[0], distractors[1]]
      ..shuffle(_rng);
    return PhonologicalTrial(
      game: game,
      prompt: 'Blend the sounds — what word is it?',
      speak: item.phonemes,
      choices: choices,
      correctIndex: choices.indexOf(item.word),
      answer: item.word,
    );
  }

  PhonologicalTrial _deletion() {
    final item = _deleteBank[_rng.nextInt(_deleteBank.length)];
    final distractors = List<String>.of(item.distractors)..shuffle(_rng);
    final choices = <String>[item.answer, distractors[0], distractors[1]]
      ..shuffle(_rng);
    return PhonologicalTrial(
      game: game,
      prompt: 'Say “${item.word.toUpperCase()}” without the /${item.deletePhoneme}/ sound.',
      speak: <String>[item.word],
      choices: choices,
      correctIndex: choices.indexOf(item.answer),
      answer: item.answer,
    );
  }
}

/// Sequences and scores a single phonological game.
class PhonologicalSession {
  PhonologicalSession({
    this.moduleId = 'learning',
    required this.game,
    this.maxTrials = 15,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final PhonoGame game;
  final int maxTrials;
  final ProtocolMode mode;

  String get groupId => game.groupId;

  final List<TrialRecord> records = <TrialRecord>[];

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  bool submit(
    PhonologicalTrial trial,
    int chosenIndex, {
    required int latencyMs,
  }) {
    final correct = trial.isCorrectIndex(chosenIndex);
    records.add(
      TrialRecord(
        target: trial.answer,
        response:
            (chosenIndex >= 0 && chosenIndex < trial.choices.length)
                ? trial.choices[chosenIndex]
                : '',
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{'game': game.name},
      ),
    );
    return correct;
  }
}
