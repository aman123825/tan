/// Demo corpus content pools (pure Dart), matching the WAV assets produced by
/// `tools/generate_demo_assets.py`. All are Indian-English `demo_only`
/// demonstration material, not validated clinical stimuli.
library;

import 'dart:math';

import 'audio/timbre.dart';
import 'closed_set.dart';
import 'identification.dart';

String _asset(String dir, String file) => 'assets/stimuli/$dir/$file.wav';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Spoken digits 0–9 (shown as numerals).
final List<ClosedSetItem> kDigitItems = <ClosedSetItem>[
  for (var i = 0; i < 10; i++)
    ClosedSetItem(
      id: 'digit_$i',
      label: '$i',
      assetPath: _asset('digits', 'digit_$i'),
    ),
];

/// Spoken letters a–z (shown uppercase).
final List<ClosedSetItem> kLetterItems = <ClosedSetItem>[
  for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++)
    ClosedSetItem(
      id: 'letter_${String.fromCharCode(c)}',
      label: String.fromCharCode(c).toUpperCase(),
      assetPath: _asset('letters', 'letter_${String.fromCharCode(c)}'),
    ),
];

/// Minimal-pair CV syllables for phoneme-contrast tasks.
const List<String> _phonemes = <String>[
  'ba',
  'pa',
  'da',
  'ta',
  'ga',
  'ka',
  'ma',
  'na',
  'sa',
  'sha',
  'fa',
  'va'
];
final List<ClosedSetItem> kPhonemeItems = <ClosedSetItem>[
  for (final s in _phonemes)
    ClosedSetItem(
        id: 'syl_$s', label: s, assetPath: _asset('phonemes', 'syl_$s')),
];

/// Everyday word bank (closed-set word / CNC).
const List<String> _words = <String>[
  'bell',
  'ball',
  'bat',
  'bag',
  'pen',
  'pin',
  'cup',
  'cap',
  'dog',
  'cat',
  'book',
  'key',
  'ship',
  'chip',
  'boat',
  'coat'
];
final List<ClosedSetItem> kWordItems = <ClosedSetItem>[
  for (final w in _words)
    ClosedSetItem(
        id: 'word_$w', label: w, assetPath: _asset('words', 'word_$w')),
];

/// Named colors with display swatches (0xAARRGGBB).
const Map<String, int> _colors = <String, int>{
  'red': 0xFFD32F2F,
  'green': 0xFF388E3C,
  'blue': 0xFF1976D2,
  'yellow': 0xFFFBC02D,
  'orange': 0xFFF57C00,
  'purple': 0xFF7B1FA2,
  'black': 0xFF000000,
  'white': 0xFFECEFF1,
};
final List<ClosedSetItem> kColorItems = <ClosedSetItem>[
  for (final e in _colors.entries)
    ClosedSetItem(
      id: 'color_${e.key}',
      label: e.key,
      assetPath: _asset('colors', 'color_${e.key}'),
      swatchArgb: e.value,
    ),
];

/// Everyday sentences (id -> text), for closed/open sentence recognition.
const Map<String, String> _sentences = <String, String>{
  's1': 'the boy runs home',
  's2': 'she reads a book',
  's3': 'the dog is black',
  's4': 'we eat rice today',
  's5': 'open the red door',
  's6': 'birds fly very high',
  's7': 'he drinks cold water',
  's8': 'the sun is bright',
  's9': 'put the cup down',
  's10': 'they walk to school',
};
final List<ClosedSetItem> kSentenceItems = <ClosedSetItem>[
  for (final e in _sentences.entries)
    ClosedSetItem(
      id: e.key,
      label: e.value,
      assetPath: _asset('sentences', e.key),
    ),
];

