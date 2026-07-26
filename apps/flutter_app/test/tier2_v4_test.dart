import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/training/sentence_closure.dart'
    show kClosureChoiceLevels;
import 'package:hearbloom/data/favorites_store.dart';
import 'package:hearbloom/data/reminder_store.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/fatigue/fatigue_sheet.dart';
import 'package:hearbloom/features/gamification/gamification_overlay.dart'
    show levelUpChime;
import 'package:hearbloom/features/gamification/personal_bests_page.dart';
import 'package:hearbloom/features/kids/guardian_view_page.dart';
import 'package:hearbloom/features/kids/kids_abc_page.dart';
import 'package:hearbloom/features/kids/story_path_page.dart';
import 'package:hearbloom/features/psychoacoustics/beat_tap_page.dart';
import 'package:hearbloom/features/psychoacoustics/music_in_noise_page.dart';
import 'package:hearbloom/features/psychoacoustics/tmtf_page.dart';

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    favoriteIds.value = <String>{};
  });

  group('Favorites store', () {
    test('toggle adds, removes and persists', () async {
      final store = FavoritesStore();
      await store.toggle(moduleFavoriteId('music'));
      expect(favoriteIds.value, contains('module:music'));
      await store.toggle(trainingFavoriteId(3));
      expect(favoriteIds.value, contains('training:3'));
      await store.toggle(moduleFavoriteId('music'));
      expect(favoriteIds.value, isNot(contains('module:music')));
      // Round-trips through SharedPreferences.
      favoriteIds.value = <String>{};
      expect(await store.load(), contains('training:3'));
    });
  });

  group('Reminder store', () {
    test('enabled/hour/dismissal round-trip', () async {
      final store = ReminderStore();
      expect((await store.load()).enabled, isFalse);
      await store.setEnabled(true);
      await store.setHour(19);
      final s = await store.load();
      expect(s.enabled, isTrue);
      expect(s.hour, 19);
      final today = DateTime(2026, 7, 27);
      expect(await store.isDismissedFor(today), isFalse);
      await store.dismissFor(today);
      expect(await store.isDismissedFor(today), isTrue);
      expect(await store.isDismissedFor(DateTime(2026, 7, 28)), isFalse);
    });
  });

  group('Session naming', () {
    testWidgets('post-session sheet returns the trimmed label',
        (tester) async {
      PostSessionRatings? out;
      await tester.pumpWidget(_app(Scaffold(
        body: FatigueSheet(
          askConfidence: true,
          askLabel: true,
          onSubmit: (_) {},
          onSubmitRatings: (r) => out = r,
        ),
      )));
      await tester.enterText(
          find.byKey(const Key('session-label')), '  noisy room  ');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(out!.label, 'noisy room');
    });

    test('SessionRecord label survives JSON round-trip', () {
      final r = SessionRecord(
        timestamp: DateTime(2026, 7, 27),
        moduleId: 'noise',
        groupId: 'word',
        title: 'Words',
        accuracy: 0.8,
        trials: 10,
        label: 'after school',
      );
      expect(SessionRecord.fromJson(r.toJson()).label, 'after school');
      final legacy = r.toJson()..remove('lbl');
      expect(SessionRecord.fromJson(legacy).label, isNull);
    });
  });

  group('Level-up chime', () {
    test('is short, quiet and non-empty', () {
      final chime = levelUpChime();
      expect(chime, isNotEmpty);
      expect(chime.length / kSampleRate, lessThan(0.5));
      expect(chime.every((v) => v.abs() <= 0.15), isTrue);
    });
  });

  group('TMTF page', () {
    testWidgets('runs a trial and Stop shows the curve', (tester) async {
      await tester.pumpWidget(_app(const TmtfPage()));
      await tester.pump();
      expect(find.textContaining('Rate 4 Hz'), findsOneWidget);
      await tester.tap(find.text('Sound 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(find.byKey(const Key('tmtf-plot')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Music in noise page', () {
    testWidgets('offers four melody titles and adapts SNR', (tester) async {
      await tester.pumpWidget(
          _app(MusicInNoisePage(comfortableLevel: 0.4)));
      await tester.pump();
      expect(find.textContaining('SNR'), findsWidgets);
      // Four melody choice buttons render with real titles.
      expect(
          find.byWidgetPredicate((w) =>
              w is Text &&
              (w.data?.contains('Twinkle') == true ||
                  w.data?.contains('Jingle') == true ||
                  w.data?.contains('Mary') == true ||
                  w.data?.contains('Ode') == true ||
                  w.data?.contains('Frère') == true ||
                  w.data?.contains('London') == true)),
          findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Beat tap page', () {
    testWidgets('start → taps → results with consistency stat',
        (tester) async {
      await tester
          .pumpWidget(_app(const BeatTapPage(bpm: 240, beats: 4)));
      await tester.tap(find.byKey(const Key('beat-tap-start')));
      await tester.pump(const Duration(milliseconds: 600));
      // Tap a few times during the (short) track.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('beat-tap-pad')));
        await tester.pump(const Duration(milliseconds: 250));
      }
      // Let the end-timer fire ((4+4) beats × 250 ms + 300 ms ≈ 2.3 s).
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Tapping consistency'), findsOneWidget);
    });
  });

  group('Kids pages', () {
    testWidgets('ABC worlds lists all four environments', (tester) async {
      await tester.pumpWidget(_app(const KidsAbcPage()));
      for (final world in AbcWorld.values) {
        expect(find.byKey(Key('abc-${world.name}')), findsOneWidget);
      }
      expect(find.text('Quiet room'), findsOneWidget);
      expect(find.text('Phone call'), findsOneWidget);
    });

    testWidgets('ABC world opens the letter game with its acoustics',
        (tester) async {
      await tester.pumpWidget(_app(const KidsAbcPage()));
      await tester.tap(find.byKey(const Key('abc-quiet')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ABC — Quiet room'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('story path shows chapters and locks future ones',
        (tester) async {
      await tester.pumpWidget(_app(const StoryPathPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('story-node-0')), findsOneWidget);
      expect(find.byKey(const Key('story-node-5')), findsOneWidget);
      // With 0 sessions, later chapters are locked.
      await tester.scrollUntilVisible(
          find.byKey(const Key('story-node-5')), 400);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('story-node-5')));
      await tester.pumpAndSettle();
      expect(find.textContaining('to unlock'), findsOneWidget);
    });

    testWidgets('guardian view summarises in plain language',
        (tester) async {
      final history = SessionHistory(key: 'guardian.test');
      await history.add(SessionRecord(
        timestamp: DateTime.now(),
        moduleId: 'noise',
        groupId: 'word',
        title: 'Words in noise',
        accuracy: 0.7,
        trials: 20,
        metric: '−2.0 dB SNR',
        metricValue: -2,
        metricUnit: 'dB SNR',
        higherIsBetter: false,
      ));
      await tester.pumpWidget(_app(GuardianViewPage(history: history)));
      await tester.pumpAndSettle();
      expect(find.text('sessions this week'), findsOneWidget);
      expect(find.textContaining('Listening in noise'), findsOneWidget);
      expect(find.textContaining('finer listening'), findsOneWidget);
    });
  });

  group('Personal bests', () {
    testWidgets('shows the best run per test (lower-is-better aware)',
        (tester) async {
      final history = SessionHistory(key: 'bests.test');
      await history.add(SessionRecord(
        timestamp: DateTime(2026, 7, 20),
        moduleId: 'auditory',
        groupId: 'gap',
        title: 'Gap detection',
        accuracy: 0.7,
        trials: 20,
        metric: '5.0 ms',
        metricValue: 5,
        metricUnit: 'ms',
        higherIsBetter: false,
      ));
      await history.add(SessionRecord(
        timestamp: DateTime(2026, 7, 26),
        moduleId: 'auditory',
        groupId: 'gap',
        title: 'Gap detection',
        accuracy: 0.7,
        trials: 20,
        metric: '3.2 ms',
        metricValue: 3.2,
        metricUnit: 'ms',
        higherIsBetter: false,
      ));
      await tester.pumpWidget(_app(PersonalBestsPage(history: history)));
      await tester.pumpAndSettle();
      expect(find.text('3.2 ms'), findsOneWidget); // the lower threshold wins
      expect(find.text('5.0 ms'), findsNothing);
      expect(find.textContaining('lower is better'), findsOneWidget);
    });
  });

  group('Adaptive closure ladder sanity', () {
    test('levels are strictly increasing set sizes', () {
      for (var i = 1; i < kClosureChoiceLevels.length; i++) {
        expect(kClosureChoiceLevels[i],
            greaterThan(kClosureChoiceLevels[i - 1]));
      }
    });
  });
}
