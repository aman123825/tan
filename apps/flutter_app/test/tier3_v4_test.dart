import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/settings/app_settings.dart';
import 'package:hearbloom/core/tinnitus/tinnitus_store.dart';
import 'package:hearbloom/data/consent_store.dart';
import 'package:hearbloom/data/usage_stats.dart';
import 'package:hearbloom/features/consent/consent_page.dart';
import 'package:hearbloom/features/questionnaires/tfi_page.dart';
import 'package:hearbloom/features/questionnaires/thi_page.dart';
import 'package:hearbloom/features/settings/data_tools.dart';
import 'package:hearbloom/features/tinnitus/desensitization_page.dart';
import 'package:hearbloom/features/tinnitus/residual_inhibition_page.dart';
import 'package:hearbloom/features/tinnitus/trt_education_page.dart';

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    consentState.value = null;
  });

  group('THI scoring', () {
    test('all-No is 0, all-Yes is 100, grades follow McCombe', () {
      expect(Thi.items.length, 25);
      expect(Thi.total(List<int?>.filled(25, 2)), 0);
      expect(Thi.total(List<int?>.filled(25, 0)), 100);
      expect(Thi.total(List<int?>.filled(25, null)), isNull);
      expect(Thi.grade(10), contains('slight'));
      expect(Thi.grade(30), contains('mild'));
      expect(Thi.grade(50), contains('moderate'));
      expect(Thi.grade(70), contains('severe'));
      expect(Thi.grade(90), contains('catastrophic'));
      // Subscale maxima: 11 functional / 9 emotional / 5 catastrophic items.
      final allYes = List<int?>.filled(25, 0);
      expect(Thi.scaleScore(allYes, ThiScale.functional), 44);
      expect(Thi.scaleScore(allYes, ThiScale.emotional), 36);
      expect(Thi.scaleScore(allYes, ThiScale.catastrophic), 20);
    });
  });

  group('TFI-style scoring', () {
    test('overall is mean×10 and domains cover all eight', () {
      expect(TfiStyle.items.length, 25);
      expect(TfiStyle.overall(List<double?>.filled(25, 5)), closeTo(50, 1e-9));
      expect(TfiStyle.overall(List<double?>.filled(25, null)), isNull);
      for (final d in TfiDomain.values) {
        expect(TfiStyle.items.where((i) => i.domain == d), isNotEmpty);
        expect(TfiStyle.domainScore(List<double?>.filled(25, 8), d),
            closeTo(80, 1e-9));
      }
    });

    testWidgets('page carries the not-the-licensed-TFI banner',
        (tester) async {
      await tester.pumpWidget(_app(const TfiPage()));
      expect(find.textContaining('NOT the licensed'), findsOneWidget);
    });
  });

  group('Consent flow (J8)', () {
    testWidgets('decline blocks persistence; agree re-enables it',
        (tester) async {
      await tester.pumpWidget(_app(const ConsentPage()));
      expect(persistenceAllowed, isTrue); // unasked keeps working
      await tester.scrollUntilVisible(
          find.byKey(const Key('consent-decline')), 400);
      await tester.tap(find.byKey(const Key('consent-decline')));
      await tester.pump();
      expect(consentState.value, isFalse);
      expect(persistenceAllowed, isFalse);
      // Version-pinned persistence round-trip.
      expect(await ConsentStore().load(), isFalse);
      await ConsentStore().record(consented: true);
      expect(persistenceAllowed, isTrue);
    });

    testWidgets('consent screen shows the sound-safety promise',
        (tester) async {
      await tester.pumpWidget(_app(const ConsentPage()));
      await tester.scrollUntilVisible(
          find.textContaining('never changes your device volume'), 400);
      expect(find.textContaining('never changes your device volume'),
          findsOneWidget);
    });
  });

  group('Data tools (J8)', () {
    test('export dumps stored keys and delete wipes them', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'hearbloom.session_history.v1': '[{"ts":"2026-07-27T10:00:00.000",'
            '"mod":"noise","grp":"word","title":"W","acc":0.5,"n":2,'
            '"pt":"Current User","synced":false}]',
        'hearbloom.a11y.v1.high_contrast': true,
      });
      final json = await buildLocalDataExport();
      expect(json, contains('hearbloom.session_history.v1'));
      expect(json, contains('"grp": "word"')); // inlined as structure
      expect(json, contains('research_only'));
      final removed = await deleteAllLocalData();
      expect(removed, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(consentState.value, isNull); // consent screen shows again
    });
  });

  group('Usage stats (J10)', () {
    test('records only after opt-in and clears', () async {
      final stats = UsageStats();
      await stats.record('gap');
      expect(await stats.load(), isEmpty); // off by default
      await stats.setEnabled(true);
      await stats.record('gap');
      await stats.record('gap');
      await stats.record('word');
      expect(await stats.load(), {'gap': 2, 'word': 1});
      await stats.clear();
      expect(await stats.load(), isEmpty);
    });
  });

  group('Residual inhibition page', () {
    testWidgets('asks for MML first when unmeasured', (tester) async {
      await tester.pumpWidget(_app(const ResidualInhibitionPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Measure your masking level first'),
          findsOneWidget);
    });

    testWidgets('full run: masker → report → timing → summary',
        (tester) async {
      await TinnitusStore().saveMml(15);
      await tester.pumpWidget(
          _app(const ResidualInhibitionPage(maskerSeconds: 2)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ri-start')));
      await tester.pump(const Duration(seconds: 3)); // masker countdown
      expect(find.byKey(const Key('ri-depth-partial')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ri-depth-partial')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ri-back')));
      await tester.pump();
      expect(find.textContaining('Residual inhibition observed'),
          findsOneWidget);
    });
  });

  group('Desensitization page', () {
    testWidgets('completes a short session and locks until tomorrow',
        (tester) async {
      await tester
          .pumpWidget(_app(const DesensitizationPage(sessionSeconds: 2)));
      await tester.pumpAndSettle();
      expect(find.textContaining('step 1 of 14'), findsOneWidget);
      await tester.tap(find.byKey(const Key('desens-start')));
      await tester.pump(const Duration(seconds: 3)); // session countdown
      await tester.pump();
      expect(find.textContaining('next step unlocks tomorrow'),
          findsOneWidget);
      // The start button is now disabled for today.
      final button = tester.widget<FilledButton>(
          find.byKey(const Key('desens-start')));
      expect(button.onPressed, isNull);
    });
  });

  group('TRT education', () {
    testWidgets('covers the model and the not-therapy disclaimer',
        (tester) async {
      await tester.pumpWidget(_app(const TrtEducationPage()));
      expect(find.textContaining('What tinnitus is'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.textContaining('reading this is not therapy'), 400);
      expect(find.textContaining('reading this is not therapy'),
          findsOneWidget);
      expect(find.textContaining('Jastreboff'), findsWidgets);
    });
  });

  group('Lite mode (L8)', () {
    test('implies reduced motion', () {
      appSettings.value = const AppSettings(liteMode: true);
      // reduceMotionActive needs a context only for MediaQuery; the settings
      // short-circuit is what lite mode uses.
      expect(appSettings.value.liteMode, isTrue);
      appSettings.value = const AppSettings();
    });

    testWidgets('reduceMotionActive is true under lite mode',
        (tester) async {
      appSettings.value = const AppSettings(liteMode: true);
      late bool reduced;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            reduced = reduceMotionActive(context);
            return const SizedBox.shrink();
          },
        ),
      ));
      expect(reduced, isTrue);
      appSettings.value = const AppSettings();
    });
  });
}
