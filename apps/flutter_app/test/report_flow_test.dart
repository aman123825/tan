import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/data/cloud_sync.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/onboarding/onboarding_page.dart';
import 'package:hearbloom/features/report/report_tab.dart';
import 'package:hearbloom/features/report/session_result_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('first-launch introduction is skippable and remembered',
      (tester) async {
    var finished = false;
    final store = OnboardingStore(key: 'test.onboarding');
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          store: store,
          onFinished: () => finished = true,
        ),
      ),
    );

    expect(find.text('Welcome to HearBloom'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(await store.isComplete(), isTrue);
  });

  testWidgets('empty report center never substitutes sample patient data',
      (tester) async {
    final history = SessionHistory(key: 'test.empty.history');
    final sync = CloudSyncService(
      history: history,
      lastSyncKey: 'test.empty.last_sync',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReportTabPage(history: history, syncService: sync),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your reports will appear here'), findsOneWidget);
    expect(
      find.text('No demonstration or sample patient data is shown here.'),
      findsOneWidget,
    );
    expect(find.text('Jane Doe'), findsNothing);
  });

  testWidgets('stored session opens an offline report with a graph',
      (tester) async {
    final history = SessionHistory(key: 'test.report.history');
    final record = _record();
    await history.add(record);
    final sync = CloudSyncService(
      history: history,
      lastSyncKey: 'test.report.last_sync',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReportTabPage(history: history, syncService: sync),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-session-0')));
    await tester.pumpAndSettle();

    expect(find.text('Test report'), findsOneWidget);
    expect(find.text('Answer breakdown'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Saved on this device'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Incorrect'), findsOneWidget);
  });

  testWidgets('privacy-declined result is shown but clearly not stored',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showSessionResultSheet(
                context,
                record: _record(),
                savedOffline: false,
              ),
              child: const Text('Open report'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Shown for this session only'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Shown for this session only'), findsOneWidget);
    expect(
      find.textContaining('privacy choice prevents local storage'),
      findsOneWidget,
    );
  });
}

SessionRecord _record() => SessionRecord(
      timestamp: DateTime(2026, 7, 27, 10, 30),
      moduleId: 'auditory',
      groupId: 'gap',
      title: 'Gap detection',
      accuracy: 0.75,
      trials: 8,
      metric: '4.2 ms',
      metricValue: 4.2,
      metricUnit: 'ms',
    );
