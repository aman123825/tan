import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/confusion_matrix.dart';
import 'package:hearbloom/core/protocol_engine.dart';
import 'package:hearbloom/core/training/consonant_training.dart';
import 'package:hearbloom/core/training/vowel_training.dart';
import 'package:hearbloom/features/common/audio_wave_animation.dart';
import 'package:hearbloom/features/common/encouragement.dart';
import 'package:hearbloom/features/common/live_chart.dart';
import 'package:hearbloom/features/common/stimulus_preview.dart';
import 'package:hearbloom/features/common/trial_scaffold.dart';
import 'package:hearbloom/features/report/confusion_matrix_page.dart';
import 'package:hearbloom/features/training/consonant_training_page.dart';
import 'package:hearbloom/features/training/vowel_training_page.dart';

void main() {
  // ================================================= Encouragement =========
  group('Encouragement', () {
    final rng = Random(1);

    test('celebrates a 3+ correct streak', () {
      final msg = Encouragement.forTrial(
        correct: true,
        streakAfter: 3,
        priorStreak: 2,
        completed: 5,
        total: 25,
        rng: rng,
      );
      expect(Encouragement.streak, contains(msg));
    });

    test('nudges after a wrong answer that broke a streak', () {
      final msg = Encouragement.forTrial(
        correct: false,
        streakAfter: 0,
        priorStreak: 4,
        completed: 6,
        total: 25,
        rng: rng,
      );
      expect(Encouragement.brokeStreak, contains(msg));
    });

    test('marks the halfway point exactly once', () {
      final msg = Encouragement.forTrial(
        correct: true,
        streakAfter: 1,
        priorStreak: 0,
        completed: 12, // floor(25/2)
        total: 25,
        rng: rng,
      );
      expect(Encouragement.halfway, contains(msg));
    });

    test('celebrates completion', () {
      final msg = Encouragement.forTrial(
        correct: true,
        streakAfter: 1,
        priorStreak: 0,
        completed: 25,
        total: 25,
        rng: rng,
      );
      expect(Encouragement.complete, contains(msg));
    });

    test('returns null for an ordinary correct answer', () {
      final msg = Encouragement.forTrial(
        correct: true,
        streakAfter: 1,
        priorStreak: 0,
        completed: 3,
        total: 25,
        rng: rng,
      );
      expect(msg, isNull);
    });
  });

  // ================================================= ConfusionMatrix =======
  group('ConfusionMatrix', () {
    test('tabulates counts, correct and errors', () {
      final m = ConfusionMatrix();
      m.record('b', 'b');
      m.record('b', 'p');
      m.record('b', 'p');
      m.record('p', 'p');
      expect(m.count('b', 'p'), 2);
      expect(m.count('b', 'b'), 1);
      expect(m.total, 4);
      expect(m.correct, 2); // b->b, p->p
      expect(m.errorCount, 2);
      expect(m.labels, ['b', 'p']); // sorted union
      expect(m.maxCount, 2);
    });

    test('ranks the most frequent confusion and summarises it', () {
      final m = ConfusionMatrix();
      for (var i = 0; i < 4; i++) {
        m.record('b', 'p'); // 4 b->p errors
      }
      m.record('d', 't'); // 1 d->t error
      m.record('b', 'b');
      final top = m.topConfusions(3);
      expect(top.first.target, 'b');
      expect(top.first.response, 'p');
      expect(top.first.count, 4);
      // 4 of 5 errors are b->p => 80%.
      expect(m.summary(), contains('confuse b with p'));
      expect(m.summary(), contains('80%'));
    });

    test('fromRecords ignores blank responses', () {
      final records = <TrialRecord>[
        TrialRecord(
            target: 'a', response: 'a', correct: true, latencyMs: 100),
        TrialRecord(
            target: 'a', response: '', correct: false, latencyMs: 100),
      ];
      final m = ConfusionMatrix.fromRecords(records);
      expect(m.total, 1);
      expect(m.correct, 1);
    });
  });

  // ================================================= Vowel training ========
  group('Vowel training core', () {
    test('has the 12 h_d vowels and a formant table', () {
      expect(kVowels.length, 12);
      expect(kVowels.first.word, 'heed');
      for (final v in kVowels) {
        expect(v.f1, greaterThan(0));
        expect(v.f2, greaterThan(v.f1));
      }
    });

    test('synthesizeVowel makes ~300ms of finite audio in range', () {
      final s = synthesizeVowel(kVowels.first);
      expect(s.length, closeTo(0.3 * kSampleRate, 2));
      expect(s.every((x) => x.isFinite), isTrue);
      expect(s.every((x) => x.abs() <= 1.0), isTrue);
      expect(rms(s), greaterThan(0));
    });

    test('level 1 is a 3AFC discrimination with one odd out', () {
      final gen = VowelTrainingGenerator(seed: 3);
      for (var i = 0; i < 20; i++) {
        final t = gen.next(1);
        expect(t.isDiscrimination, isTrue);
        expect(t.sequence.length, 3);
        expect(t.oddIndex, inInclusiveRange(0, 2));
        final odd = t.sequence[t.oddIndex];
        final others = <Vowel>[
          for (var j = 0; j < 3; j++)
            if (j != t.oddIndex) t.sequence[j]
        ];
        // The two non-odd items are identical and differ from the odd one.
        expect(others[0].id, others[1].id);
        expect(others[0].id, isNot(odd.id));
        expect(t.isCorrect(t.oddIndex), isTrue);
      }
    });

    test('levels 3/4/5 are identification with the right AFC and noise', () {
      final gen = VowelTrainingGenerator(seed: 2);
      final l3 = gen.next(3);
      expect(l3.choices.length, 4);
      expect(l3.inNoise, isFalse);
      expect(l3.choices[l3.targetIndex].id, l3.target.id);

      final l4 = gen.next(4);
      expect(l4.choices.length, 6);

      final l5 = gen.next(5);
      expect(l5.choices.length, 4);
      expect(l5.inNoise, isTrue);
      expect(l5.snrDb, 5);
    });

    test('session scores, completes and gates at 70%', () {
      final s = VowelTrainingSession(level: 3, maxTrials: 10);
      final gen = VowelTrainingGenerator(seed: 5);
      for (var i = 0; i < 10; i++) {
        final t = gen.next(3);
        s.submit(t, t.targetIndex); // always correct
      }
      expect(s.isComplete, isTrue);
      expect(s.percent, 100);
      expect(s.passed, isTrue);
      expect(s.results.length, 10);
    });
  });

  // ================================================= Consonant training ====
  group('Consonant training core', () {
    test('16 syllables listed; 12 have shipped assets', () {
      expect(kConsonants.length, 16);
      expect(kAvailableConsonants.length, 12);
      for (final id in ['za', 'la', 'ra', 'wa']) {
        expect(consonantById(id).hasAsset, isFalse);
      }
    });

    test('every generated choice at every level has a real asset', () {
      final gen = ConsonantTrainingGenerator(seed: 7);
      for (final level in [1, 2, 3, 4]) {
        for (var i = 0; i < 30; i++) {
          final t = gen.next(level);
          for (final c in t.choices) {
            expect(c.hasAsset, isTrue,
                reason: 'level $level drew ${c.id} without an asset');
          }
          expect(t.choices[t.targetIndex].id, t.target.id);
        }
      }
    });

    test('level AFC sizes and in-noise flag', () {
      final gen = ConsonantTrainingGenerator(seed: 1);
      expect(gen.next(1).choices.length, 2);
      expect(gen.next(2).choices.length, 4);
      expect(gen.next(3).choices.length, 6);
      final l4 = gen.next(4);
      expect(l4.choices.length, 4);
      expect(l4.inNoise, isTrue);
      expect(l4.snrDb, 5);
    });

    test('session default is 30 trials and passes at 70%', () {
      final s = ConsonantTrainingSession(level: 2);
      expect(s.maxTrials, 30);
      final gen = ConsonantTrainingGenerator(seed: 9);
      for (var i = 0; i < 30; i++) {
        final t = gen.next(2);
        // 21/30 correct = 70%.
        s.submit(
            t, i < 21 ? t.targetIndex : (t.targetIndex + 1) % t.choices.length);
      }
      expect(s.isComplete, isTrue);
      expect(s.percent, 70);
      expect(s.passed, isTrue);
    });
  });

  // ================================================= Widgets ================
  group('New widgets', () {
    testWidgets('LiveChart shows the running accuracy percentage',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: LiveChart(results: [true, false]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('AudioWaveAnimation renders idle without error',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: AudioWaveAnimation(active: false))),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AudioWaveAnimation), findsOneWidget);
    });

    testWidgets('StimulusPreview lists items and confirms', (tester) async {
      var started = false;
      var played = 0;
      await tester.pumpWidget(MaterialApp(
        home: StimulusPreview(
          title: 'Preview',
          items: const [
            StimulusPreviewItem(id: 'a', label: 'heed'),
            StimulusPreviewItem(id: 'b', label: 'had'),
          ],
          onPlay: (_) async => played++,
          onStart: () => started = true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('heed'), findsOneWidget);
      expect(find.text('had'), findsOneWidget);

      await tester.tap(find.text('heed'));
      await tester.pump();
      expect(played, 1);

      await tester.tap(find.byKey(const Key('stimulus-preview-start')));
      await tester.pump();
      expect(started, isTrue);
    });

    testWidgets('ConfusionMatrixPage shows the summary and grid',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ConfusionMatrixPage(matrix: ConfusionMatrixPage.sample()),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ConfusionMatrixView), findsOneWidget);
      expect(find.textContaining('confuse'), findsOneWidget);
    });

    testWidgets('TrialScaffold surfaces the live chart and encouragement',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: TrialScaffold(
          title: 'T',
          instruction: 'Listen',
          pills: [MetaPill(text: 'x')],
          transport: [],
          statusLeft: 'L',
          statusRight: 'R',
          liveResults: [true, true],
          encouragement: 'Great streak!',
          child: SizedBox(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(LiveChart), findsOneWidget);
      expect(find.text('Great streak!'), findsOneWidget);
    });
  });

  // ================================================= Page flows =============
  group('Training page flows', () {
    testWidgets('vowel page: preview -> play -> reveals the odd sound',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VowelTrainingPage(
          audioPort: SilentAudioPort(),
          seed: 0,
        ),
      ));
      await tester.pumpAndSettle();

      // Preview stage first.
      expect(find.byKey(const Key('stimulus-preview-start')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stimulus-preview-start')));
      await tester.pump();

      // Training stage: level pill + discrimination instruction.
      expect(find.text('Level 1/5'), findsOneWidget);
      expect(find.text('Listen, then tap the sound that was different.'),
          findsOneWidget);

      // Reconstruct the first trial (generator seed = pageSeed + level).
      final trial = VowelTrainingGenerator(seed: 1).next(1);
      final odd = trial.oddIndex;

      // Play (avoid pumpAndSettle while the equalizer animation is active).
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump();

      // Tap a wrong sound -> the correct one is revealed.
      final wrong = (odd + 1) % 3;
      await tester.tap(find.text('Sound ${wrong + 1}'));
      await tester.pump();
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('The correct answer was: Sound ${odd + 1}'),
          findsOneWidget);
    });

    testWidgets('consonant page: preview -> play -> scores a correct choice',
        (tester) async {
      final wavBytes = encodeWav16(
        tone(seconds: 0.2, freqHz: 300, amp: 0.3),
        sampleRate: 22050,
      );
      await tester.pumpWidget(MaterialApp(
        home: ConsonantTrainingPage(
          audioPort: SilentAudioPort(),
          seed: 0,
          assetLoader: (path) async => wavBytes,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stimulus-preview-start')));
      await tester.pump();

      expect(find.text('Level 1/4'), findsOneWidget);

      final trial = ConsonantTrainingGenerator(seed: 1).next(1);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text(trial.choices[trial.targetIndex].label));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });
  });
}
