import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/norms.dart';
import 'package:hearbloom/features/battery/capd_battery_presets.dart';
import 'package:hearbloom/features/common/practice_overlay.dart';
import 'package:hearbloom/features/headphone_check/headphone_check_page.dart';
import 'package:hearbloom/features/scap/scap_page.dart';

void main() {
  group('age-stratified norms', () {
    test('ageBandFor maps ages to the correct band', () {
      expect(ageBandFor(5), AgeBand.years7to8); // below 7 falls back to youngest
      expect(ageBandFor(7), AgeBand.years7to8);
      expect(ageBandFor(8), AgeBand.years7to8);
      expect(ageBandFor(9), AgeBand.years9to10);
      expect(ageBandFor(10), AgeBand.years9to10);
      expect(ageBandFor(11), AgeBand.years11to12);
      expect(ageBandFor(12), AgeBand.years11to12);
      expect(ageBandFor(13), AgeBand.years13to17);
      expect(ageBandFor(17), AgeBand.years13to17);
      expect(ageBandFor(18), AgeBand.years18to50);
      expect(ageBandFor(50), AgeBand.years18to50);
      expect(ageBandFor(51), AgeBand.years51to65);
      expect(ageBandFor(65), AgeBand.years51to65);
      expect(ageBandFor(66), AgeBand.years65plus);
      expect(ageBandFor(90), AgeBand.years65plus);
    });

    test('GIN interpretation is age-dependent (lower is better)', () {
      // Adult cut-off is 6 ms.
      expect(interpretWithAge(test: 'gin', ageYears: 30, value: 3).band,
          NormBand.betterThanTypical);
      expect(interpretWithAge(test: 'gin', ageYears: 30, value: 5).band,
          NormBand.withinTypical);
      expect(interpretWithAge(test: 'gin', ageYears: 30, value: 7).band,
          NormBand.slightlyBelowTypical);
      expect(interpretWithAge(test: 'gin', ageYears: 30, value: 12).band,
          NormBand.belowTypical);
      // Same 7 ms is "within typical" for a 7-year-old (cut-off 8 ms).
      expect(interpretWithAge(test: 'gin', ageYears: 7, value: 7).band,
          NormBand.withinTypical);
    });

    test('DPT/FPT/DDT interpretation (higher is better)', () {
      expect(interpretWithAge(test: 'dpt', ageYears: 30, value: 90).band,
          NormBand.betterThanTypical);
      expect(interpretWithAge(test: 'dpt', ageYears: 30, value: 80).band,
          NormBand.withinTypical);
      expect(interpretWithAge(test: 'dpt', ageYears: 30, value: 65).band,
          NormBand.slightlyBelowTypical);
      expect(interpretWithAge(test: 'dpt', ageYears: 30, value: 50).band,
          NormBand.belowTypical);

      expect(interpretWithAge(test: 'fpt', ageYears: 30, value: 60).band,
          NormBand.belowTypical);
      expect(interpretWithAge(test: 'ddt', ageYears: 30, value: 92).band,
          NormBand.withinTypical);
      // A 7-year-old's DDT cut-off is 85%, so 86% is within typical.
      expect(interpretWithAge(test: 'ddt', ageYears: 7, value: 86).band,
          NormBand.withinTypical);
    });

    test('MLD and SIN interpretation', () {
      expect(interpretWithAge(test: 'mld', ageYears: 30, value: 14).band,
          NormBand.betterThanTypical);
      expect(interpretWithAge(test: 'mld', ageYears: 30, value: 4).band,
          NormBand.belowTypical);
      // SIN SNR-loss: lower is better.
      expect(interpretWithAge(test: 'sin', ageYears: 30, value: 0).band,
          NormBand.betterThanTypical);
      expect(interpretWithAge(test: 'sin', ageYears: 30, value: 2).band,
          NormBand.withinTypical);
      expect(interpretWithAge(test: 'sin', ageYears: 30, value: 10).band,
          NormBand.belowTypical);
      // Older adults get a relaxed SIN cut-off (5 dB at 51–65).
      expect(interpretWithAge(test: 'sin', ageYears: 60, value: 5).band,
          NormBand.withinTypical);
    });

    test('known tests carry a citation; unknown tests are insufficient', () {
      expect(interpretWithAge(test: 'gin', ageYears: 30, value: 5).citation,
          isNotEmpty);
      final unknown =
          interpretWithAge(test: 'nope', ageYears: 30, value: 5);
      expect(unknown.isInsufficient, isTrue);
    });
  });

  group('SCAP screening', () {
    test('has 12 items and 3 options', () {
      expect(ScapScreening.items.length, 12);
      expect(ScapScreening.optionLabels, ['Never', 'Sometimes', 'Often']);
      expect(ScapScreening.maxScore, 24);
    });

    test('scoring and cut-off at 9', () {
      expect(ScapScreening.total(List<int>.filled(12, 0)), 0);
      expect(ScapScreening.total(List<int>.filled(12, 2)), 24);
      expect(ScapScreening.suggestsEvaluation(8), isFalse);
      expect(ScapScreening.suggestsEvaluation(9), isTrue);
      expect(ScapScreening.interpretation(9), contains('9'));
      expect(ScapScreening.recommendation(9), contains('evaluation'));
    });
  });

  group('CAPD battery presets', () {
    test('defines Screening, Full and ANSD-Focus', () {
      expect(kCapdBatteryPresets.length, 3);
      final byName = {for (final p in kCapdBatteryPresets) p.name: p};

      expect(byName['Screening']!.durationMinutes, 30);
      expect(byName['Screening']!.tests, ['GIN', 'DDT', 'DPT']);

      expect(byName['Full']!.durationMinutes, 60);
      expect(byName['Full']!.tests, ['GIN', 'DDT', 'DPT', 'FPT', 'MLD', 'SIN']);

      expect(byName['ANSD-Focus']!.durationMinutes, 45);
      expect(byName['ANSD-Focus']!.tests, ['GIN', 'MLD', 'SIN', 'Digit Span']);

      expect(byName['Screening']!.durationLabel, '~30 min');
    });
  });

  group('CapdBatteryPresetsPage widget', () {
    testWidgets('shows the three presets and returns the tapped name',
        (tester) async {
      CapdBatteryPreset? selected;
      await tester.pumpWidget(MaterialApp(
        home: CapdBatteryPresetsPage(onSelected: (p) => selected = p),
      ));

      expect(find.text('Screening'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('ANSD-Focus'), findsOneWidget);
      expect(find.text('~30 min'), findsOneWidget);

      await tester.tap(find.byKey(const Key('preset-Screening')));
      await tester.pump();
      expect(selected?.name, 'Screening');
    });
  });

  group('HeadphoneCheckPage widget', () {
    testWidgets('passes when both ears are answered correctly',
        (tester) async {
      bool? passed;
      await tester.pumpWidget(MaterialApp(
        home: HeadphoneCheckPage(
          earOrder: const ['left', 'right'],
          onCompleted: (p) => passed = p,
        ),
      ));
      await tester.pumpAndSettle();

      // Left ear tone -> tap Left.
      await tester.tap(find.byKey(const Key('side-left')));
      await tester.pumpAndSettle();
      // Right ear tone -> tap Right.
      await tester.tap(find.byKey(const Key('side-right')));
      await tester.pumpAndSettle();

      expect(passed, isTrue);
      expect(find.byKey(const Key('headphone-result')), findsOneWidget);
      expect(find.text('Headphones verified'), findsOneWidget);
    });

    testWidgets('fails when an ear is wrong', (tester) async {
      bool? passed;
      await tester.pumpWidget(MaterialApp(
        home: HeadphoneCheckPage(
          earOrder: const ['left', 'right'],
          onCompleted: (p) => passed = p,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('side-left'))); // left correct
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('side-left'))); // right wrong
      await tester.pumpAndSettle();

      expect(passed, isFalse);
      expect(find.text('Check failed'), findsOneWidget);
    });
  });

  group('PracticeOverlay widget', () {
    testWidgets('runs 3 practice trials then calls onComplete',
        (tester) async {
      var completed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PracticeOverlay(
              onComplete: () => completed = true,
              trialBuilder: (context, trialNumber, submit) => ElevatedButton(
                key: const Key('trial-btn'),
                onPressed: () =>
                    submit(correct: true, correctAnswer: 'A'),
                child: Text('Trial $trialNumber'),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('Practice round (1 of 3)'), findsOneWidget);

      for (var round = 1; round <= 3; round++) {
        await tester.tap(find.byKey(const Key('trial-btn')));
        await tester.pump();
        expect(find.byKey(const Key('practice-feedback')), findsOneWidget);
        expect(find.text('Correct!'), findsOneWidget);
        await tester.tap(find.byKey(const Key('practice-next')));
        await tester.pump();
      }

      expect(find.byKey(const Key('practice-complete')), findsOneWidget);
      expect(find.textContaining('Practice complete'), findsOneWidget);

      // The completion hand-off is delayed ~1s.
      expect(completed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(completed, isTrue);
    });
  });
}
