/// Staggered Spondaic Word (SSW) test logic (pure Dart).
///
/// Each trial presents two spondees (two-syllable compound words) offset in
/// time and split across the ears (word 1 → right, word 2 → left) so that the
/// inner syllables *overlap*:
///
/// ```
///   right ear:  [ air | plane ]                 (word 1)
///   left ear:          [ base | ball ]          (word 2)
///                 RNC    RC/LC    LNC
/// ```
///
/// This yields four scoring conditions — Right Non-Competing (RNC), Right
/// Competing (RC), Left Competing (LC) and Left Non-Competing (LNC) — the
/// Buffalo-model layout (Katz, 1962). The listener reports the two words heard;
/// because responses are whole words, each ear's word maps to its two
/// conditions (documented demonstration simplification, not clinical scoring).
///
/// SAFETY: nothing here changes master volume. The staggered stereo timing is
/// synthesised with tone bursts (a labelled demonstration proxy — NOT recorded
/// speech and not validated clinical SSW material) and is verified headlessly.
library;

import 'dart:math';
import 'dart:typed_data';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// A spondaic word split into its two equal-stress syllables.
class Spondee {
  const Spondee(this.word, this.syllable1, this.syllable2);

  final String word;
  final String syllable1;
  final String syllable2;
}

/// Twenty spondees used by the demonstration SSW.
const List<Spondee> kSpondees = <Spondee>[
  Spondee('airplane', 'air', 'plane'),
  Spondee('baseball', 'base', 'ball'),
  Spondee('cowboy', 'cow', 'boy'),
  Spondee('hotdog', 'hot', 'dog'),
  Spondee('birthday', 'birth', 'day'),
  Spondee('sunset', 'sun', 'set'),
  Spondee('football', 'foot', 'ball'),
  Spondee('popcorn', 'pop', 'corn'),
  Spondee('doorbell', 'door', 'bell'),
  Spondee('rainbow', 'rain', 'bow'),
  Spondee('toothbrush', 'tooth', 'brush'),
  Spondee('cupcake', 'cup', 'cake'),
  Spondee('mailbox', 'mail', 'box'),
  Spondee('pancake', 'pan', 'cake'),
  Spondee('railroad', 'rail', 'road'),
  Spondee('seesaw', 'see', 'saw'),
  Spondee('starfish', 'star', 'fish'),
  Spondee('sidewalk', 'side', 'walk'),
  Spondee('snowman', 'snow', 'man'),
  Spondee('daylight', 'day', 'light'),
];

/// The four SSW scoring conditions (Buffalo model).
enum SswCondition {
  /// Right Non-Competing (word 1, first syllable — right ear only).
  rnc,

  /// Right Competing (word 1, second syllable — overlaps word 2).
  rc,

  /// Left Competing (word 2, first syllable — overlaps word 1).
  lc,

  /// Left Non-Competing (word 2, second syllable — left ear only).
  lnc,
}

extension SswConditionInfo on SswCondition {
  String get label => switch (this) {
        SswCondition.rnc => 'RNC',
        SswCondition.rc => 'RC',
        SswCondition.lc => 'LC',
        SswCondition.lnc => 'LNC',
      };

  String get description => switch (this) {
        SswCondition.rnc => 'Right non-competing',
        SswCondition.rc => 'Right competing',
        SswCondition.lc => 'Left competing',
        SswCondition.lnc => 'Left non-competing',
      };
}

/// Syllable duration (seconds) for the synthesised spondee.
const double kSswSyllableSeconds = 0.35;

/// Builds a staggered stereo SSW stimulus. Word 1 ([right]) plays in the right
/// ear, word 2 ([left]) in the left ear, offset by one syllable so the inner
/// syllables overlap in time. Each syllable is a distinct tone burst (a
/// demonstration proxy for speech). Returns a 16-bit stereo WAV.
Uint8List buildSswStimulus({
  required Spondee right,
  required Spondee left,
  double syllableSeconds = kSswSyllableSeconds,
  int sampleRate = kSampleRate,
}) {
  final syl = (syllableSeconds * sampleRate).round();
  final total = syl * 3; // three syllable slots: R1 | R2+L1 | L2

  final rCh = List<double>.filled(total, 0.0);
  final lCh = List<double>.filled(total, 0.0);

  // Deterministic per-word pitches so the two words sound distinct.
  double pitch(String w) => 200.0 + (w.hashCode & 0x7fff) % 260; // 200–460 Hz

  void place(List<double> ch, int slot, double freq) {
    final burst = tone(
        seconds: syllableSeconds, freqHz: freq, amp: 0.5, sampleRate: sampleRate);
    final start = slot * syl;
    for (var i = 0; i < burst.length && start + i < ch.length; i++) {
      ch[start + i] += burst[i];
    }
  }

  final rBase = pitch(right.word);
  final lBase = pitch(left.word);
  // Word 1 (right): syllable 1 in slot 0 (RNC), syllable 2 in slot 1 (RC).
  place(rCh, 0, rBase);
  place(rCh, 1, rBase * 1.12);
  // Word 2 (left): syllable 1 in slot 1 (LC), syllable 2 in slot 2 (LNC).
  place(lCh, 1, lBase);
  place(lCh, 2, lBase * 1.12);

  return encodeWavStereo16(lCh, rCh, sampleRate: sampleRate);
}

