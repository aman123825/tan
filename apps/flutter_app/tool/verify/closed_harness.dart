// Headless verification for closed-set identification + content pools.
//
//   dart run tool/verify/closed_harness.dart
import 'dart:io';
import 'dart:math';

import '../../lib/core/closed_set.dart';
import '../../lib/core/content_pools.dart';
import '../../lib/core/protocol_engine.dart';

int _checks = 0;
int _failures = 0;

void check(String name, bool condition) {
  _checks++;
  if (condition) {
    stdout.writeln('  ok   $name');
  } else {
    _failures++;
    stdout.writeln('  FAIL $name');
  }
}

void main() {
  // Generator.
  final gen = ClosedSetGenerator(pool: kDigitItems, choiceCount: 4, seed: 3);
  final t = gen.next();
  check('choice count respected', t.choices.length == 4);
  check('target is among choices', t.choices.any((c) => c.id == t.target.id));
  check('choices unique',
      t.choices.map((c) => c.id).toSet().length == t.choices.length);
  check('target index resolves',
      t.targetIndex >= 0 && t.choices[t.targetIndex].id == t.target.id);
  final g2 =
      ClosedSetGenerator(pool: kDigitItems, choiceCount: 4, seed: 3).next();
  check('deterministic target', g2.target.id == t.target.id);
  check(
      'deterministic order',
      g2.choices.map((c) => c.id).join(',') ==
          t.choices.map((c) => c.id).join(','));

  // Session scoring.
  final s =
      ClosedSetSession(moduleId: 'foundation', groupId: 'word', maxTrials: 5);
  check('correct choice', s.submit(t, t.targetIndex, latencyMs: 700));
  final wrongIdx = (t.targetIndex + 1) % t.choices.length;
  check('wrong choice', !s.submit(t, wrongIdx, latencyMs: 700));
  check('accuracy = 1/2', (s.accuracy - 0.5).abs() < 1e-9);
  check('records target id', s.records.first.target == t.target.id);
  check('records choices param', s.records.first.parameters['choices'] == 4);
  check('quiet run has no snr',
      !s.records.first.parameters.containsKey('snr_db'));
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  // Noise variant records snr_db.
  final n = ClosedSetSession(snrDb: 5, maxTrials: 5);
  n.submit(t, t.targetIndex, latencyMs: 500);
  check('noise run records snr', n.records.first.parameters['snr_db'] == 5);

  // Adaptive-noise variant: the SNR itself adapts 2-down/1-up (noisier when
  // correct), so recognition difficulty tracks the noise, not the item.
  final adaptive = ClosedSetSession(snrTrack: AdaptiveTrack.snr(), maxTrials: 100);
  final wrong2 = (t.targetIndex + 1) % t.choices.length;
  check('adaptive noise starts at 12 dB', adaptive.currentSnrDb == 12);
  adaptive.submit(t, t.targetIndex, latencyMs: 400); // correct #1
  check('adaptive: no move after 1 correct', adaptive.currentSnrDb == 12);
  adaptive.submit(t, t.targetIndex, latencyMs: 400); // correct #2 -> noisier
  check('adaptive: SNR drops after 2 correct', adaptive.currentSnrDb == 10);
  adaptive.submit(t, wrong2, latencyMs: 400); // wrong -> easier
  check('adaptive: SNR rises after wrong', adaptive.currentSnrDb == 12);
  check('adaptive: first trial presented at 12 dB',
      adaptive.records.first.parameters['snr_db'] == 12);
  check('adaptive: third trial presented at 10 dB',
      adaptive.records[2].parameters['snr_db'] == 10);
  check('adaptive threshold null before enough reversals',
      adaptive.thresholdSnrDb == null);

  // Content pools match generated corpora.
  check('digits pool = 10', kDigitItems.length == 10);
  check('letters pool = 26', kLetterItems.length == 26);
  check('phonemes pool = 12', kPhonemeItems.length == 12);
  check('words pool = 16', kWordItems.length == 16);
  check(
      'colors pool = 8 with swatch',
      kColorItems.length == 8 &&
          kColorItems.every((c) => c.swatchArgb != null));
  check('sentences pool = 10', kSentenceItems.length == 10);
  check('asset path shape',
      kDigitItems.first.assetPath == 'assets/stimuli/digits/digit_0.wav');

  // Matrix sentence.
  final m = buildMatrixSentence(Random(1));
  check('matrix: 5 words', m.text.split(' ').length == 5);
  check('matrix: 5 asset paths', m.assetPaths.length == 5);
  check('matrix: deterministic', buildMatrixSentence(Random(1)).text == m.text);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks closed checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks closed checks');
    exit(1);
  }
}