/// Matrix-sentence slots (5 slots × 10 alternatives).
const List<String> kMatrixOrder = <String>[
  'name',
  'verb',
  'number',
  'adjective',
  'object'
];
const Map<String, List<String>> kMatrixSlots = <String, List<String>>{
  'name': [
    'peter',
    'thomas',
    'lucy',
    'alan',
    'nina',
    'rachel',
    'david',
    'sara',
    'john',
    'emma'
  ],
  'verb': [
    'has',
    'wants',
    'gives',
    'buys',
    'sees',
    'keeps',
    'sells',
    'holds',
    'brings',
    'takes'
  ],
  'number': [
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'twelve'
  ],
  'adjective': [
    'red',
    'green',
    'blue',
    'big',
    'small',
    'old',
    'new',
    'dark',
    'pink',
    'white'
  ],
  'object': [
    'toys',
    'pens',
    'books',
    'cups',
    'rings',
    'chairs',
    'desks',
    'shoes',
    'bags',
    'cards'
  ],
};

/// A concatenated matrix sentence: display [text] and the ordered [assetPaths]
/// of its five words (decoded and joined at runtime).
class MatrixSentence {
  const MatrixSentence(this.text, this.assetPaths);

  final String text;
  final List<String> assetPaths;
}

/// Deterministically builds one matrix sentence (one word per slot).
MatrixSentence buildMatrixSentence(Random rng) {
  final words = <String>[];
  final paths = <String>[];
  for (final slot in kMatrixOrder) {
    final options = kMatrixSlots[slot]!;
    final w = options[rng.nextInt(options.length)];
    words.add(w);
    paths.add(_asset('matrix', 'matrix_${slot}_$w'));
  }
  return MatrixSentence(words.join(' '), paths);
}

// ---------------------------------------------------------------------------
// Identification choice pools (for the generic IdentificationPage).
// ---------------------------------------------------------------------------

/// Synthesized instrument choices (audio synthesized at runtime).
final List<IdentificationChoice> kInstrumentChoices = <IdentificationChoice>[
  for (final i in kInstruments) IdentificationChoice(id: i, label: _cap(i)),
];

/// Public-domain melody choices (audio synthesized at runtime).
final List<IdentificationChoice> kMelodyChoices = <IdentificationChoice>[
  for (final m in kMelodyIds)
    IdentificationChoice(id: m, label: kMelodyTitles[m] ?? m),
];

/// Synthesized environmental sound-effect choices (demonstrations).
final List<IdentificationChoice> kEnvironmentChoices = <IdentificationChoice>[
  for (final s in kSfx) IdentificationChoice(id: s, label: _cap(s)),
];

/// Food picture choices (emoji picture + spoken-name asset).
const Map<String, String> _foodEmoji = <String, String>{
  'apple': '🍎',
  'banana': '🍌',
  'grapes': '🍇',
  'pizza': '🍕',
  'bread': '🍞',
  'egg': '🥚',
};
final List<IdentificationChoice> kFoodChoices = <IdentificationChoice>[
  for (final e in _foodEmoji.entries)
    IdentificationChoice(
      id: e.key,
      label: _cap(e.key),
      emoji: e.value,
      assetPath: _asset('food', 'food_${e.key}'),
    ),
];

/// Animal picture choices (emoji picture + spoken-name asset).
const Map<String, String> _animalEmoji = <String, String>{
  'dog': '🐶',
  'cat': '🐱',
  'elephant': '🐘',
  'fish': '🐟',
  'bird': '🐤',
  'cow': '🐄',
};
final List<IdentificationChoice> kAnimalChoices = <IdentificationChoice>[
  for (final e in _animalEmoji.entries)
    IdentificationChoice(
      id: e.key,
      label: _cap(e.key),
      emoji: e.value,
      assetPath: _asset('animals', 'animal_${e.key}'),
    ),
];

/// Talker/voice choices for speaker identification (each voice says one word).
final List<IdentificationChoice> kSpeakerChoices = <IdentificationChoice>[
  IdentificationChoice(
      id: 'v1', label: 'Voice A', assetPath: _asset('speaker', 'speaker_v1')),
  IdentificationChoice(
      id: 'v2', label: 'Voice B', assetPath: _asset('speaker', 'speaker_v2')),
  IdentificationChoice(
      id: 'v3', label: 'Voice C', assetPath: _asset('speaker', 'speaker_v3')),
  IdentificationChoice(
      id: 'v4', label: 'Voice D', assetPath: _asset('speaker', 'speaker_v4')),
];