/// One SSW trial: [right] (word 1) and [left] (word 2) plus a shuffled
/// closed-set of six spondee words (including both targets).
class SswTrial {
  const SswTrial({
    required this.right,
    required this.left,
    required this.choices,
  });

  final Spondee right;
  final Spondee left;
  final List<String> choices;

  bool rightCorrect(Set<String> selected) => selected.contains(right.word);
  bool leftCorrect(Set<String> selected) => selected.contains(left.word);
}

/// Deterministic SSW trial generator.
class SswGenerator {
  SswGenerator({int seed = 0, this.choiceCount = 6}) : _rng = Random(seed);

  final int choiceCount;
  final Random _rng;

  SswTrial next() {
    final pool = List<Spondee>.of(kSpondees)..shuffle(_rng);
    final right = pool[0];
    final left = pool[1];
    final distractors = pool.skip(2).take(choiceCount - 2).toList();
    final choices = <String>[right.word, left.word, ...distractors.map((s) => s.word)]
      ..shuffle(_rng);
    return SswTrial(right: right, left: left, choices: choices);
  }
}

/// Sequences and scores an SSW run, tallying per-condition correctness.
class SswSession {
  SswSession({
    this.moduleId = 'auditory',
    this.groupId = 'ssw',
    this.maxTrials = 20,
    this.mode = ProtocolMode.test,
  });

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  final Map<SswCondition, int> _correct = {
    for (final c in SswCondition.values) c: 0,
  };
  final Map<SswCondition, int> _total = {
    for (final c in SswCondition.values) c: 0,
  };

  bool get showsFeedback => mode == ProtocolMode.training;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;
  bool get isComplete => records.length >= maxTrials;

  /// Percent correct for [condition] (0 if none presented yet).
  int percent(SswCondition condition) {
    final t = _total[condition]!;
    if (t == 0) return 0;
    return ((_correct[condition]! / t) * 100).round();
  }

  int correctFor(SswCondition condition) => _correct[condition]!;
  int totalFor(SswCondition condition) => _total[condition]!;

  /// Overall percent correct across all four conditions.
  int get totalPercent {
    final c = _correct.values.reduce((a, b) => a + b);
    final t = _total.values.reduce((a, b) => a + b);
    return t == 0 ? 0 : ((c / t) * 100).round();
  }

  /// Records a trial from the set of [selected] words. The right word maps to
  /// RNC + RC, the left word to LC + LNC.
  ///
  /// Returns whether *both* words were reported correctly.
  bool submit(
    SswTrial trial,
    Set<String> selected, {
    required int latencyMs,
  }) {
    final rOk = trial.rightCorrect(selected);
    final lOk = trial.leftCorrect(selected);
    _total[SswCondition.rnc] = _total[SswCondition.rnc]! + 1;
    _total[SswCondition.rc] = _total[SswCondition.rc]! + 1;
    _total[SswCondition.lc] = _total[SswCondition.lc]! + 1;
    _total[SswCondition.lnc] = _total[SswCondition.lnc]! + 1;
    if (rOk) {
      _correct[SswCondition.rnc] = _correct[SswCondition.rnc]! + 1;
      _correct[SswCondition.rc] = _correct[SswCondition.rc]! + 1;
    }
    if (lOk) {
      _correct[SswCondition.lc] = _correct[SswCondition.lc]! + 1;
      _correct[SswCondition.lnc] = _correct[SswCondition.lnc]! + 1;
    }
    records.add(TrialRecord(
      target: '${trial.right.word} | ${trial.left.word}',
      response: selected.join(', '),
      correct: rOk && lOk,
      latencyMs: latencyMs,
      parameters: <String, Object?>{
        'right_word': trial.right.word,
        'left_word': trial.left.word,
        'right_correct': rOk,
        'left_correct': lOk,
      },
    ));
    return rOk && lOk;
  }

  /// Buffalo-model interpretation from the overall error rate and the
  /// competing-vs-non-competing pattern. Research demonstration only.
  String interpret() {
    if (completedTrials == 0) return 'No trials completed.';
    final competing =
        ((percent(SswCondition.rc) + percent(SswCondition.lc)) / 2).round();
    final nonCompeting =
        ((percent(SswCondition.rnc) + percent(SswCondition.lnc)) / 2).round();
    final total = totalPercent;
    final buffer = StringBuffer();
    if (total >= 90) {
      buffer.write('Overall $total% is within the typical range. ');
    } else if (total >= 75) {
      buffer.write('Overall $total% is mildly reduced. ');
    } else {
      buffer.write('Overall $total% is notably reduced. ');
    }
    if (nonCompeting - competing >= 15) {
      buffer.write(
          'Competing conditions ($competing%) are weaker than non-competing '
          '($nonCompeting%), the classic SSW pattern.');
    } else {
      buffer.write(
          'Competing ($competing%) and non-competing ($nonCompeting%) are '
          'similar.');
    }
    return buffer.toString();
  }
}
