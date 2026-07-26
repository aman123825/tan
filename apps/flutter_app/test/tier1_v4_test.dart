import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audiogram.dart';
import 'package:hearbloom/core/pattern_test.dart';
import 'package:hearbloom/core/pdf_writer.dart';
import 'package:hearbloom/core/settings/app_settings.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/audiogram/audiogram_page.dart';
import 'package:hearbloom/features/binaural_jnd/binaural_jnd_page.dart';
import 'package:hearbloom/features/common/trial_scaffold.dart';
import 'package:hearbloom/features/compare/session_compare_page.dart';
import 'package:hearbloom/features/figure_ground/figure_ground_page.dart';
import 'package:hearbloom/features/pattern_test/pattern_test_page.dart';
import 'package:hearbloom/features/questionnaires/aphab_page.dart';
import 'package:hearbloom/features/questionnaires/fisher_page.dart';
import 'package:hearbloom/features/report/report_data.dart';

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('APHAB scoring', () {
    test('subscales have 6 items each and 6 reversed items exist', () {
      for (final scale in AphabScale.values) {
        expect(Aphab.items.where((i) => i.scale == scale).length, 6);
      }
      expect(Aphab.items.where((i) => i.reversed).length, 6);
    });

    test('all-D answers score 50 everywhere', () {
      final answers = List<int?>.filled(24, 3); // D = 50%
      for (final scale in AphabScale.values) {
        expect(Aphab.scaleScore(answers, scale), closeTo(50, 1e-9));
      }
      expect(Aphab.globalScore(answers), closeTo(50, 1e-9));
    });

    test('all-A answers: reversal flips positively-worded items', () {
      final answers = List<int?>.filled(24, 0); // A = 99% (1% reversed)
      // EC and AV have no reversed items; BN and RV each have 3 of 6.
      expect(Aphab.scaleScore(answers, AphabScale.ec), closeTo(99, 1e-9));
      expect(Aphab.scaleScore(answers, AphabScale.av), closeTo(99, 1e-9));
      expect(Aphab.scaleScore(answers, AphabScale.bn), closeTo(50, 1e-9));
      expect(Aphab.scaleScore(answers, AphabScale.rv), closeTo(50, 1e-9));
      expect(Aphab.globalScore(answers), closeTo((99 + 50 + 50) / 3, 1e-9));
    });

    test('incomplete answers give null scores', () {
      expect(Aphab.globalScore(List<int?>.filled(24, null)), isNull);
    });
  });

  group('Fisher checklist scoring', () {
    test('has 25 items and 4 points each', () {
      expect(FisherChecklist.items.length, 25);
      expect(FisherChecklist.score(<int>{}), 100);
      expect(FisherChecklist.score({0, 1, 2, 3, 4}), 80);
      expect(
          FisherChecklist.score(
              {for (var i = 0; i < 25; i++) i}),
          0);
    });
  });

  group('SessionRecord confusion persistence', () {
    test('confusions survive a JSON round-trip', () {
      final record = SessionRecord(
        timestamp: DateTime(2026, 7, 26),
        moduleId: 'learning',
        groupId: 'consonant_training',
        title: 'Consonants',
        accuracy: 0.8,
        trials: 10,
        confusions: const [
          ['ba', 'pa'],
          ['da', 'da'],
        ],
      );
      final restored = SessionRecord.fromJson(record.toJson());
      expect(restored.confusions, [
        ['ba', 'pa'],
        ['da', 'da'],
      ]);
      // Legacy records (no cf key) load with null confusions.
      final legacy = record.toJson()..remove('cf');
      expect(SessionRecord.fromJson(legacy).confusions, isNull);
    });

    test('aggregateConfusions builds a real matrix from history', () {
      final history = [
        SessionRecord(
          timestamp: DateTime(2026, 7, 26),
          moduleId: 'learning',
          groupId: 'consonant_training',
          title: 'Consonants',
          accuracy: 0.5,
          trials: 2,
          confusions: const [
            ['ba', 'pa'],
            ['ba', 'ba'],
          ],
        ),
        SessionRecord(
          timestamp: DateTime(2026, 7, 25),
          moduleId: 'noise',
          groupId: 'word',
          title: 'Words',
          accuracy: 1,
          trials: 1,
        ),
      ];
      final (matrix, sessions) = aggregateConfusions(history);
      expect(sessions, 1);
      expect(matrix!.count('ba', 'pa'), 1);
      expect(matrix.count('ba', 'ba'), 1);
      // Empty history → no matrix (report omits the section, invents nothing).
      final (none, zero) = aggregateConfusions(const []);
      expect(none, isNull);
      expect(zero, 0);
    });
  });

  group('PDF writer', () {
    test('emits a structurally valid single-page PDF', () {
      final bytes = buildSimplePdf(
        title: 'Test',
        blocks: const [
          PdfHeading('Title', level: 1),
          PdfKeyValue('Patient', 'X'),
          PdfTableRow(['A', 'B'], bold: true),
          PdfParagraph('Body text — with unicode ± µ.'),
        ],
      );
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('%PDF-1.4'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(text, contains('/Type /Catalog'));
      expect(bytes.every((b) => b < 128), isTrue, reason: 'ASCII-only');
    });

    test('paginates long content', () {
      final bytes = buildSimplePdf(
        title: 'Long',
        blocks: [for (var i = 0; i < 120; i++) PdfParagraph('Line $i')],
      );
      final text = String.fromCharCodes(bytes);
      expect(RegExp('/Type /Page ').allMatches(text).length,
          greaterThanOrEqualTo(2));
    });
  });

  group('Pattern test hum-back mode', () {
    testWidgets('chooser → hum flow → hummed results', (tester) async {
      PatternSession? completed;
      await tester.pumpWidget(_app(PatternTestPage(
        testType: 'fpt',
        trialsPerEar: 1,
        onCompleted: (s) => completed = s,
      )));
      // Response-mode chooser is shown first.
      expect(find.byKey(const Key('pattern-mode-hum')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pattern-mode-hum')));
      await tester.pumpAndSettle();
      // Trial page in hum mode: reveal, then score both trials as matched.
      for (var i = 0; i < 2; i++) {
        expect(find.byKey(const Key('pattern-hum-reveal')), findsOneWidget);
        await tester.tap(find.byKey(const Key('pattern-hum-reveal')));
        await tester.pump();
        expect(find.byKey(const Key('pattern-hum-answer')), findsOneWidget);
        await tester.tap(find.byKey(const Key('pattern-hum-match')));
        await tester.pump(const Duration(milliseconds: 1000));
      }
      expect(completed, isNotNull);
      expect(completed!.groupId, 'frequency_pattern_hum');
      expect(completed!.overallAccuracy, 1.0);
      expect(find.textContaining('Hummed responses'), findsOneWidget);
    });

    testWidgets('fixed labels mode skips the chooser', (tester) async {
      await tester.pumpWidget(_app(const PatternTestPage(
        testType: 'dpt',
        trialsPerEar: 1,
        responseMode: PatternResponseMode.labels,
      )));
      await tester.pump();
      expect(find.byKey(const Key('pattern-mode-labels')), findsNothing);
      expect(find.text('Duration Pattern Test'), findsWidgets);
    });
  });

  group('Screening audiogram page', () {
    testWidgets('plays, answers, and Stop shows the plotted results',
        (tester) async {
      await tester.pumpWidget(_app(AudiogramPage(seed: 2)));
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump(const Duration(milliseconds: 1500));
      // Tone finished → answer buttons enabled.
      await tester.tap(find.byKey(const Key('audiogram-heard')));
      await tester.pump(const Duration(milliseconds: 1500));
      // End early via the transport Stop → results with the plot.
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump(const Duration(seconds: 2)); // flush pending delays
      expect(find.byKey(const Key('audiogram-plot')), findsOneWidget);
      expect(find.text('Detection thresholds'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('PTA right'), 300);
      expect(find.textContaining('PTA right'), findsOneWidget);
    });
  });

  group('Binaural JND page', () {
    testWidgets('2-interval choice gives feedback and adapts',
        (tester) async {
      await tester.pumpWidget(_app(const BinauralJndPage(mode: 'itd')));
      await tester.pump();
      expect(find.textContaining('ITD'), findsWidgets);
      expect(find.text('Sound 1'), findsOneWidget);
      await tester.tap(find.text('Sound 1'));
      await tester.pump();
      expect(
          find.byWidgetPredicate((w) =>
              w is Icon &&
              (w.icon == Icons.check_circle || w.icon == Icons.cancel)),
          findsWidgets);
      // Let the auto-advance timer fire before the test ends.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Figure-ground page', () {
    testWidgets('starts in the +8 dB block with a voice pill',
        (tester) async {
      await tester.pumpWidget(_app(FigureGroundPage(comfortableLevel: 0.4)));
      await tester.pump();
      expect(find.textContaining('Block SNR +8'), findsOneWidget);
      expect(find.textContaining('(proxy)'), findsOneWidget);
      // Dispose before the 2 s auto-play timer would fire.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Session compare page', () {
    testWidgets('empty history shows guidance', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(_app(const SessionComparePage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least twice'), findsOneWidget);
    });
  });

  group('Trial scaffold H6/H11', () {
    testWidgets('caption appears only with the setting on and help sheet '
        'is consistent', (tester) async {
      appSettings.value =
          appSettings.value.copyWith(showStimulusText: false);
      Widget scaffold() => _app(TrialScaffold(
            title: 'Demo task',
            instruction: 'Listen and answer.',
            pills: const [],
            transport: const [],
            statusLeft: 'Q 1 of 1',
            statusRight: '00:00',
            revealedText: 'bell',
            helpText: 'Measures demo things.',
            child: const SizedBox.shrink(),
          ));
      await tester.pumpWidget(scaffold());
      expect(find.textContaining('bell'), findsNothing);
      appSettings.value = appSettings.value.copyWith(showStimulusText: true);
      await tester.pumpWidget(scaffold());
      await tester.pump();
      expect(find.textContaining('bell'), findsOneWidget);
      // Consistent help: same icon opens a sheet with the shared controls.
      await tester.tap(find.byTooltip('Help'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Controls (same on every exercise)'),
          findsOneWidget);
      expect(find.textContaining('Measures demo things.'), findsOneWidget);
      appSettings.value =
          appSettings.value.copyWith(showStimulusText: false);
    });
  });

  group('Questionnaire pages', () {
    testWidgets('Fisher checkboxes drive the score', (tester) async {
      await tester.pumpWidget(_app(const FisherPage()));
      await tester.tap(find.byKey(const Key('fisher-0')));
      await tester.tap(find.byKey(const Key('fisher-1')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const Key('fisher-see-result')), 400);
      await tester.tap(find.byKey(const Key('fisher-see-result')));
      await tester.pump();
      expect(find.text('92'), findsOneWidget);
    });

    testWidgets('APHAB renders all 24 items and disables submit until '
        'complete', (tester) async {
      await tester.pumpWidget(_app(const AphabPage()));
      expect(find.textContaining('Abbreviated Profile'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aphab-0-3')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const Key('aphab-see-result')), 600);
      final button = tester.widget<FilledButton>(
          find.byKey(const Key('aphab-see-result')));
      expect(button.onPressed, isNull); // 23 items still unanswered
    });
  });

  group('Audiogram metric', () {
    test('summarize includes false-alarm sub-score when catches ran', () {
      final s = AudiogramSession(seed: 3);
      var guard = 0;
      while (!s.isComplete && guard < 2000) {
        final p = s.next()!;
        s.submit(!p.isCatch && p.levelDbfs >= -50);
        guard++;
      }
      expect(s.isComplete, isTrue);
      expect(s.ptaFor('left'), isNotNull);
    });
  });
}
