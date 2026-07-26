import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/gamification.dart';
import 'package:hearbloom/core/training/auditory_closure.dart';
import 'package:hearbloom/core/training/competing_speakers.dart';
import 'package:hearbloom/core/training/continuum.dart';
import 'package:hearbloom/core/training/following_directions.dart';
import 'package:hearbloom/core/training/phonemic_contrast.dart';
import 'package:hearbloom/core/training/speed_training.dart';
import 'package:hearbloom/core/training/working_memory.dart';
import 'package:hearbloom/data/gamification_store.dart';
import 'package:hearbloom/features/gamification/gamification_overlay.dart';
import 'package:hearbloom/features/training/closure_training_page.dart';
import 'package:hearbloom/features/training/competing_speakers_page.dart';
import 'package:hearbloom/features/training/compressed_training_page.dart';
import 'package:hearbloom/features/training/continuum_page.dart';
import 'package:hearbloom/features/training/following_directions_page.dart';
import 'package:hearbloom/features/training/phonemic_contrast_page.dart';
import 'package:hearbloom/features/training/working_memory_page.dart';

Uint8List _demoWav() =>
    encodeWav16(tone(seconds: 0.1, freqHz: 300, amp: 0.3), sampleRate: 8000);

void main() {
  // ================================================================== core ==
  group('Competing speakers core', () {
    test('generator yields a distinct distractor and a 4-choice set', () {
      final g = CompetingSpeakersGenerator(seed: 0);
      for (var i = 0; i < 20; i++) {
        final t = g.next();
        expect(t.target, isNot(equals(t.distractor)));
        expect(t.choices.length, 4);
        expect(t.choices, contains(t.target));
      }
    });

    test('level difference falls 2 dB after two correct, rises after a miss',
        () {
      final s = CompetingSpeakersSession(maxTrials: 20);
      expect(s.currentLevelDiffDb, 10);
      final trial = CompetingSpeakersTrial(
          target: 'A', distractor: 'B', choices: const ['A', 'B', 'C', 'D']);
      s.submit(trial, 0, latencyMs: 1); // correct
      expect(s.currentLevelDiffDb, 10); // 1 correct → no move
      s.submit(trial, 0, latencyMs: 1); // 2nd correct
      expect(s.currentLevelDiffDb, 8); // harder
      s.submit(trial, 0, latencyMs: 1); // correct @8 → min tracked
      expect(s.minLevelDiffDb, 8);

      final s2 = CompetingSpeakersSession();
      s2.submit(trial, 1, latencyMs: 1); // wrong (chose B)
      expect(s2.currentLevelDiffDb, 12); // easier
    });
  });

  group('Speed training core', () {
    test('timeScale shortens (>1×) and stretches (<1×)', () {
      final input = List<double>.generate(1000, (i) => i.toDouble());
      expect(timeScale(input, 2.0).length, closeTo(500, 1));
      expect(timeScale(input, 0.8).length, closeTo(1250, 1));
      expect(timeScale(input, 1.0).length, 1000);
    });

    test('speed climbs after two correct and drops after a miss', () {
      final s = SpeedTrainingSession(maxTrials: 20);
      expect(s.currentSpeed, 1.0);
      const t = SpeedTrainingTrial('the cat sat', <String>[]);
      s.submit(t, 'the cat sat', latencyMs: 1); // 1.0 word accuracy
      expect(s.currentSpeed, 1.0);
      s.submit(t, 'the cat sat', latencyMs: 1);
      expect(s.currentSpeed, closeTo(1.1, 1e-9));
      expect(s.maxSpeedReached, closeTo(1.1, 1e-9));
      s.submit(t, 'nonsense', latencyMs: 1); // 0 accuracy → slower
      expect(s.currentSpeed, closeTo(1.0, 1e-9));
    });

    test('speed is bounded to [0.8, 2.0]', () {
      final s = SpeedTrainingSession(maxTrials: 100);
      const t = SpeedTrainingTrial('one two', <String>[]);
      for (var i = 0; i < 40; i++) {
        s.submit(t, 'one two', latencyMs: 1);
      }
      expect(s.currentSpeed, lessThanOrEqualTo(2.0));
      expect(s.maxSpeedReached, lessThanOrEqualTo(2.0));
    });
  });

  group('Phonemic contrast core', () {
    test('pool has ten pairs and the generator honours the tier', () {
      expect(kMinimalPairs.length, 10);
      final g = PhonemicContrastGenerator(seed: 0);
      final t = g.next(1);
      expect(t.pair.tier, 1);
      expect(t.choices.length, 2);
      expect(t.choices, contains(t.target));
    });

    test('tier climbs after two correct and drops after a miss', () {
      final s = PhonemicContrastSession(maxTrials: 30);
      expect(s.currentTier, 1);
      final tr = PhonemicContrastTrial(
          pair: kMinimalPairs[0],
          choices: const ['bat', 'pat'],
          targetIndex: 0);
      s.submit(tr, 0, latencyMs: 1); // correct
      expect(s.currentTier, 1);
      s.submit(tr, 0, latencyMs: 1); // 2nd correct
      expect(s.currentTier, 2);
      expect(s.maxTierReached, 2);
      s.submit(tr, 1, latencyMs: 1); // wrong
      expect(s.currentTier, 1);
    });
  });

  group('Auditory closure core', () {
    test('maskMiddle replaces the central region and preserves the edges', () {
      final input = List<double>.filled(100, 0.5);
      final masked = maskMiddle(input, 0.3, seed: 1);
      expect(masked.length, 100);
      expect(masked.first, 0.5);
      expect(masked.last, 0.5);
      final mid = masked.sublist(35, 65);
      expect(mid.any((x) => x != 0.5), isTrue);
      expect(maskMiddle(input, 0).length, 100); // ratio 0 → no-op
    });

    test('mask grows on a correct streak and shrinks on a miss', () {
      final s = AuditoryClosureSession(maxTrials: 20);
      expect(s.currentMaskPercent, 30);
      final tr = AuditoryClosureTrial(
          word: 'bell', choices: const ['bell', 'ball', 'bat', 'bag']);
      s.submit(tr, 0, latencyMs: 1);
      s.submit(tr, 0, latencyMs: 1); // two correct
      expect(s.currentMaskPercent, 40);
      expect(s.maxMaskPercent, 40);
      s.submit(tr, 1, latencyMs: 1); // wrong
      expect(s.currentMaskPercent, 30);
    });
  });

  group('Continuum core', () {
    test('level 1 is a three-tone oddball', () {
      final t = ContinuumSession(seed: 0).nextTrial();
      expect(t.level, 1);
      expect(t.kind, ContinuumTrialKind.toneOddball);
      expect(t.choices, const ['First', 'Second', 'Third']);
      expect(t.baseFreqHz, isNotNull);
      expect(t.oddFreqHz, isNotNull);
    });

    test('passing a level (>=80%) advances; failing ends the run', () {
      final pass = ContinuumSession(seed: 0, trialsPerLevel: 5);
      for (var i = 0; i < 5; i++) {
        final tr = pass.nextTrial();
        pass.submit(tr, tr.targetIndex, latencyMs: 1); // all correct
      }
      expect(pass.currentLevel, 2);
      expect(pass.highestLevel, 2);
      expect(pass.isComplete, isFalse);

      final fail = ContinuumSession(seed: 0, trialsPerLevel: 5);
      for (var i = 0; i < 5; i++) {
        final tr = fail.nextTrial();
        final wrong = (tr.targetIndex + 1) % tr.choices.length;
        fail.submit(tr, wrong, latencyMs: 1); // all wrong
      }
      expect(fail.isComplete, isTrue);
      expect(fail.highestLevel, 1);
    });
  });

  group('Working memory core', () {
    test('span trial expected order (forward/backward) and matching', () {
      const fwd = SpanTrial([1, 2, 3], backward: false);
      expect(fwd.expected, [1, 2, 3]);
      const bwd = SpanTrial([1, 2, 3], backward: true);
      expect(bwd.expected, [3, 2, 1]);
      expect(bwd.matches([3, 2, 1]), isTrue);
      expect(bwd.matches([1, 2, 3]), isFalse);
    });

    test('span length adapts and tracks the longest correct span', () {
      final s = SpanSession(maxTrials: 10, seed: 1);
      expect(s.currentLength, 3);
      final t1 = s.next();
      s.submit(t1, t1.expected, latencyMs: 1);
      final t2 = s.next();
      s.submit(t2, t2.expected, latencyMs: 1);
      expect(s.currentLength, 4); // +1 after two correct
      expect(s.maxSpan, 3);
      final t3 = s.next();
      s.submit(t3, const [99], latencyMs: 1); // wrong
      expect(s.currentLength, 3); // -1
    });

    test('n-back targets are the n-back repeats; N adapts', () {
      const b = NBackBlock([5, 5, 3, 3], 1);
      expect(b.targets, {1, 3});
      final s = NBackSession(maxTrials: 10, seed: 1);
      expect(s.currentN, 1);
      final b1 = s.next();
      s.submit(b1, b1.targets, latencyMs: 1);
      final b2 = s.next();
      s.submit(b2, b2.targets, latencyMs: 1);
      expect(s.currentN, 2); // +1 after two correct blocks
      expect(s.maxNReached, 1);
    });
  });

  group('Following directions core', () {
    test('trial instruction, grid and ordered correctness', () {
      final g = FollowingDirectionsGenerator(seed: 0);
      final t = g.next(2);
      expect(t.steps, 2);
      expect(t.grid.length, 6);
      expect(t.instruction.toLowerCase(), contains('tap the'));
      expect(t.isCorrect(t.sequence), isTrue);
      expect(t.isCorrect([t.sequence[1], t.sequence[0]]), isFalse);
    });

    test('level climbs after two correct and drops after a miss', () {
      final s = FollowingDirectionsSession(maxTrials: 10);
      final g = FollowingDirectionsGenerator(seed: 2);
      expect(s.currentLevel, 1);
      var tr = g.next(s.currentLevel);
      s.submit(tr, tr.sequence, latencyMs: 1);
      tr = g.next(s.currentLevel);
      s.submit(tr, tr.sequence, latencyMs: 1);
      expect(s.currentLevel, 2);
      expect(s.maxLevelReached, 2);
      tr = g.next(s.currentLevel);
      s.submit(tr, const <int>[], latencyMs: 1); // wrong
      expect(s.currentLevel, 1);
    });
  });

  group('Gamification core', () {
    test('points formula', () {
      expect(pointsForSession(10, 7), 10 * 10 + 7 * 5 + 20);
      expect(pointsForSession(0, 0), 20);
    });

    test('first session, perfect score and points are awarded', () {
      final o = applySession(GamificationState.initial(),
          trials: 5, correct: 5, testId: 'competing_speakers',
          now: DateTime(2025, 1, 1));
      expect(o.state.points, pointsForSession(5, 5));
      expect(o.state.sessionsCompleted, 1);
      final ids = o.newBadges.map((b) => b.id);
      expect(ids, contains(BadgeIds.firstSession));
      expect(ids, contains(BadgeIds.perfectScore));
    });

    test('streak extends across consecutive days and resets after a gap', () {
      var s = GamificationState.initial();
      SessionOutcome? last;
      for (var i = 0; i < 7; i++) {
        last = applySession(s,
            trials: 3, correct: 2, testId: 'x',
            now: DateTime(2025, 1, 1).add(Duration(days: i)));
        s = last.state;
      }
      expect(s.currentStreak, 7);
      expect(last!.newBadges.map((b) => b.id),
          contains(BadgeIds.sevenDayStreak));

      // A missed day resets the streak to 1.
      final after = applySession(s,
          trials: 1, correct: 1, testId: 'x', now: DateTime(2025, 1, 10));
      expect(after.state.currentStreak, 1);
    });

    test('daily goal counts per day and resets the next day', () {
      var s = GamificationState.initial();
      final d = DateTime(2025, 3, 1, 9);
      s = applySession(s, trials: 1, correct: 1, testId: 'a', now: d).state;
      s = applySession(s,
              trials: 1, correct: 1, testId: 'b',
              now: d.add(const Duration(hours: 1)))
          .state;
      s = applySession(s,
              trials: 1, correct: 1, testId: 'c',
              now: d.add(const Duration(hours: 2)))
          .state;
      expect(s.exercisesToday, 3);
      expect(s.dailyGoalMet, isTrue);
      s = applySession(s,
              trials: 1, correct: 1, testId: 'a', now: DateTime(2025, 3, 2))
          .state;
      expect(s.exercisesToday, 1);
    });

    test('all-tests-tried unlocks after every training id is seen', () {
      var s = GamificationState.initial();
      SessionOutcome? last;
      for (final id in kGamifiedTestIds) {
        last = applySession(s,
            trials: 1, correct: 0, testId: id, now: DateTime(2025, 1, 1));
        s = last.state;
      }
      expect(s.badges, contains(BadgeIds.allTestsTried));
    });

    test('state JSON round-trips', () {
      final o = applySession(GamificationState.initial(),
          trials: 4, correct: 3, testId: 'continuum',
          now: DateTime(2025, 1, 1));
      final restored = GamificationState.decode(o.state.encode());
      expect(restored.points, o.state.points);
      expect(restored.sessionsCompleted, 1);
      expect(restored.badges, o.state.badges);
      expect(restored.testsTried, contains('continuum'));
    });
  });

  group('Gamification store', () {
    test('records a session, persists it and returns new badges', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = GamificationStore(key: 'test.gamification');
      final badges = await store.recordSession(
        trials: 5,
        correct: 5,
        testId: 'phonemic_contrast',
        now: DateTime(2025, 1, 1),
      );
      expect(badges.map((b) => b.id), contains(BadgeIds.firstSession));
      final loaded = await store.load();
      expect(loaded.points, pointsForSession(5, 5));
      expect(loaded.sessionsCompleted, 1);
      expect(loaded.testsTried, contains('phonemic_contrast'));
    });
  });

  // =============================================================== widgets ==
  group('Phase 3 widgets', () {
    testWidgets('competing speakers plays then scores the higher-voice choice',
        (tester) async {
      final port = SilentAudioPort();
      final target = CompetingSpeakersGenerator(seed: 0).next().target;
      await tester.pumpWidget(MaterialApp(
        home: CompetingSpeakersPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 0,
          audioPort: port,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);
      await tester.tap(find.text(target));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('phonemic contrast plays then scores the 2AFC choice',
        (tester) async {
      final port = SilentAudioPort();
      final trial = PhonemicContrastGenerator(seed: 0).next(1);
      await tester.pumpWidget(MaterialApp(
        home: PhonemicContrastPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 0,
          audioPort: port,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);
      await tester.tap(find.text(trial.target));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('auditory closure plays a masked word then scores a choice',
        (tester) async {
      final port = SilentAudioPort();
      final target =
          AuditoryClosureGenerator(pool: kClosureWordPool, seed: 0).next().word;
      await tester.pumpWidget(MaterialApp(
        home: ClosureTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 0,
          audioPort: port,
          assetLoader: (_) async => _demoWav(),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);
      await tester.tap(find.text(target));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('compressed training plays then scores typed text',
        (tester) async {
      final port = SilentAudioPort();
      final target = SpeedTrainingGenerator(seed: 0).next().text;
      await tester.pumpWidget(MaterialApp(
        home: CompressedTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 0,
          audioPort: port,
          assetLoader: (_) async => _demoWav(),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);
      await tester.enterText(find.byType(TextField), target);
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('continuum level 1 plays tones then scores the odd one',
        (tester) async {
      final port = SilentAudioPort();
      final trial = ContinuumSession(seed: 0).nextTrial();
      final correctLabel = trial.choices[trial.targetIndex];
      await tester.pumpWidget(MaterialApp(
        home: ContinuumPage(
          comfortableLevel: 0.4,
          trialsPerLevel: 5,
          seed: 0,
          audioPort: port,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);
      await tester.tap(find.text(correctLabel));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('working memory chooser opens the span runner', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: WorkingMemoryPage(comfortableLevel: 0.4, maxTrials: 3),
      ));
      await tester.pump();
      expect(find.text('Digit span'), findsOneWidget);
      expect(find.text('N-back'), findsOneWidget);
      await tester.tap(find.text('Digit span'));
      await tester.pumpAndSettle();
      expect(find.text('Recall'), findsOneWidget);
    });

    testWidgets('following directions renders an instruction and grid',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FollowingDirectionsPage(comfortableLevel: 0.4, maxTrials: 3),
      ));
      await tester.pump();
      expect(find.textContaining('Tap the'), findsWidgets);
      expect(find.textContaining('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('gamification overlay shows points, streak and daily labels',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GamificationOverlay(store: GamificationStore(key: 'ov.test')),
        ),
      ));
      await tester.pump();
      expect(find.text('points'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.textContaining('today'), findsOneWidget);
    });

    testWidgets('badge celebration shows the badge name', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showBadgeCelebration(ctx, kBadges.first),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Badge unlocked!'), findsOneWidget);
      expect(find.text(kBadges.first.name), findsOneWidget);
    });
  });
}
