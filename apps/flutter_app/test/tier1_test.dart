import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/dsi.dart';
import 'package:hearbloom/core/lisns.dart';
import 'package:hearbloom/core/ssw.dart';
import 'package:hearbloom/core/training/dichotic_integration.dart';
import 'package:hearbloom/features/common/countdown_ring.dart';
import 'package:hearbloom/features/common/level_progress_map.dart';
import 'package:hearbloom/features/common/response_time_flash.dart';
import 'package:hearbloom/features/common/trial_scaffold.dart';
import 'package:hearbloom/features/dsi/dsi_page.dart';
import 'package:hearbloom/features/lisns/lisns_page.dart';
import 'package:hearbloom/features/questionnaires/hhie_page.dart';
import 'package:hearbloom/features/questionnaires/ssq12_page.dart';
import 'package:hearbloom/features/ssw/ssw_page.dart';
import 'package:hearbloom/features/training/dichotic_integration_page.dart';

/// Reads the NumChannels field (offset 22, uint16 LE) from a WAV header.
int _channels(List<int> wav) => wav[22] | (wav[23] << 8);

void main() {
  // ============================================================ LiSN-S ======
  group('LiSN-S core', () {
    test('condition flags (spatial / different talker)', () {
      expect(LisnsCondition.sameTalker0.spatial, isFalse);
      expect(LisnsCondition.sameTalker0.differentTalker, isFalse);
      expect(LisnsCondition.sameTalker90.spatial, isTrue);
      expect(LisnsCondition.diffTalker0.differentTalker, isTrue);
      expect(LisnsCondition.diffTalker90.spatial, isTrue);
      expect(LisnsCondition.diffTalker90.differentTalker, isTrue);
    });

    test('masker story fills the requested length', () {
      final m = lisnsMaskerStory(seed: 1, seconds: 1.0, sampleRate: 8000);
      expect(m.length, 8000);
    });

    test('buildLisnsStimulus returns a stereo WAV (both conditions)', () {
      final target = tone(seconds: 0.3, freqHz: 220, amp: 0.3, sampleRate: 8000);
      final masker = lisnsMaskerStory(seed: 2, seconds: 0.5, sampleRate: 8000);
      for (final c in LisnsCondition.values) {
        final wav = buildLisnsStimulus(
          target: target,
          masker: masker,
          condition: c,
          snrDb: 2,
          sampleRate: 8000,
        );
        expect(_channels(wav), 2, reason: '${c.id} must be stereo');
        expect(wav.length, greaterThan(44));
      }
    });

    test('session interleaves conditions and derives SRTs + advantages', () {
      final s = LisnsSession(maxTrialsPerCondition: 3);
      final seen = <LisnsCondition, int>{};
      var guard = 0;
      while (!s.isComplete && guard++ < 200) {
        final c = s.currentCondition;
        seen[c] = (seen[c] ?? 0) + 1;
        // Easy conditions answered correctly more often -> lower (better) SRT.
        final correct = c == LisnsCondition.diffTalker90 ||
            c == LisnsCondition.sameTalker90;
        s.submit(
          c,
          target: 'the boy runs home',
          response: correct ? 'the boy runs home' : 'no idea',
          scoreFraction: correct ? 1.0 : 0.0,
          latencyMs: 500,
        );
      }
      expect(s.isComplete, isTrue);
      expect(s.completedTrials, 12); // 4 conditions x 3
      for (final c in LisnsCondition.values) {
        expect(seen[c], 3);
        expect(s.srtFor(c), isNotNull);
      }
      // Advantages are finite doubles (may be positive or negative).
      expect(s.talkerAdvantage.isFinite, isTrue);
      expect(s.spatialAdvantage.isFinite, isTrue);
      expect(s.totalAdvantage.isFinite, isTrue);
    });
  });

  // =============================================================== SSW ======
  group('SSW core', () {
    test('20 spondees, each with two syllables', () {
      expect(kSpondees.length, 20);
      for (final s in kSpondees) {
        expect(s.syllable1, isNotEmpty);
        expect(s.syllable2, isNotEmpty);
      }
    });

    test('generator yields 6 choices including both targets', () {
      final t = SswGenerator(seed: 3).next();
      expect(t.choices.length, 6);
      expect(t.choices, contains(t.right.word));
      expect(t.choices, contains(t.left.word));
      expect(t.right.word, isNot(t.left.word));
    });

    test('buildSswStimulus is stereo', () {
      final t = SswGenerator(seed: 0).next();
      final wav = buildSswStimulus(
          right: t.right, left: t.left, sampleRate: 8000);
      expect(_channels(wav), 2);
    });

    test('scoring maps right word -> RNC/RC and left word -> LC/LNC', () {
      final s = SswSession(maxTrials: 1);
      final t = SswGenerator(seed: 5).next();
      // Report only the RIGHT word: right conditions correct, left conditions 0.
      s.submit(t, <String>{t.right.word}, latencyMs: 400);
      expect(s.percent(SswCondition.rnc), 100);
      expect(s.percent(SswCondition.rc), 100);
      expect(s.percent(SswCondition.lc), 0);
      expect(s.percent(SswCondition.lnc), 0);
      expect(s.totalPercent, 50);
    });

    test('interpretation reflects overall accuracy', () {
      final s = SswSession(maxTrials: 2);
      final g = SswGenerator(seed: 9);
      for (var i = 0; i < 2; i++) {
        final t = g.next();
        s.submit(t, <String>{t.right.word, t.left.word}, latencyMs: 300);
      }
      expect(s.totalPercent, 100);
      expect(s.interpret(), contains('within the typical range'));
    });
  });

  // =============================================================== DSI ======
  group('DSI core', () {
    test('10 sentences; generator gives 6 choices incl. both ears', () {
      expect(kDsiSentences.length, 10);
      final t = DsiGenerator(seed: 1).next();
      expect(t.choices.length, 6);
      expect(t.choices, contains(t.leftSentence));
      expect(t.choices, contains(t.rightSentence));
    });

    test('directed mode alternates the cued ear', () {
      final g = DsiGenerator(seed: 2);
      final a = g.next();
      final b = g.next();
      expect(a.cuedEar, isNot(b.cuedEar));
    });

    test('buildDsiStimulus is stereo', () {
      final wav = buildDsiStimulus(
        leftSentence: 'she reads a book',
        rightSentence: 'the dog is black',
        sampleRate: 8000,
      );
      expect(_channels(wav), 2);
    });

    test('free-recall per-ear scoring and ear advantage', () {
      final s = DsiSession(maxTrials: 1);
      final t = DsiGenerator(seed: 4).next();
      // Report only the right sentence -> right 100%, left 0% -> REA +100.
      s.submitFreeRecall(t, <String>{t.rightSentence}, latencyMs: 500);
      expect(s.rightPercent, 100);
      expect(s.leftPercent, 0);
      expect(s.rightEarAdvantage, 100);
    });

    test('directed mode scores only the cued ear', () {
      final s = DsiSession(dsiMode: DsiMode.directed, maxTrials: 1);
      final t = DsiGenerator(seed: 6).next();
      final correct =
          s.submitDirected(t, t.cuedSentence, latencyMs: 400);
      expect(correct, isTrue);
      if (t.cuedEar == DsiEar.right) {
        expect(s.rightPercent, 100);
      } else {
        expect(s.leftPercent, 100);
      }
    });
  });

  // ============================================ Dichotic Integration ========
  group('Dichotic integration core', () {
    test('starts at 10 dB and reduces the gap after two correct', () {
      final s = DichoticIntegrationSession(maxTrials: 10);
      expect(s.currentLevelDiffDb, 10);
      final g = DichoticIntegrationGenerator(seed: 0);
      final t1 = g.next();
      s.submit(t1, t1.targetDigit, latencyMs: 300); // correct #1
      expect(s.currentLevelDiffDb, 10); // 2-down: no change after one
      final t2 = g.next();
      s.submit(t2, t2.targetDigit, latencyMs: 300); // correct #2 -> harder
      expect(s.currentLevelDiffDb, 8);
      expect(s.minLevelDiffDb, 8);
    });

    test('wrong answer never pushes the gap above the start', () {
      final s = DichoticIntegrationSession(maxTrials: 10);
      final g = DichoticIntegrationGenerator(seed: 1);
      final t = g.next();
      final wrong = t.targetDigit == '0' ? '1' : '0';
      s.submit(t, wrong, latencyMs: 300);
      expect(s.currentLevelDiffDb, lessThanOrEqualTo(10));
    });

    test('generator picks a distinct distractor', () {
      for (var seed = 0; seed < 20; seed++) {
        final t = DichoticIntegrationGenerator(seed: seed).next();
        expect(t.targetDigit, isNot(t.distractorDigit));
      }
    });

    test('stimulus is stereo', () {
      final tgt = tone(seconds: 0.2, freqHz: 300, amp: 0.4, sampleRate: 8000);
      final dis = tone(seconds: 0.2, freqHz: 500, amp: 0.4, sampleRate: 8000);
      final wav = buildDichoticIntegrationStimulus(
        target: tgt,
        distractor: dis,
        trainedEar: TrainedEar.left,
        levelDiffDb: 10,
        sampleRate: 8000,
      );
      expect(_channels(wav), 2);
    });
  });

  // ============================================================= SSQ12 ======
  group('SSQ12 scoring', () {
    test('12 items, four per section', () {
      expect(Ssq12.items.length, 12);
      for (final section in Ssq12Section.values) {
        final n = Ssq12.items.where((i) => i.section == section).length;
        expect(n, 4, reason: '${section.label} should have 4 items');
      }
    });

    test('section and overall means', () {
      // Speech = 10, Spatial = 0, Qualities = 5 -> overall = 5.
      final answers = <double>[
        10, 10, 10, 10, // speech
        0, 0, 0, 0, // spatial
        5, 5, 5, 5, // qualities
      ];
      expect(Ssq12.sectionMean(answers, Ssq12Section.speech), 10);
      expect(Ssq12.sectionMean(answers, Ssq12Section.spatial), 0);
      expect(Ssq12.sectionMean(answers, Ssq12Section.qualities), 5);
      expect(Ssq12.overallMean(answers), 5);
    });
  });

  // ============================================================= HHIE-S =====
  group('HHIE-S scoring', () {
    test('10 items, five emotional and five social', () {
      expect(HhieScreening.items.length, 10);
      final e = HhieScreening.items
          .where((i) => i.subscale == HhieSubscale.emotional)
          .length;
      final s = HhieScreening.items
          .where((i) => i.subscale == HhieSubscale.social)
          .length;
      expect(e, 5);
      expect(s, 5);
    });

    test('Yes=4 / Sometimes=2 / No=0 totals and cut-off', () {
      final allYes = List<int>.filled(10, 0); // option index 0 = Yes
      final allNo = List<int>.filled(10, 2); // option index 2 = No
      expect(HhieScreening.total(allYes), 40);
      expect(HhieScreening.total(allNo), 0);
      expect(HhieScreening.maxScore, 40);
      expect(HhieScreening.suggestsHandicap(10), isFalse); // > 10 needed
      expect(HhieScreening.suggestsHandicap(12), isTrue);
      expect(HhieScreening.interpretation(0), contains('no self-perceived'));
    });
  });

  // ===================================================== Common widgets =====
  group('Countdown ring', () {
    testWidgets('renders and fires onComplete after its duration',
        (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CountdownRing(
              duration: const Duration(milliseconds: 400),
              onComplete: () => done = true,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(CountdownRing), findsOneWidget);
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(done, isTrue);
    });
  });

  group('Level progress map', () {
    testWidgets('shows the current level text', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LevelProgressMap(
              currentLevel: 1, totalLevels: 5, completedLevels: 1),
        ),
      ));
      await tester.pump(); // not pumpAndSettle: current dot pulses forever
      expect(find.text('Level 2/5'), findsOneWidget);
    });
  });

  group('Response time flash', () {
    testWidgets('shows the latency in ms', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: ResponseTimeFlash(latencyMs: 620))),
      ));
      await tester.pump();
      expect(find.text('620 ms'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // finite fade-out
    });
  });

  group('TrialScaffold number-key answering', () {
    testWidgets('a digit key invokes onDigitKey', (tester) async {
      int? pressed;
      await tester.pumpWidget(MaterialApp(
        home: TrialScaffold(
          title: 'T',
          instruction: 'i',
          pills: const [],
          transport: const [],
          statusLeft: '',
          statusRight: '',
          onDigitKey: (d) => pressed = d,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pump();
      expect(pressed, 3);
    });
  });

  // ======================================================= Page smoke =======
  group('Tier-1 page flows', () {
    testWidgets('SSW auto-plays, scores two words, advances', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = SilentAudioPort();
      await tester.pumpWidget(MaterialApp(
        home: SswPage(comfortableLevel: 0.4, maxTrials: 3, seed: 0, audioPort: port),
      ));
      await tester.pump(); // countdown showing
      await tester.pump(const Duration(seconds: 3)); // countdown -> auto-play
      await tester.pump();
      expect(port.playCount, greaterThanOrEqualTo(1));

      final t = SswGenerator(seed: 0).next();
      await tester.tap(find.text(t.right.word));
      await tester.pump();
      await tester.tap(find.text(t.left.word));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('DSI (free recall) auto-plays and scores both', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = SilentAudioPort();
      await tester.pumpWidget(MaterialApp(
        home: DsiPage(comfortableLevel: 0.4, maxTrials: 3, seed: 0, audioPort: port),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(port.playCount, greaterThanOrEqualTo(1));

      final t = DsiGenerator(seed: 0).next();
      await tester.tap(find.text(t.leftSentence));
      await tester.pump();
      await tester.tap(find.text(t.rightSentence));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('Dichotic integration auto-plays and scores a digit',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = SilentAudioPort();
      final wav = encodeWav16(
          tone(seconds: 0.2, freqHz: 300, amp: 0.3), sampleRate: 8000);
      await tester.pumpWidget(MaterialApp(
        home: DichoticIntegrationPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 0,
          audioPort: port,
          assetLoader: (path) async => wav,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(port.playCount, greaterThanOrEqualTo(1));

      final t = DichoticIntegrationGenerator(seed: 0).next();
      await tester.tap(find.text(t.targetDigit));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('LiSN-S auto-plays, scores a typed answer, advances',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = SilentAudioPort();
      final wav = encodeWav16(
          tone(seconds: 0.3, freqHz: 220, amp: 0.3), sampleRate: 8000);
      await tester.pumpWidget(MaterialApp(
        home: LisnsPage(
          comfortableLevel: 0.4,
          seed: 0,
          audioPort: port,
          assetLoader: (path) async => wav,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(port.playCount, greaterThanOrEqualTo(1));

      // First target sentence is kLisnsTargetSentences[0].
      await tester.enterText(
          find.byType(TextField), kLisnsTargetSentences[0].text);
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('SSQ12 shows a result after See result', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: Ssq12Page()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ssq12-see-result')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ssq12-result')), findsOneWidget);
    });

    testWidgets('HHIE-S computes a total once all answered', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: HhiePage()));
      await tester.pumpAndSettle();
      // Answer every item "No" (option index 2) -> total 0.
      for (var i = 0; i < HhieScreening.items.length; i++) {
        await tester.tap(find.byKey(Key('hhie-$i-opt2')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('hhie-see-result')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hhie-result')), findsOneWidget);
      expect(find.text('0 / 40'), findsOneWidget);
    });
  });
}
