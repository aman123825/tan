import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/asr.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/audio/task_stimuli.dart';
import 'package:hearbloom/core/chord_identification.dart';
import 'package:hearbloom/core/closed_set.dart';
import 'package:hearbloom/core/content_pools.dart';
import 'package:hearbloom/core/dichotic.dart';
import 'package:hearbloom/core/identification.dart';
import 'package:hearbloom/core/interval_task.dart';
import 'package:hearbloom/core/mci.dart';
import 'package:hearbloom/core/open_set.dart';
import 'package:hearbloom/core/protocol_engine.dart';
import 'package:hearbloom/core/sequence_entry.dart';
import 'package:hearbloom/core/speech_in_noise.dart';
import 'package:hearbloom/data/api.dart';
import 'package:hearbloom/features/catalog/validation_badge.dart';
import 'package:hearbloom/features/battery/battery_page.dart';
import 'package:hearbloom/features/chord/chord_identification_page.dart';
import 'package:hearbloom/features/closed_set/closed_set_page.dart';
import 'package:hearbloom/features/comfortable_level/comfortable_level_page.dart';
import 'package:hearbloom/features/dichotic/dichotic_page.dart';
import 'package:hearbloom/features/fatigue/fatigue_sheet.dart';
import 'package:hearbloom/features/gap_detection/gap_detection_page.dart';
import 'package:hearbloom/features/identification/identification_page.dart';
import 'package:hearbloom/features/interval_task/interval_task_page.dart';
import 'package:hearbloom/features/mci/mci_page.dart';
import 'package:hearbloom/features/modulation_detection/modulation_detection_page.dart';
import 'package:hearbloom/features/modulation_rate/modulation_rate_page.dart';
import 'package:hearbloom/features/note_sequence/note_sequence_page.dart';
import 'package:hearbloom/features/open_set/open_set_page.dart';
import 'package:hearbloom/features/pitch_discrimination/pitch_discrimination_page.dart';
import 'package:hearbloom/features/protocol/protocol_intro_screen.dart';
import 'package:hearbloom/features/results/results_page.dart';
import 'package:hearbloom/features/review/clinician_review_page.dart';
import 'package:hearbloom/features/sequence_entry/sequence_entry_page.dart';
import 'package:hearbloom/features/speech_in_noise/speech_in_noise_page.dart';

