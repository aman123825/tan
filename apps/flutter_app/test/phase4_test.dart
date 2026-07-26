import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/i18n/language_config.dart';
import 'package:hearbloom/core/settings/app_settings.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/dashboard/clinician_dashboard_page.dart';
import 'package:hearbloom/features/remote/remote_sync_page.dart';
import 'package:hearbloom/features/report/enhanced_report_page.dart';
import 'package:hearbloom/features/settings/language_selector.dart';
import 'package:hearbloom/features/settings/settings_page.dart';
import 'package:hearbloom/features/trends/trend_page.dart';
import 'package:hearbloom/features/validation/validation_protocol_page.dart';

void main() {
  // ============================================================ i18n / lang ==
  group('Language config', () {
    test('five languages are supported, English first and default', () {
      expect(kSupportedLanguages.length, 5);
      expect(kSupportedLanguages.first.code, 'en-IN');
      expect(kDefaultLanguageCode, 'en-IN');
      expect(
        kSupportedLanguages.map((l) => l.code).toSet(),
        {'en-IN', 'hi-IN', 'ta-IN', 'te-IN', 'kn-IN'},
      );
    });

    test('every language has a 10-word pool with native + roman + english', () {
      for (final lang in kSupportedLanguages) {
        expect(lang.wordPool.length, 10, reason: '${lang.code} pool size');
        for (final w in lang.wordPool) {
          expect(w.native.isNotEmpty, isTrue);
          expect(w.roman.isNotEmpty, isTrue);
          expect(w.english.isNotEmpty, isTrue);
        }
      }
    });

    test('Hindi pool uses Devanagari script (non-ASCII natives)', () {
      final ascii = RegExp(r'^[ -~]+$');
      // Every Hindi native form should contain non-ASCII (Devanagari) glyphs.
      for (final w in kHindi.wordPool) {
        expect(ascii.hasMatch(w.native), isFalse,
            reason: '${w.native} should be Devanagari');
      }
    });

    test('only English ships bundled speech; others await generation', () {
      expect(kEnglishIndia.hasBundledSpeech, isTrue);
      expect(kHindi.hasBundledSpeech, isFalse);
      expect(kTamil.hasBundledSpeech, isFalse);
      expect(kTelugu.hasBundledSpeech, isFalse);
      expect(kKannada.hasBundledSpeech, isFalse);
    });

    test('languageByCode falls back to English for unknown codes', () {
      expect(languageByCode('hi-IN').code, 'hi-IN');
      expect(languageByCode('zz-ZZ').code, 'en-IN');
      expect(languageByCode(null).code, 'en-IN');
    });

    test('LanguageStore round-trips a saved code and coerces invalid ones',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LanguageStore();
      expect(await store.loadCode(), 'en-IN'); // default
      await store.save('ta-IN');
      expect(await store.loadCode(), 'ta-IN');
      await store.save('bogus');
      expect(await store.loadCode(), 'en-IN'); // coerced
    });
  });

  // ======================================================= accessibility ====
  group('App settings (accessibility)', () {
    test('text-size scale factors are ordered small < medium < large', () {
      expect(TextSizePreference.small.scale, lessThan(1.0));
      expect(TextSizePreference.medium.scale, 1.0);
      expect(TextSizePreference.large.scale, greaterThan(1.0));
    });

    test('AppSettingsStore persists high-contrast and text size', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      appSettings.value = const AppSettings();
      final store = AppSettingsStore();

      var loaded = await store.load();
      expect(loaded.highContrast, isFalse);
      expect(loaded.textSize, TextSizePreference.medium);

      await store.setHighContrast(true);
      await store.setTextSize(TextSizePreference.large);

      loaded = await store.load();
      expect(loaded.highContrast, isTrue);
      expect(loaded.textSize, TextSizePreference.large);
      // The global notifier is kept in sync.
      expect(appSettings.value.highContrast, isTrue);
      expect(appSettings.value.textSize, TextSizePreference.large);
    });

    test('loadAppSettings populates the notifier from storage', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'hearbloom.a11y.v1.high_contrast': true,
        'hearbloom.a11y.v1.text_size': 'small',
      });
      appSettings.value = const AppSettings();
      await loadAppSettings();
      expect(appSettings.value.highContrast, isTrue);
      expect(appSettings.value.textSize, TextSizePreference.small);
    });
  });

  // ================================================ session record patient ==
  group('SessionRecord patient field', () {
    test('defaults to Current User and round-trips through JSON', () {
      final r = SessionRecord(
        timestamp: DateTime(2026, 1, 2, 3, 4),
        moduleId: 'auditory',
        groupId: 'gap',
        title: 'Gap detection',
        accuracy: 0.8,
        trials: 10,
      );
      expect(r.patient, kDefaultPatient);
      final back = SessionRecord.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.patient, kDefaultPatient);

      final custom = SessionRecord(
        timestamp: DateTime(2026, 1, 2),
        moduleId: 'm',
        groupId: 'g',
        title: 't',
        accuracy: 0.5,
        trials: 4,
        patient: 'Patient A',
      );
      final back2 =
          SessionRecord.fromJson(jsonDecode(jsonEncode(custom.toJson())));
      expect(back2.patient, 'Patient A');
    });

    test('legacy JSON without a patient key still loads', () {
      final legacy = <String, dynamic>{
        'ts': DateTime(2026, 1, 1).toIso8601String(),
        'mod': 'm',
        'grp': 'g',
        'title': 't',
        'acc': 0.6,
        'n': 5,
      };
      expect(SessionRecord.fromJson(legacy).patient, kDefaultPatient);
    });
  });

  // ================================================ report classification ===
  group('Enhanced report — Buffalo classification', () {
    test('affectedProfiles collects categories with non-normal results', () {
      final affected = affectedProfiles(kSampleReportTests);
      expect(affected.contains(BuffaloProfile.integration), isTrue);
      expect(affected.contains(BuffaloProfile.auditoryDecoding), isTrue);
      expect(affected.contains(BuffaloProfile.toleranceFadingMemory), isTrue);
      expect(affected.contains(BuffaloProfile.prosodic), isTrue);
    });

    test('all-normal results classify as no weakness with no deficit recs', () {
      const normal = <ReportTest>[
        ReportTest(
          name: 'Test A',
          score: '95%',
          norm: '≥ 90%',
          status: ReportStatus.normal,
          profile: BuffaloProfile.integration,
        ),
      ];
      expect(affectedProfiles(normal), isEmpty);
      expect(classifyBuffaloProfile(normal), contains('within their'));
      final recs = reportRecommendations(normal);
      // Only the closing referral recommendation remains.
      expect(recs.length, 1);
      expect(recs.single, contains('audiologist'));
    });

    test('auditory-decoding deficit yields a phonemic-training recommendation',
        () {
      const tests = <ReportTest>[
        ReportTest(
          name: 'Phoneme discrimination',
          score: '60%',
          norm: '≥ 80%',
          status: ReportStatus.below,
          profile: BuffaloProfile.auditoryDecoding,
        ),
      ];
      final recs = reportRecommendations(tests);
      expect(recs.any((r) => r.toLowerCase().contains('phonemic training')),
          isTrue);
      expect(recs.any((r) => r.contains('FM system')), isTrue);
    });
  });

  // ================================================ patient summarisation ===
  group('Clinician dashboard — summarisePatients', () {
    List<SessionRecord> mk(String patient, List<double> accs, DateTime start) {
      return [
        for (var i = 0; i < accs.length; i++)
          SessionRecord(
            timestamp: start.add(Duration(days: i)),
            moduleId: 'm',
            groupId: 'g',
            title: 'Gap detection',
            accuracy: accs[i],
            trials: 10,
            patient: patient,
          ),
      ];
    }

    test('groups by patient, orders by most-recent, computes trend', () {
      final records = <SessionRecord>[
        ...mk('Alice', [0.4, 0.6, 0.8], DateTime(2026, 1, 1)),
        ...mk('Bob', [0.9], DateTime(2026, 2, 1)),
      ];
      final summaries = summarisePatients(records);
      expect(summaries.length, 2);
      // Bob's session is later → sorted first.
      expect(summaries.first.patient, 'Bob');
      final alice = summaries.firstWhere((s) => s.patient == 'Alice');
      expect(alice.sessionCount, 3);
      expect(alice.trend, TrendDirection.improving);
      // Single-session patient is reported as stable.
      final bob = summaries.firstWhere((s) => s.patient == 'Bob');
      expect(bob.trend, TrendDirection.stable);
    });
  });

  // ============================================================ widgets =====
  group('Phase 4 widgets', () {
    testWidgets('EnhancedReportPage shows the table, profile and actions',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EnhancedReportPage()));
      await tester.pumpAndSettle();

      expect(find.text('Test Results'), findsOneWidget);
      expect(find.text('CAPD Profile — Buffalo Model'), findsOneWidget);
      expect(find.text('Recommendations'), findsOneWidget);
      expect(find.text('Print Report'), findsOneWidget);
      expect(find.text('Copy Text'), findsOneWidget);
      // Table headers.
      expect(find.text('Ear'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.byKey(const Key('report-paper')), findsOneWidget);
    });

    testWidgets('Report print button shows browser instructions on the VM',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EnhancedReportPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-print')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('browser'), findsOneWidget);
    });

    testWidgets('Report copy button copies text and confirms', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EnhancedReportPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Report text copied to clipboard'), findsOneWidget);
    });

    testWidgets('ClinicianDashboardPage lists a patient and exports JSON',
        (tester) async {
      final records = [
        for (var i = 0; i < 3; i++)
          SessionRecord(
            timestamp: DateTime(2026, 1, 1).add(Duration(days: i)),
            moduleId: 'm',
            groupId: 'g',
            title: 'Gap detection',
            accuracy: 0.5 + i * 0.2,
            trials: 10,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(home: ClinicianDashboardPage(records: records)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient-Current User')), findsOneWidget);
      expect(find.text('Improving'), findsWidgets);

      await tester.tap(find.byKey(const Key('dashboard-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('session record'), findsOneWidget);
    });

    testWidgets('ClinicianDashboardPage detail opens on tap', (tester) async {
      final records = [
        for (var i = 0; i < 3; i++)
          SessionRecord(
            timestamp: DateTime(2026, 1, 1).add(Duration(days: i)),
            moduleId: 'm',
            groupId: 'g',
            title: 'Gap detection',
            accuracy: 0.5 + i * 0.15,
            trials: 10,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(home: ClinicianDashboardPage(records: records)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient-Current User')));
      await tester.pumpAndSettle();
      expect(find.text('Session history'), findsOneWidget);
    });

    testWidgets('RemoteSyncPage shows sync status and Sync-Now snackbar',
        (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RemoteSyncPage()));
      await tester.pumpAndSettle();

      expect(find.text('Not yet synced — data stored locally'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      expect(find.byKey(const Key('pending-sessions-value')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sync-now-button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // With no clinician code linked, sync prompts the user to enter one.
      expect(
        find.text('Enter a clinician code to enable sync.'),
        findsWidgets,
      );
    });

    testWidgets('RemoteSyncPage saves the clinician code', (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final linkStore = ClinicianLinkStore();
      await tester.pumpWidget(
        MaterialApp(home: RemoteSyncPage(linkStore: linkStore)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('clinician-code-field')), 'CLIN-1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(await linkStore.load(), 'CLIN-1234');
    });

    testWidgets('ValidationProtocolPage renders the study sections',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: ValidationProtocolPage()));
      await tester.pumpAndSettle();
      expect(find.text('Study design'), findsOneWidget);
      expect(find.text('Participants'), findsOneWidget);
      expect(find.textContaining('SCAN-3'), findsWidgets);
      // Later sections are below the fold in the test viewport — scroll to one.
      await tester.scrollUntilVisible(
        find.text('Statistical plan'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Statistical plan'), findsOneWidget);
    });

    testWidgets('LanguageSelectorPage lists languages and saves a choice',
        (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LanguageStore();
      LanguageConfig? changed;
      await tester.pumpWidget(MaterialApp(
        home: LanguageSelectorPage(store: store, onChanged: (l) => changed = l),
      ));
      await tester.pumpAndSettle();

      expect(find.text('English (India)'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);

      await tester.tap(find.byKey(const Key('language-hi-IN')));
      await tester.pumpAndSettle();

      expect(changed?.code, 'hi-IN');
      expect(await store.loadCode(), 'hi-IN');
    });

    testWidgets('SettingsPage toggles high-contrast and text size',
        (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      appSettings.value = const AppSettings();
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('High-contrast mode'), findsOneWidget);
      expect(find.text('Text size'), findsOneWidget);

      await tester.tap(find.byKey(const Key('high-contrast-switch')));
      await tester.pumpAndSettle();
      expect(appSettings.value.highContrast, isTrue);

      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      expect(appSettings.value.textSize, TextSizePreference.large);
    });
  });
}
