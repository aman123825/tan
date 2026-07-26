import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/binaural_fusion.dart';
import 'package:hearbloom/core/competing_sentences.dart';
import 'package:hearbloom/core/compressed_speech.dart';
import 'package:hearbloom/core/dichotic.dart';
import 'package:hearbloom/core/filtered_speech.dart';
import 'package:hearbloom/core/hint_sin.dart';
import 'package:hearbloom/core/rgdt.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/binaural_fusion/binaural_fusion_page.dart';
import 'package:hearbloom/features/competing_sentences/competing_sentences_page.dart';
import 'package:hearbloom/features/filtered_speech/filtered_speech_page.dart';
import 'package:hearbloom/features/open_set/open_set_page.dart' show kOpenWordPool;
import 'package:hearbloom/features/report/pdf_report_page.dart';
import 'package:hearbloom/features/rgdt/rgdt_page.dart';
import 'package:hearbloom/features/trends/trend_page.dart';

Uint8List _demoWav() =>
    encodeWav16(tone(seconds: 0.1, freqHz: 300, amp: 0.3), sampleRate: 8000);

void main() {
  // ------------------------------------------------------------------ core --
  group('Competing sentences core', () {
    test('generator yields a distinct distractor and a 4-choice set with target',
        () {
      final gen = CompetingSentenceGenerator(seed: 3);
      for (var i = 0; i < 30; i++) {
        final t = gen.next();
        expect(t.target, isNot(equals(t.distractor)));
        expect(t.choices.length, 4);
        expect(t.choices, contains(t.target));
        expect(['left', 'right'], contains(t.targetEar));
      }
    });

    test('session tracks per-ear accuracy', () {
      final s = CompetingSentenceSession();
      final right = CompetingSentenceTrial(
        target: 'A',
        distractor: 'B',
        targetEar: 'right',
        choices: const ['A', 'B', 'C', 'D'],
      );
      final left = CompetingSentenceTrial(
        target: 'C',
        distractor: 'D',
        targetEar: 'left',
        choices: const ['A', 'B', 'C', 'D'],
      );
      expect(s.submit(right, 0, latencyMs: 1), isTrue); // correct
      expect(s.submit(left, 0, latencyMs: 1), isFalse); // wrong (chose A)
      expect(s.rightAccuracy, 1.0);
      expect(s.leftAccuracy, 0.0);
      expect(s.hasEar('left'), isTrue);
      expect(s.accuracy, closeTo(0.5, 1e-9));
    });
  });

  group('Filtered speech core', () {
    test('low-pass biquad attenuates a high tone more than a low tone', () {
      const sr = 8000;
      final low = tone(seconds: 0.2, freqHz: 200, amp: 0.5, sampleRate: sr);
      final high = tone(seconds: 0.2, freqHz: 3500, amp: 0.5, sampleRate: sr);
      final lowF = lowPassBiquad(low, 1000, sampleRate: sr);
      final highF = lowPassBiquad(high, 1000, sampleRate: sr);
      expect(rms(highF), lessThan(rms(lowF)));
      expect(rms(highF), lessThan(rms(high))); // high band is reduced
    });

    test('generator runs right-ear then left-ear blocks; session scores per ear',
        () {
      final gen =
          FilteredSpeechGenerator(pool: const ['bell'], trialsPerEar: 3);
      final ears = <String>[];
      while (!gen.isComplete) {
        ears.add(gen.next().ear);
      }
      expect(ears, ['right', 'right', 'right', 'left', 'left', 'left']);

      final s = FilteredSpeechSession(trialsPerEar: 3);
      s.submit(const FilteredSpeechTrial('bell', 'right'), 'bell',
          latencyMs: 1);
      s.submit(const FilteredSpeechTrial('bell', 'left'), 'wrong',
          latencyMs: 1);
      expect(s.rightPercent, 100);
      expect(s.leftPercent, 0);
    });
  });

  group('Compressed speech core', () {
    test('time compression shortens the buffer to ~ (1 - ratio)', () {
      final input = List<double>.generate(1000, (i) => i.toDouble());
      final out = timeCompress(input, 0.4);
      expect(out.length, closeTo(600, 2));
      expect(out.length, lessThan(input.length));
    });

    test('ratio 0 is a no-op; session scores whole words', () {
      final input = List<double>.filled(100, 0.1);
      expect(timeCompress(input, 0).length, 100);
      final s = CompressedSpeechSession(maxTrials: 2);
      s.submit(const CompressedSpeechTrial('cup'), 'cup', latencyMs: 1);
      s.submit(const CompressedSpeechTrial('cap'), 'cup', latencyMs: 1);
      expect(s.percent, 50);
    });
  });

  group('Binaural fusion core', () {
    test('high-pass biquad passes a high tone and attenuates a low tone', () {
      const sr = 8000;
      final low = tone(seconds: 0.2, freqHz: 200, amp: 0.5, sampleRate: sr);
      final high = tone(seconds: 0.2, freqHz: 3500, amp: 0.5, sampleRate: sr);
      expect(rms(highPassBiquad(low, 1000, sampleRate: sr)),
          lessThan(rms(highPassBiquad(high, 1000, sampleRate: sr))));
    });

    test('splitBands routes the low band to the chosen ear', () {
      const sr = 8000;
      final lowTone = tone(seconds: 0.2, freqHz: 200, amp: 0.5, sampleRate: sr);
      final left = splitBands(lowTone, LowBandEar.left, sampleRate: sr);
      // Low content routed to left → left louder than right for a low tone.
      expect(rms(left.left), greaterThan(rms(left.right)));
      final right = splitBands(lowTone, LowBandEar.right, sampleRate: sr);
      expect(rms(right.right), greaterThan(rms(right.left)));
      expect(left.left.length, lowTone.length);
    });

    test('session scores closed-set choices', () {
      final gen = BinauralFusionGenerator(pool: kOpenWordPool, seed: 1);
      final t = gen.next();
      expect(t.choices, contains(t.word));
      final s = BinauralFusionSession(maxTrials: 2);
      expect(s.submit(t, t.targetIndex, latencyMs: 1), isTrue);
      expect(s.percent, 100);
    });
  });

  group('Dichotic modes', () {
    test('cued mode (default) scores the cued ear only', () {
      final s = DichoticSession();
      expect(s.dichoticMode, DichoticMode.cued);
      final t = DichoticTrial(
          leftDigit: '1', rightDigit: '2', targetEar: Ear.right);
      expect(s.submit(t, '2', latencyMs: 1), isTrue);
      expect(s.rightAccuracy, 1.0);
    });

    test('free recall scores both ears order-independently', () {
      final s = DichoticSession(dichoticMode: DichoticMode.freeRecall);
      final t1 = DichoticTrial(
          leftDigit: '1', rightDigit: '2', targetEar: Ear.right);
      // Report in the "wrong" order — still both correct.
      expect(s.submitFreeRecall(t1, ['2', '1'], latencyMs: 1), isTrue);
      final t2 = DichoticTrial(
          leftDigit: '3', rightDigit: '4', targetEar: Ear.left);
      // Left correct, right wrong.
      expect(s.submitFreeRecall(t2, ['3', '9'], latencyMs: 1), isFalse);
      expect(s.leftAccuracy, 1.0); // 2/2 left digits recalled
      expect(s.rightAccuracy, closeTo(0.5, 1e-9)); // 1/2 right digits
    });

    test('directed mode computes a right-ear advantage', () {
      final s = DichoticSession(dichoticMode: DichoticMode.directed);
      s.submit(
          DichoticTrial(leftDigit: '1', rightDigit: '2', targetEar: Ear.right),
          '2',
          latencyMs: 1); // right correct
      s.submit(
          DichoticTrial(leftDigit: '3', rightDigit: '4', targetEar: Ear.left),
          '9',
          latencyMs: 1); // left wrong
      expect(s.rightAccuracy, 1.0);
      expect(s.leftAccuracy, 0.0);
      expect(s.rightEarAdvantage, 100);
    });

    test('generator honours a forced ear', () {
      final t = DichoticGenerator(seed: 2).next(forceEar: Ear.left);
      expect(t.targetEar, Ear.left);
    });
  });

  group('HINT sentence-in-noise core', () {
    test('two correct responses lower the SNR by one step (2-down/1-up)', () {
      final s = HintSinSession();
      expect(s.currentSnrDb, 10);
      s.submit('the cat sat', 'the cat sat', latencyMs: 1); // 1.0
      expect(s.currentSnrDb, 10); // no move after 1 correct
      s.submit('the cat sat', 'the cat sat', latencyMs: 1); // 1.0
      expect(s.currentSnrDb, 8); // dropped one 2 dB step
    });

    test('word-accuracy below threshold counts as incorrect (raises SNR)', () {
      final s = HintSinSession();
      final score = s.submit('one two three four', 'zero', latencyMs: 1);
      expect(score, lessThan(0.5));
      expect(s.currentSnrDb, 12); // one wrong raises SNR by a step
    });

    test('sequencer is deterministic for a seed', () {
      final a = HintSentenceSequencer(seed: 5);
      final b = HintSentenceSequencer(seed: 5);
      expect(a.sentenceFor(0), b.sentenceFor(0));
      expect(a.sentenceFor(3), b.sentenceFor(3));
    });
  });

  group('RGDT core', () {
    test('generator emits the planned number of trials', () {
      final gen = RgdtGenerator(
          presentationsPerGap: 2, catchPerFrequency: 1, seed: 0);
      // 4 freqs × (8 gaps × 2 + 1 catch) = 68
      expect(gen.totalTrials, 68);
    });

    test('threshold is the smallest gap detected on >= 2/3 of trials', () {
      final s = RgdtSession();
      // 2 ms gap: not detected (0/2)
      s.submit(const RgdtTrial(frequencyHz: 500, gapMs: 2), false,
          latencyMs: 1);
      s.submit(const RgdtTrial(frequencyHz: 500, gapMs: 2), false,
          latencyMs: 1);
      // 5 ms gap: detected 2/2
      s.submit(const RgdtTrial(frequencyHz: 500, gapMs: 5), true, latencyMs: 1);
      s.submit(const RgdtTrial(frequencyHz: 500, gapMs: 5), true, latencyMs: 1);
      expect(s.thresholdForFrequency(500), 5);
    });

    test('combined threshold averages per-frequency thresholds', () {
      final s = RgdtSession(frequencies: const [500, 1000]);
      s.submit(const RgdtTrial(frequencyHz: 500, gapMs: 5), true, latencyMs: 1);
      s.submit(const RgdtTrial(frequencyHz: 1000, gapMs: 15), true,
          latencyMs: 1);
      expect(s.perFrequencyThresholds[500], 5);
      expect(s.perFrequencyThresholds[1000], 15);
      expect(s.combinedThresholdMs, 10);
    });

    test('catch trial (no gap) is correct when "one sound" is reported', () {
      const catchTrial = RgdtTrial(frequencyHz: 1000, gapMs: 0);
      expect(catchTrial.isCorrect(false), isTrue); // heardTwo=false
      expect(catchTrial.isCorrect(true), isFalse);
    });
  });

  group('Report classification', () {
    test('abnormal pattern is described; all-normal is "No clear"', () {
      final profile = classifyCapdProfile(kSampleReportEntries);
      expect(profile.toLowerCase(), contains('difficulty'));
      final normal = [
        const ReportEntry(
          testName: 'x',
          score: '95%',
          norm: '≥ 90%',
          interpretation: 'ok',
          withinNorm: true,
          category: CapdCategory.dichotic,
        ),
      ];
      expect(classifyCapdProfile(normal), contains('No clear'));
    });

    test('recommendations always include an audiologist referral', () {
      final recs = reportRecommendations(kSampleReportEntries);
      expect(recs, isNotEmpty);
      expect(recs.join(' ').toLowerCase(), contains('audiologist'));
    });
  });

  group('Trend regression', () {
    test('slope of a perfectly linear series', () {
      expect(linearRegressionSlope([0, 1, 2, 3], [10, 20, 30, 40]),
          closeTo(10, 1e-9));
      expect(linearRegressionIntercept([0, 1, 2, 3], [10, 20, 30, 40]),
          closeTo(10, 1e-9));
    });

    test('slope classification into improving/stable/declining', () {
      expect(trendFromSlope(10), TrendDirection.improving);
      expect(trendFromSlope(-10), TrendDirection.declining);
      expect(trendFromSlope(0), TrendDirection.stable);
      expect(trendFromSlope(0.5), TrendDirection.stable); // within dead-band
    });

    test('degenerate input yields zero slope', () {
      expect(linearRegressionSlope([1], [5]), 0);
      expect(linearRegressionSlope([2, 2, 2], [1, 2, 3]), 0);
    });
  });

  // ---------------------------------------------------------------- widgets --
  group('Phase 2 widgets', () {
    testWidgets('competing sentences plays stereo then scores the choice',
        (tester) async {
      final port = SilentAudioPort();
      final target = CompetingSentenceGenerator(seed: 0).next().target;
      await tester.pumpWidget(MaterialApp(
        home: CompetingSentencesPage(
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

    testWidgets('filtered speech plays a filtered word then scores typing',
        (tester) async {
      final port = SilentAudioPort();
      await tester.pumpWidget(MaterialApp(
        home: FilteredSpeechPage(
          comfortableLevel: 0.4,
          wordPool: const ['bell'],
          trialsPerEar: 2,
          audioPort: port,
          assetLoader: (_) async => _demoWav(),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);

      await tester.enterText(find.byType(TextField), 'bell');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('binaural fusion plays split-band stereo then scores a choice',
        (tester) async {
      final port = SilentAudioPort();
      final t = BinauralFusionGenerator(pool: kOpenWordPool, seed: 0).next();
      await tester.pumpWidget(MaterialApp(
        home: BinauralFusionPage(
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

      await tester.tap(find.text(t.word));
      await tester.pump();
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('RGDT plays a tone pair then accepts a one/two response',
        (tester) async {
      final port = SilentAudioPort();
      await tester.pumpWidget(MaterialApp(
        home: RgdtPage(
          comfortableLevel: 0.4,
          presentationsPerGap: 1,
          catchPerFrequency: 0,
          audioPort: port,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(port.playCount, 1);

      await tester.tap(find.text('Two sounds'));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('report card shows CAPD profile and copy action',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PdfReportPage()));
      await tester.pump();
      expect(find.textContaining('CAPD'), findsWidgets);
      expect(find.text('Copy to clipboard'), findsOneWidget);
      expect(find.text('Recommendations'), findsOneWidget);
    });

    testWidgets('trend page labels an improving series', (tester) async {
      final now = DateTime(2025, 1, 1);
      final records = [
        for (var i = 0; i < 3; i++)
          SessionRecord(
            timestamp: now.add(Duration(days: i)),
            moduleId: 'auditory',
            groupId: 'gap',
            title: 'Gap detection',
            accuracy: 0.5 + i * 0.2,
            trials: 10,
          ),
      ];
      await tester.pumpWidget(MaterialApp(home: TrendPage(records: records)));
      await tester.pump();
      expect(find.text('Improving'), findsOneWidget);
    });
  });
}