void main() {
  testWidgets('validation badge surfaces the research status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ValidationBadge(validationStatus: 'unvalidated')),
        ),
      ),
    );
    expect(find.text('UNVALIDATED'), findsOneWidget);
  });

  testWidgets('comfortable-level check locks the level and disables the slider',
      (tester) async {
    double? locked;
    await tester.pumpWidget(
      MaterialApp(home: ComfortableLevelPage(onLocked: (l) => locked = l)),
    );

    // Research + non-diagnostic messaging is present.
    expect(find.text('RESEARCH ONLY'), findsOneWidget);
    expect(find.textContaining('not a hearing test'), findsOneWidget);

    // Slider starts enabled (user can calibrate).
    Slider slider = tester.widget(find.byType(Slider));
    expect(slider.onChanged, isNotNull);

    // Lock the level.
    await tester.ensureVisible(find.text('Lock level and continue'));
    await tester.tap(find.text('Lock level and continue'));
    await tester.pumpAndSettle();

    // Callback fired and the locked state is shown.
    expect(locked, isNotNull);
    expect(find.textContaining('Level locked'), findsOneWidget);

    // Slider is now disabled — no in-test volume changes.
    slider = tester.widget(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });

  testWidgets('speech-in-noise plays real word-in-noise then advances',
      (tester) async {
    // A valid WAV so the renderer can decode + mix + play a real stimulus.
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final firstTrial = FourAfcGenerator(kDemoWordPool, seed: 7).next();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeechInNoisePage(
          moduleId: 'noise',
          groupId: 'sentence_noise',
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 7,
          audioPort: port,
          assetLoader: (path) async => wavBytes,
        ),
      ),
    );
    await tester.pump();

    // Locked level is shown and the sample must be played first.
    expect(find.textContaining('Level 40%'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    // The word was decoded, mixed with noise at the current SNR, and played.
    expect(port.playCount, 1);
    expect(port.lastPlayed, isNotNull);
    expect(find.textContaining('Replay'), findsOneWidget);

    // Choose an answer -> training feedback + advance control appears.
    await tester.tap(find.text(firstTrial.choices.first));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('speech-in-noise auto-advances ~1.5s after a choice (Fix B)',
      (tester) async {
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final firstTrial = FourAfcGenerator(kDemoWordPool, seed: 7).next();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeechInNoisePage(
          moduleId: 'noise',
          groupId: 'sentence_noise',
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 7,
          audioPort: port,
          assetLoader: (path) async => wavBytes,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    // Right after answering: manual Next is offered; the "play me first" hint
    // is hidden because the sample has been played this trial.
    await tester.tap(find.text(firstTrial.choices.first));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Play the sample to enable the choices.'), findsNothing);

    // Without tapping Next, the flow advances by itself (a short beat after
    // the corrective replays on a wrong answer, ~1.5 s on a correct one):
    // Next is gone and a fresh, unanswered trial is on screen.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsNothing);
    expect(find.textContaining('Question 2 of'), findsOneWidget);
  });

  testWidgets('gap detection plays synthesized audio and advances on a choice',
      (tester) async {
    final port = SilentAudioPort();
    await tester.pumpWidget(
      MaterialApp(
        home: GapDetectionPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 1,
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Wired-headphone guidance for temporal tasks is shown.
    expect(find.textContaining('wired headphones'), findsOneWidget);
    // Auto-played on trial start — no manual Play tap needed.
    expect(port.playCount, 1);
    expect(port.lastPlayed, isNotNull);
    expect(find.text('Replay sequence (0/5)'), findsOneWidget);

    // Choosing an interval records the trial and offers to advance.
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('results page exports CSV via a copyable dialog', (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/results')) {
        return http.Response(
          '{"total_trials":1,"accuracy":1.0,'
          '"pooling_policy":"not_pooled_across_condition_or_device",'
          '"separated":[{"condition":"binaural","output_device":"wired_headphones",'
          '"module_id":"noise","group_id":"sentence_noise","mode":"test","n":1,'
          '"accuracy":1.0,"mean_latency_ms":600.0,'
          '"reliability":{"reliable":false,"reason":"insufficient_trials"}}]}',
          200,
        );
      }
      if (req.url.path.endsWith('/export.csv')) {
        return http.Response(
          'at,session_id,module_id\n2026-07-24,abc,noise\n',
          200,
          headers: {'content-type': 'text/csv'},
        );
      }
      return http.Response('{}', 200);
    });
    final api = Api(baseUrl: 'http://test.local', client: mock);

    await tester.pumpWidget(
      MaterialApp(home: ResultsPage(profileId: 'p1', api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('By condition & device'), findsOneWidget);

    await tester.tap(find.byTooltip('Export CSV'));
    await tester.pumpAndSettle();
    expect(find.text('CSV export (research data)'), findsOneWidget);
    expect(find.textContaining('at,session_id,module_id'), findsOneWidget);
  });

  testWidgets('clinician review submits a review for a session',
      (tester) async {
    var reviewCalled = false;
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/export.json')) {
        return http.Response(
          '{"profile":{},"trials":[],"sessions":[{"id":"s1",'
          '"condition":"binaural","output_device":"wired_headphones",'
          '"started_at":"2026-07-24","review_status":null,'
          '"reviewed_by":null,"review_note":null}]}',
          200,
        );
      }
      if (req.url.path.contains('/sessions/') &&
          req.url.path.endsWith('/review')) {
        reviewCalled = true;
        return http.Response(
          '{"id":"s1","review_status":"approved","reviewed_by":"Dr Rao"}',
          200,
        );
      }
      return http.Response('{}', 200);
    });
    final api = Api(baseUrl: 'http://test.local', client: mock);

    await tester.pumpWidget(
      MaterialApp(home: ClinicianReviewPage(profileId: 'p1', api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('binaural · wired_headphones'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review session'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Dr Rao');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(reviewCalled, isTrue);
  });

  testWidgets('modulation detection plays synthesized audio and advances',
      (tester) async {
    final port = SilentAudioPort();
    await tester.pumpWidget(
      MaterialApp(
        home: ModulationDetectionPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 1,
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.textContaining('wired headphones'), findsOneWidget);
    expect(port.playCount, 1);
    expect(find.text('Replay sequence (0/5)'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('protocol intro walks Introduction -> Preview -> start',
      (tester) async {
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProtocolIntroScreen(
          title: 'Speech in noise',
          description: 'Task description here.',
          exampleText: 'Example instruction here.',
          onStart: () => started = true,
        ),
      ),
    );

    // Introduction stage.
    expect(find.text('Task description here.'), findsOneWidget);
    expect(find.text('See an example'), findsOneWidget);

    await tester.tap(find.text('See an example'));
    await tester.pumpAndSettle();

    // Preview stage.
    expect(find.text('Example instruction here.'), findsOneWidget);
    expect(find.text('Begin training'), findsOneWidget);

    await tester.tap(find.text('Begin training'));
    await tester.pumpAndSettle();
    expect(started, isTrue);
  });

  testWidgets('protocol intro can skip directly to the test', (tester) async {
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProtocolIntroScreen(
          title: 'Speech in noise',
          description: 'Task description here.',
          exampleText: 'Example instruction here.',
          onStart: () => started = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('protocol-intro-skip')));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('digit-span shows a sequence and scores exact recall',
      (tester) async {
    // Deterministic: the page's generator (same seed) yields this sequence.
    final expected = SequenceEntryGenerator(seed: 5).next(3);
    await tester.pumpWidget(
      const MaterialApp(home: SequenceEntryPage(seed: 5, maxTrials: 3)),
    );
    await tester.pump();

    expect(find.text("I'm ready"), findsOneWidget);
    await tester.tap(find.text("I'm ready"));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), expected.join());
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('MCI plays a contour and scores the chosen shape (labelled)',
      (tester) async {
    final target = MciGenerator(seed: 2).next();
    final port = SilentAudioPort();
    await tester.pumpWidget(
      MaterialApp(
        home: MciPage(
          seed: 2,
          maxTrials: 3,
          audioPort: port,
          assetLoader: (path) async => Uint8List(4),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play contour'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    // Accessibility: each contour choice declares a semantic label.
    final label = contourLabel(target.targetPattern);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      ),
      findsWidgets,
    );

    await tester.tap(find.text(label).first);
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('pitch discrimination plays tones with labelled intervals',
      (tester) async {
    final port = SilentAudioPort();
    await tester.pumpWidget(
      MaterialApp(
        home: PitchDiscriminationPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 1,
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Auto-played on trial start — no manual Play tap.
    expect(port.playCount, 1);
    expect(find.text('Replay tones (0/5)'), findsOneWidget);

    // Accessibility: interval buttons declare semantic labels.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Tone 1',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('results page renders an accuracy chart for multiple conditions',
      (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/results')) {
        return http.Response(
          '{"total_trials":40,"accuracy":0.9,'
          '"pooling_policy":"not_pooled_across_condition_or_device",'
          '"separated":['
          '{"condition":"binaural","output_device":"wired_headphones",'
          '"module_id":"noise","group_id":"sentence_noise","mode":"test","n":20,'
          '"accuracy":1.0,"mean_latency_ms":600.0,'
          '"reliability":{"reliable":true,"replay_rate":0.0,"fast_rate":0.0}},'
          '{"condition":"binaural","output_device":"bluetooth",'
          '"module_id":"noise","group_id":"sentence_noise","mode":"training",'
          '"n":20,"accuracy":0.8,"mean_latency_ms":500.0,'
          '"reliability":{"reliable":true,"replay_rate":0.0,"fast_rate":0.0}}]}',
          200,
        );
      }
      return http.Response('{}', 200);
    });
    final api = Api(baseUrl: 'http://test.local', client: mock);

    await tester.pumpWidget(
      MaterialApp(home: ResultsPage(profileId: 'p1', api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.textContaining('Accuracy by condition'), findsOneWidget);

    // The cited normative reference strip is present (research context).
    await tester.scrollUntilVisible(
      find.text('Research reference points (illustrative)'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.text('Research reference points (illustrative)'), findsOneWidget);
    expect(find.textContaining('Musiek et al., 2005'), findsOneWidget);
  });

  testWidgets('modulation-rate discrimination plays sounds and advances',
      (tester) async {
    final port = SilentAudioPort();
    await tester.pumpWidget(
      MaterialApp(
        home: ModulationRatePage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 1,
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(port.playCount, 1);
    expect(find.text('Replay sounds (0/5)'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('open-word recognition scores a typed answer (normalized)',
      (tester) async {
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final target = OpenSetGenerator(kOpenWordPool, seed: 4).next();

    await tester.pumpWidget(
      MaterialApp(
        home: OpenSetPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 4,
          audioPort: port,
          assetLoader: (path) async => wavBytes,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play word'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);
    // ASR assistance is disabled by default: no microphone affordance.
    expect(find.text('Speak'), findsNothing);

    // Case/punctuation-insensitive: typing the word in caps still scores.
    await tester.enterText(find.byType(TextField), target.toUpperCase());
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('interval task auto-plays and scores the odd-interval choice',
      (tester) async {
    final port = SilentAudioPort();
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'amplitude',
      paramName: 'delta_db',
      track: AdaptiveTrack(value: 8, min: 0.5, max: 15, step: 1),
      maxTrials: 3,
    );
    final target = ThreeIntervalGenerator(seed: 2, intervals: 3).next();

    await tester.pumpWidget(
      MaterialApp(
        home: IntervalTaskPage(
          title: 'Loudness discrimination',
          instruction: 'Pick the odd one.',
          session: session,
          seed: 2,
          synth: (t, p, i) => List<double>.filled(2400, 0.1),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(1)} dB',
          thresholdText: (t) => t == null ? 'not reached' : '$t',
          choiceWord: 'Sound',
          audioPort: port,
        ),
      ),
    );
    // The trial auto-plays after the 1.2 s breathing room.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Auto-played on trial start — no manual Play tap needed.
    expect(port.playCount, 1);
    expect(find.text('Replay (0/5)'), findsOneWidget);

    await tester.tap(find.text('Sound ${target.targetInterval + 1}'));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('interval task re-plays the sounds twice after a wrong answer',
      (tester) async {
    final port = SilentAudioPort();
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'amplitude',
      paramName: 'delta_db',
      track: AdaptiveTrack(value: 8, min: 0.5, max: 15, step: 1),
      maxTrials: 3,
    );
    final target = ThreeIntervalGenerator(seed: 2, intervals: 3).next();

    await tester.pumpWidget(
      MaterialApp(
        home: IntervalTaskPage(
          title: 'Loudness discrimination',
          instruction: 'Pick the odd one.',
          session: session,
          seed: 2,
          synth: (t, p, i) => List<double>.filled(2400, 0.1),
          paramChip: (v) => 'x',
          thresholdText: (t) => 'x',
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(port.playCount, 1); // auto-play

    final wrong = (target.targetInterval + 1) % 3;
    await tester.tap(find.text('Sound ${wrong + 1}'));
    // Bounded pumps: check feedback + replays before the 0.3 s beat that
    // auto-advances to the next trial.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Not quite'), findsOneWidget);
    // 1 auto-play + 2 corrective replays.
    expect(port.playCount, 3);
    // Then the flow moves on by itself.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Not quite'), findsNothing);
  });

  testWidgets('interval task caps manual replay at 5', (tester) async {
    final port = SilentAudioPort();
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'amplitude',
      paramName: 'delta_db',
      track: AdaptiveTrack(value: 8, min: 0.5, max: 15, step: 1),
      maxTrials: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IntervalTaskPage(
          title: 'X',
          instruction: 'Y',
          session: session,
          seed: 2,
          synth: (t, p, i) => List<double>.filled(2400, 0.1),
          paramChip: (v) => 'x',
          thresholdText: (t) => 'x',
          audioPort: port,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(port.playCount, 1); // auto-play

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byIcon(Icons.replay));
      await tester.pumpAndSettle();
    }
    // 1 auto-play + at most 5 manual replays.
    expect(port.playCount, 6);
    expect(find.text('Replay (5/5)'), findsOneWidget);
  });

  testWidgets('chord identification plays then scores a choice',
      (tester) async {
    final port = SilentAudioPort();
    final trial = ChordGenerator(seed: 3).next();

    await tester.pumpWidget(
      MaterialApp(
        home: ChordIdentificationPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 3,
          audioPort: port,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play chord'), findsOneWidget);
    await tester.tap(find.text('Play chord'));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    await tester.tap(find.text(kChordChoices[trial.targetIndex].label));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('note sequence plays then scores a tapped melody',
      (tester) async {
    final port = SilentAudioPort();
    const notes = ['C', 'D', 'E', 'F', 'G'];
    // Same seed/symbols/first-length as the page's first trial.
    final target = SymbolSequenceGenerator(notes, seed: 5).next(2);

    await tester.pumpWidget(
      MaterialApp(
        home: SymbolSequencePage(
          moduleId: 'openset',
          groupId: 'melody_sequence',
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 5,
          symbols: notes,
          synth: (s) => noteSequenceStimulus(s),
          title: 'Melody recall',
          playNoun: 'melody',
          audioPort: port,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play melody'), findsOneWidget);
    await tester.tap(find.text('Play melody'));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    for (final n in target) {
      await tester.tap(find.widgetWithText(FilledButton, n));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('closed-set identification plays then scores a choice',
      (tester) async {
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final trial =
        ClosedSetGenerator(pool: kDigitItems, choiceCount: 4, seed: 8).next();

    await tester.pumpWidget(
      MaterialApp(
        home: ClosedSetPage(
          moduleId: 'learning',
          groupId: 'numbers',
          comfortableLevel: 0.4,
          pool: kDigitItems,
          title: 'Number recognition',
          instruction: 'Pick the number.',
          choiceCount: 4,
          seed: 8,
          maxTrials: 3,
          audioPort: port,
          assetLoader: (path) async => wavBytes,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    await tester.tap(find.text(trial.target.label));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('closed-set word recognition runs in adaptive noise',
      (tester) async {
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final trial =
        ClosedSetGenerator(pool: kWordItems, choiceCount: 4, seed: 8).next();

    await tester.pumpWidget(
      MaterialApp(
        home: ClosedSetPage(
          moduleId: 'learning',
          groupId: 'word',
          comfortableLevel: 0.4,
          pool: kWordItems,
          title: 'Word recognition',
          instruction: 'Pick the word.',
          choiceCount: 4,
          seed: 8,
          maxTrials: 5,
          snrTrack: AdaptiveTrack.snr(),
          audioPort: port,
          assetLoader: (path) async => wavBytes,
        ),
      ),
    );
    await tester.pump();

    // The adaptive-noise chip is shown at the starting SNR (not "Quiet").
    expect(find.textContaining('Adaptive SNR 12 dB'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    await tester.tap(find.text(trial.target.label));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('battery runner shows an aggregate summary', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BatteryRunnerPage(title: 'Battery', level: 0.4, stages: []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Battery complete'), findsOneWidget);
    expect(find.text('Overall'), findsOneWidget);
  });

  testWidgets('identification plays then scores a choice', (tester) async {
    final port = SilentAudioPort();
    final wav = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final trial = IdentificationGenerator(
            pool: kEnvironmentChoices, choiceCount: 4, seed: 2)
        .next();

    await tester.pumpWidget(
      MaterialApp(
        home: IdentificationPage(
          moduleId: 'foundation',
          groupId: 'environment',
          comfortableLevel: 0.4,
          pool: kEnvironmentChoices,
          title: 'Environmental sounds',
          instruction: 'Pick the sound.',
          choiceCount: 4,
          seed: 2,
          maxTrials: 3,
          playLabel: 'Play sound',
          audioProvider: (t, i) async => wav,
          audioPort: port,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play sound'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    await tester.tap(find.text(trial.target.label));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('dichotic digits plays stereo then scores the cued ear',
      (tester) async {
    final port = SilentAudioPort();
    final digitWav = encodeWav16(
      tone(seconds: 0.15, freqHz: 300, amp: 0.3),
      sampleRate: 8000,
    );
    final trial = DichoticGenerator(seed: 1).next();

    await tester.pumpWidget(
      MaterialApp(
        home: DichoticPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 1,
          audioPort: port,
          assetLoader: (path) async => digitWav,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.playCount, 1);

    await tester.tap(find.text(trial.targetDigit));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('fatigue sheet reports a rating', (tester) async {
    int? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FatigueSheet(
            initial: 0,
            onSubmit: (r) => captured = r,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Bucket label reflects the initial rating.
    expect(find.text('None (0/10)'), findsOneWidget);

    // Select a higher rating -> label updates -> Save reports it.
    await tester.tap(find.widgetWithText(ChoiceChip, '7'));
    await tester.pump();
    expect(find.text('High (7/10)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(captured, 7);
  });

  testWidgets('open-set ASR assistance pre-fills the field; user still submits',
      (tester) async {
    final wavBytes = encodeWav16(
      tone(seconds: 0.2, freqHz: 300, amp: 0.3),
      sampleRate: 22050,
    );
    final port = SilentAudioPort();
    final target = OpenSetGenerator(kOpenWordPool, seed: 9).next();

    await tester.pumpWidget(
      MaterialApp(
        home: OpenSetPage(
          comfortableLevel: 0.4,
          maxTrials: 3,
          seed: 9,
          audioPort: port,
          assetLoader: (path) async => wavBytes,
          asr: _FakeAsr(AsrResult(target)),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    // Mic affordance appears only when a provider is available.
    expect(find.text('Speak'), findsOneWidget);
    await tester.tap(find.text('Speak'));
    await tester.pumpAndSettle();

    // The transcript pre-fills the field (editable); the listener submits.
    expect(find.text(target), findsWidgets);
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('Correct'), findsOneWidget);
  });
}

/// Deterministic fake ASR engine for tests (no model, no mic).
class _FakeAsr implements AsrProvider {
  _FakeAsr(this._result);
  final AsrResult _result;
  @override
  bool get isAvailable => true;
  @override
  Future<AsrResult?> listen() async => _result;
}
