import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/session_planner.dart';
import 'package:hearbloom/core/speech_in_noise.dart'
    show FourAfcGenerator, FourAlternativeTrial;
import 'package:hearbloom/core/training/spatial.dart';
import 'package:hearbloom/core/training/vocoder.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/onboarding/onboarding_page.dart';
import 'package:hearbloom/features/open_set/open_set_page.dart'
    show kOpenWordPool;
import 'package:hearbloom/features/planner/planner_page.dart';
import 'package:hearbloom/features/training/spatial_page.dart';
import 'package:hearbloom/features/training/vocoder_page.dart';

void main() {
  // ======================================================= 1. Vocoder ========
  group('Vocoder DSP', () {
    test('preserves buffer length and is deterministic', () {
      final input = tone(seconds: 0.3, freqHz: 440, amp: 0.2);
      final a = vocode(input, 8);
      final b = vocode(input, 8);
      expect(a.length, input.length);
      expect(a, equals(b)); // deterministic for a fixed seed
    });

    test('band edges are log-spaced, ascending and N+1 in count', () {
      final edges = vocoderBandEdges(8, lowHz: 150, highHz: 7000);
      expect(edges.length, 9);
      for (var i = 1; i < edges.length; i++) {
        expect(edges[i], greaterThan(edges[i - 1]));
      }
      expect(edges.first, closeTo(150, 0.001));
      expect(edges.last, closeTo(7000, 0.001));
    });

    test('output is finite and RMS-matched (never louder than input)', () {
      final input = tone(seconds: 0.25, freqHz: 500, amp: 0.25);
      for (final ch in kVocoderChannelLadder) {
        final out = vocode(input, ch);
        expect(out.every((x) => x.isFinite), isTrue);
        expect(rms(out), greaterThan(0));
        // Matched then peak-limited → never exceeds the input RMS (+epsilon).
        expect(rms(out), lessThanOrEqualTo(rms(input) + 1e-6));
        expect(out.every((x) => x.abs() <= 0.981), isTrue);
      }
    });

    test('empty input and silence are handled gracefully', () {
      expect(vocode(<double>[], 8), isEmpty);
      final sil = silence(0.1);
      final out = vocode(sil, 8);
      expect(out.length, sil.length);
      expect(rms(out), 0);
    });

    test('bandPassBiquad rejects invalid centres', () {
      final x = tone(seconds: 0.05, freqHz: 300, amp: 0.2);
      expect(bandPassBiquad(x, 0, 1).length, x.length); // returns copy
      expect(bandPassBiquad(x, 40000, 1), equals(x)); // >= Nyquist → unchanged
    });
  });

  group('VocoderSession adaptation', () {
    FourAlternativeTrial trial() =>
        FourAlternativeTrial(choices: const ['a', 'b', 'c', 'd'], targetIndex: 0);

    test('starts at 16 channels', () {
      expect(VocoderSession().currentChannels, kVocoderStartChannels);
      expect(VocoderSession().currentChannels, 16);
    });

    test('two correct → fewer channels; one wrong → more channels', () {
      final s = VocoderSession();
      s.submit(trial(), 0, latencyMs: 0); // correct @16 (streak 1)
      expect(s.currentChannels, 16);
      s.submit(trial(), 0, latencyMs: 0); // correct @16 (streak 2) → 8
      expect(s.currentChannels, 8);
      // Mastery is measured at the presentation channel count (16 so far).
      expect(s.fewestChannelsMastered, 16);
      s.submit(trial(), 1, latencyMs: 0); // wrong @8 → 16
      expect(s.currentChannels, 16);
    });

    test('tracks the fewest channels correctly identified', () {
      final s = VocoderSession();
      s.submit(trial(), 0, latencyMs: 0); // @16 correct
      s.submit(trial(), 0, latencyMs: 0); // @16 correct → 8
      s.submit(trial(), 0, latencyMs: 0); // @8 correct
      expect(s.fewestChannelsMastered, 8);
      s.submit(trial(), 0, latencyMs: 0); // @8 correct → 4
      expect(s.currentChannels, 4);
      expect(s.fewestChannelsMastered, 8); // presented at 8, not yet 4
    });

    test('never drops below 4 or rises above 32', () {
      final down = VocoderSession(startChannels: 4);
      for (var i = 0; i < 6; i++) {
        down.submit(trial(), 0, latencyMs: 0);
      }
      expect(down.currentChannels, 4);

      final up = VocoderSession(startChannels: 32);
      for (var i = 0; i < 6; i++) {
        up.submit(trial(), 1, latencyMs: 0); // always wrong
      }
      expect(up.currentChannels, 32);
    });
  });

  // ======================================================= 2. Spatial ========
  group('Spatial ITD/ILD DSP', () {
    test('ITD uses (d/c)·sin(θ) geometry', () {
      expect(itdSeconds(0), 0);
      expect(itdSeconds(90), closeTo(kHeadWidthM / kSpeedOfSoundMps, 1e-9));
      expect(itdSeconds(-90), closeTo(-kHeadWidthM / kSpeedOfSoundMps, 1e-9));
    });

    test('ILD is 10·|sin θ| dB (≈10 dB at ±90°, 0 at centre)', () {
      expect(ildDb(0), 0);
      expect(ildDb(90), closeTo(10, 1e-9));
      expect(ildDb(-90), closeTo(10, 1e-9));
    });

    test('centre (0°) is diotic: both channels equal the input', () {
      final mono = tone(seconds: 0.05, freqHz: 400, amp: 0.2);
      final s = spatialize(mono, 0);
      expect(s.left, equals(mono));
      expect(s.right, equals(mono));
    });

    test('right source: right ear leads/full, left ear delayed+attenuated', () {
      final mono = tone(seconds: 0.1, freqHz: 400, amp: 0.3);
      final s = spatialize(mono, 90);
      expect(s.right, equals(mono)); // near ear unchanged
      expect(rms(s.left), lessThan(rms(s.right))); // far ear attenuated
    });
  });

  group('SpatialSession adaptation', () {
    test('starts easy (±90°, 2 positions) and widens on success', () {
      final s = SpatialSession();
      expect(s.currentLevel, 0);
      expect(s.activePositions, 2);
      final t = const SpatialTrial(angleDeg: 90, choices: kSpatialAngles);
      s.submit(t, 90, latencyMs: 0); // correct
      s.submit(t, 90, latencyMs: 0); // correct → level up
      expect(s.currentLevel, 1);
      expect(s.maxLevelReached, 1);
      expect(s.meanAngularError, 0);
    });

    test('wrong answer drops a level and records angular error', () {
      final s = SpatialSession();
      const t = SpatialTrial(angleDeg: 90, choices: kSpatialAngles);
      s.submit(t, 90, latencyMs: 0);
      s.submit(t, 90, latencyMs: 0); // → level 1
      s.submit(t, -90, latencyMs: 0); // wrong, error 180 → level 0
      expect(s.currentLevel, 0);
      // errors: 0, 0, 180 → mean 60
      expect(s.meanAngularError, closeTo(60, 1e-9));
      expect(s.percent, closeTo(67, 1)); // 2/3 correct
    });

    test('generator only presents angles from the active level set', () {
      final g = SpatialGenerator(seed: 3);
      for (var i = 0; i < 20; i++) {
        final t = g.next(0);
        expect(kSpatialLevels[0].contains(t.angleDeg), isTrue);
      }
    });
  });

  // ======================================================= 3. Planner ========
  group('SessionPlanner', () {
    SessionRecord rec(String grp, String title, double acc, DateTime ts,
            {String mod = 'auditory'}) =>
        SessionRecord(
          timestamp: ts,
          moduleId: mod,
          groupId: grp,
          title: title,
          accuracy: acc,
          trials: 10,
        );

    test('ranks a low/declining exercise above a mastered one', () {
      final now = DateTime(2026, 1, 10);
      final records = <SessionRecord>[
        rec('gap', 'Gap detection', 0.9, now.subtract(const Duration(days: 8))),
        rec('gap', 'Gap detection', 0.4, now.subtract(const Duration(days: 2))),
        rec('mci', 'Melodic contour', 0.95,
            now.subtract(const Duration(days: 1)),
            mod: 'music'),
      ];
      final ranked = SessionPlanner.analyze(records, now: now);
      expect(ranked.length, 2);

      final gap = ranked.first;
      expect(gap.groupId, 'gap');
      expect(gap.trend, ExerciseTrend.declining);
      expect(gap.status, ExerciseStatus.needsWork);
      // (1-0.4)*2 + 2*0.1 + 1 = 2.4
      expect(gap.priority, closeTo(2.4, 1e-9));

      final mci = ranked.last;
      expect(mci.groupId, 'mci');
      expect(mci.status, ExerciseStatus.mastered);
      // (1-0.95)*2 + 1*0.1 + 0 = 0.2
      expect(mci.priority, closeTo(0.2, 1e-9));
    });

    test('improving trend is detected and status is improving', () {
      final now = DateTime(2026, 1, 10);
      final records = <SessionRecord>[
        rec('word', 'Word', 0.5, now.subtract(const Duration(days: 3))),
        rec('word', 'Word', 0.7, now.subtract(const Duration(days: 1))),
      ];
      final r = SessionPlanner.analyze(records, now: now).single;
      expect(r.trend, ExerciseTrend.improving);
      expect(r.status, ExerciseStatus.improving);
    });

    test('recommend returns the top N by priority', () {
      final now = DateTime(2026, 1, 10);
      final records = <SessionRecord>[
        rec('a', 'A', 0.2, now.subtract(const Duration(days: 5))),
        rec('b', 'B', 0.6, now.subtract(const Duration(days: 1))),
        rec('c', 'C', 0.95, now),
      ];
      final top = SessionPlanner.recommend(records, n: 2, now: now);
      expect(top.length, 2);
      expect(top.first.groupId, 'a'); // lowest score, oldest → highest priority
    });

    test('empty history yields no recommendations', () {
      expect(SessionPlanner.analyze(const []), isEmpty);
      expect(SessionPlanner.recommend(const []), isEmpty);
    });
  });

  // ===================================================== 4. Onboarding =======
  group('OnboardingStore', () {
    test('round-trips the onboarding_complete flag', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = OnboardingStore();
      expect(await store.isComplete(), isFalse);
      await store.setComplete();
      expect(await store.isComplete(), isTrue);
      await store.reset();
      expect(await store.isComplete(), isFalse);
    });

    test('the tour has five steps', () {
      expect(kOnboardingSteps.length, 5);
      expect(kOnboardingSteps.first.headline, 'Welcome to HearBloom');
    });
  });

  // =========================================================== widgets =======
  group('Feature widgets', () {
    testWidgets('VocoderPage plays a vocoded word and scores a 4AFC choice',
        (tester) async {
      final wav = encodeWav16(
        tone(seconds: 0.2, freqHz: 300, amp: 0.3),
        sampleRate: 22050,
      );
      final port = SilentAudioPort();
      final target = FourAfcGenerator(kOpenWordPool, seed: 3, choices: 4).next();

      await tester.pumpWidget(
        MaterialApp(
          home: VocoderPage(
            comfortableLevel: 0.4,
            maxTrials: 3,
            seed: 3,
            audioPort: port,
            assetLoader: (path) async => wav,
          ),
        ),
      );
      await tester.pump();

      // Channel pill shows the starting resolution.
      expect(find.text('16 channels'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);

      await tester.tap(find.text(target.target));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('SpatialPage plays a placed sound and scores a position tap',
        (tester) async {
      final port = SilentAudioPort();
      final target = SpatialGenerator(seed: 1).next(0); // level 0 → ±90°

      await tester.pumpWidget(
        MaterialApp(
          home: SpatialPage(
            comfortableLevel: 0.4,
            maxTrials: 3,
            seed: 1,
            audioPort: port,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2 positions'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);

      final label = target.angleDeg == 0
          ? '0°'
          : '${target.angleDeg > 0 ? '+' : ''}${target.angleDeg}';
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('PlannerPage lists recommendations and starts the top pick',
        (tester) async {
      final now = DateTime(2026, 1, 10);
      final records = <SessionRecord>[
        SessionRecord(
          timestamp: now.subtract(const Duration(days: 2)),
          moduleId: 'auditory',
          groupId: 'gap',
          title: 'Gap detection',
          accuracy: 0.4,
          trials: 10,
        ),
        SessionRecord(
          timestamp: now.subtract(const Duration(days: 1)),
          moduleId: 'music',
          groupId: 'mci',
          title: 'Melodic contour',
          accuracy: 0.95,
          trials: 10,
        ),
      ];
      ExercisePriority? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: PlannerPage(
            records: records,
            now: now,
            onStartExercise: (p) => picked = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gap detection'), findsWidgets);
      expect(find.text('Melodic contour'), findsOneWidget);

      await tester.tap(find.byKey(const Key('planner-start-recommended')));
      await tester.pump();
      expect(picked, isNotNull);
      expect(picked!.groupId, 'gap');
    });

    testWidgets('PlannerPage shows an empty state with no history',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PlannerPage(records: <SessionRecord>[])),
      );
      await tester.pumpAndSettle();
      expect(find.text('No recommendations yet'), findsOneWidget);
    });

    testWidgets('OnboardingPage carousel advances and completes',
        (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = OnboardingStore();
      var finished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPage(store: store, onFinished: () => finished = true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to HearBloom'), findsOneWidget);

      // Advance through steps 2–5.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('begin'), findsWidgets); // final step CTA

      // The final "Let's begin" completes the tour.
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(await store.isComplete(), isTrue);
    });

    testWidgets('OnboardingPage Skip completes immediately', (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = OnboardingStore();
      var finished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPage(store: store, onFinished: () => finished = true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(await store.isComplete(), isTrue);
    });
  });
}
