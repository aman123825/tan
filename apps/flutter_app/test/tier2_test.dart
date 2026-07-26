import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/confusion_matrix.dart';
import 'package:hearbloom/core/narrative_report.dart';
import 'package:hearbloom/core/phoneme_analysis.dart';
import 'package:hearbloom/core/settings/app_settings.dart';
import 'package:hearbloom/core/training/music_emotion.dart';
import 'package:hearbloom/core/training/pitch_ranking.dart';
import 'package:hearbloom/core/training/prosody.dart';
import 'package:hearbloom/core/training/reverb_training.dart';
import 'package:hearbloom/core/training/timbre.dart';
import 'package:hearbloom/features/common/playback_controls.dart';
import 'package:hearbloom/features/common/spectrogram_widget.dart';
import 'package:hearbloom/features/kids/kids_mode.dart';
import 'package:hearbloom/features/kids/kids_theme.dart';
import 'package:hearbloom/features/report/staircase_plot.dart';
import 'package:hearbloom/features/training/music_emotion_page.dart';
import 'package:hearbloom/features/training/pitch_ranking_page.dart';
import 'package:hearbloom/features/training/prosody_page.dart';
import 'package:hearbloom/features/training/reverb_page.dart';
import 'package:hearbloom/features/training/timbre_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    appSettings.value = const AppSettings();
    playbackPrefs.value = const PlaybackPrefs();
  });

  tearDown(() {
    appSettings.value = const AppSettings();
    playbackPrefs.value = const PlaybackPrefs();
  });

  // ============================================================ Prosody =====
  group('Prosody training', () {
    test('every task synthesizes non-empty audio', () {
      for (final task in ProsodyTask.values) {
        final trial =
            ProsodyTrial(task: task, answerIndex: 0, cueSemitones: 4);
        final samples = synthesizeProsody(trial);
        expect(samples, isNotEmpty, reason: '$task');
        expect(rms(samples), greaterThan(0));
      }
    });

    test('two correct answers shrink the cue; a wrong answer grows it', () {
      final s = ProsodySession(task: ProsodyTask.questionStatement);
      final start = s.cue;
      ProsodyTrial t() =>
          ProsodyTrial(task: s.task, answerIndex: 0, cueSemitones: s.cue);
      expect(s.submit(t(), 0), isTrue);
      expect(s.cue, start); // one correct doesn't move yet
      expect(s.submit(t(), 0), isTrue);
      expect(s.cue, lessThan(start)); // 2-down → harder
      final afterDown = s.cue;
      expect(s.submit(t(), 1), isFalse); // wrong → easier
      expect(s.cue, greaterThan(afterDown));
    });

    test('accuracy and bestCue track correct answers', () {
      final s = ProsodySession(maxTrials: 4);
      for (var i = 0; i < 4; i++) {
        s.submit(
            ProsodyTrial(
                task: s.task, answerIndex: 0, cueSemitones: s.cue),
            0);
      }
      expect(s.accuracy, 1.0);
      expect(s.isComplete, isTrue);
      expect(s.bestCue, isNotNull);
    });
  });

  // ============================================================= Reverb =====
  group('Reverb training', () {
    test('comb reverb lengthens the buffer and stays bounded', () {
      final dry = tone(seconds: 0.2, freqHz: 300);
      final wet = combReverb(dry, rt60Seconds: 0.8);
      expect(wet.length, greaterThan(dry.length));
      for (final v in wet) {
        expect(v.abs(), lessThanOrEqualTo(0.9001));
      }
    });

    test('RT60 ladder increases and maps by level', () {
      expect(kReverbRt60Ladder.first, 0.3);
      expect(reverbRt60ForLevel(0), 0.3);
      expect(reverbRt60ForLevel(kReverbMaxLevel), 1.2);
      expect(reverbRt60ForLevel(99), 1.2); // clamped
    });

    test('two correct raise the level; a wrong answer lowers it', () {
      final s = ReverbSession();
      final g = ReverbGenerator(seed: 1);
      ReverbTrial correctThenCheck() {
        final t = g.next(s.level);
        s.submit(t, t.targetIndex);
        return t;
      }

      correctThenCheck();
      expect(s.level, 0);
      correctThenCheck();
      expect(s.level, 1); // 2 correct → level up
      final t = g.next(s.level);
      final wrong = (t.targetIndex + 1) % t.choices.length;
      s.submit(t, wrong);
      expect(s.level, 0); // wrong → level down
    });
  });

  // ====================================================== Pitch ranking =====
  group('Pitch ranking', () {
    test('correctOrder sorts presentation indices low→high', () {
      const trial = PitchRankingTrial(freqs: [400, 200, 300], level: 0);
      expect(trial.correctOrder, [1, 2, 0]);
      expect(trial.score([1, 2, 0]), 1.0);
      expect(trial.score([0, 1, 2]), 0.0);
      expect(trial.isFullyCorrect([1, 2, 0]), isTrue);
    });

    test('partial score counts exact position matches', () {
      const trial = PitchRankingTrial(freqs: [100, 200, 300], level: 0);
      // correct order = [0,1,2]; swap last two → 1/3 correct.
      expect(trial.score([0, 2, 1]), closeTo(1 / 3, 1e-9));
    });

    test('two perfect trials advance the level', () {
      final s = PitchRankingSession();
      final g = PitchRankingGenerator(seed: 3);
      for (var i = 0; i < 2; i++) {
        final t = g.next(s.level);
        s.submit(t, t.correctOrder);
      }
      expect(s.maxLevelReached, greaterThanOrEqualTo(0));
      expect(s.level, greaterThan(0));
      expect(s.fullyCorrectCount, 2);
    });

    test('generator produces the configured tone count', () {
      final g = PitchRankingGenerator(seed: 0);
      expect(g.next(0).toneCount, kPitchRankingLevels[0].toneCount);
      expect(g.next(kPitchRankingMaxLevel).toneCount,
          kPitchRankingLevels[kPitchRankingMaxLevel].toneCount);
    });
  });

  // ============================================================= Timbre =====
  group('Timbre discrimination', () {
    test('each waveform synthesizes bounded, non-empty audio', () {
      for (final w in Waveform.values) {
        final s = waveformTone(w, 220, similarity: 0);
        expect(s, isNotEmpty, reason: w.label);
        for (final v in s) {
          expect(v.abs(), lessThanOrEqualTo(0.25001));
        }
      }
    });

    test('two correct raise similarity (harder); wrong lowers it', () {
      final s = TimbreSession();
      final g = TimbreGenerator(seed: 2);
      final start = s.similarity;
      var t = g.next(s.similarity);
      s.submit(t, t.targetIndex);
      t = g.next(s.similarity);
      s.submit(t, t.targetIndex);
      expect(s.similarity, greaterThan(start));
      final afterUp = s.similarity;
      t = g.next(s.similarity);
      s.submit(t, (t.targetIndex + 1) % t.choices.length);
      expect(s.similarity, lessThan(afterUp));
    });

    test('generator offers all four waveforms as choices', () {
      final t = TimbreGenerator(seed: 0).next(0.0);
      expect(t.choices.toSet(), Waveform.values.toSet());
    });
  });

  // ===================================================== Music emotion =====
  group('Emotion in music', () {
    test('generator yields a 4AFC trial with 4–8 notes', () {
      final g = MusicEmotionGenerator(seed: 5);
      for (var i = 0; i < 10; i++) {
        final t = g.next();
        expect(t.choices.length, 4);
        expect(t.choices.toSet(), MusicEmotion.values.toSet());
        expect(t.noteCount, inInclusiveRange(4, 8));
        expect(t.synthesize(), isNotEmpty);
      }
    });

    test('session tallies accuracy over trials', () {
      final s = MusicEmotionSession(maxTrials: 3);
      final g = MusicEmotionGenerator(seed: 1);
      for (var i = 0; i < 3; i++) {
        final t = g.next();
        s.submit(t, t.targetIndex);
      }
      expect(s.accuracy, 1.0);
      expect(s.isComplete, isTrue);
    });

    test('each emotion has a distinct spec', () {
      expect(kMusicEmotionSpecs.length, 4);
      expect(musicEmotionSpec(MusicEmotion.happy).noteSeconds,
          lessThan(musicEmotionSpec(MusicEmotion.sad).noteSeconds));
    });
  });

  // =================================================== Phoneme analysis =====
  group('Phoneme feature analysis', () {
    test('classifies the distinctive feature that changed', () {
      expect(classifyConfusion('ba', 'pa'), PhonemeFeatureError.voicing);
      expect(classifyConfusion('b', 'd'), PhonemeFeatureError.place);
      expect(classifyConfusion('t', 's'), PhonemeFeatureError.manner);
      expect(classifyConfusion('m', 'b'), PhonemeFeatureError.manner);
      expect(classifyConfusion('sha', 'cha'), isNotNull); // sh vs ch
      expect(classifyConfusion('x', 'q'), isNull); // unknown
    });

    test('tallies percentages and summarizes the primary deficit', () {
      final a = PhonemeErrorAnalysis.fromConfusions(const [
        ConfusionPair('b', 'p', 5), // voicing
        ConfusionPair('b', 'd', 2), // place
        ConfusionPair('t', 's', 1), // manner
      ]);
      expect(a.classifiedTotal, 8);
      expect(a.voicing, 5);
      expect(a.percentFor(PhonemeFeatureError.voicing), closeTo(62.5, 1e-9));
      final summary = a.summary();
      expect(summary, contains('voicing'));
      expect(summary.toLowerCase(), contains('primary deficit'));
    });

    test('builds from a ConfusionMatrix', () {
      final m = ConfusionMatrix()
        ..record('b', 'p')
        ..record('b', 'p')
        ..record('d', 'd'); // correct (diagonal, ignored)
      final a = PhonemeErrorAnalysis.fromMatrix(m);
      expect(a.voicing, 2);
      expect(a.classifiedTotal, 2);
    });
  });

  // =================================================== Narrative report =====
  group('Narrative report', () {
    test('maps below-norm temporal results to an Auditory Decoding profile',
        () {
      final r = generateNarrativeReport(const NarrativeInput(
        ageYears: 30,
        ginMs: 12,
        mldDb: 12,
        sinSnrDb: 2,
      ));
      expect(r.domainSentences, isNotEmpty);
      expect(r.paragraph, contains('below age norms'));
      expect(r.profile, NarrativeProfile.auditoryDecoding);
      expect(r.recommendations, contains('phonemic training'));
      expect(r.paragraph, contains('Profile: Auditory Decoding deficit'));
    });

    test('all-normal results give a within-normal-limits profile', () {
      final r = generateNarrativeReport(const NarrativeInput(
        ageYears: 30,
        ginMs: 4,
        mldDb: 14,
        sinSnrDb: 0,
        ddtRightPct: 95,
        ddtLeftPct: 95,
        digitSpan: 7,
      ));
      expect(r.profile, NarrativeProfile.withinNormalLimits);
      expect(r.paragraph, contains('within normal limits'));
    });

    test('empty input still produces a paragraph', () {
      final r = generateNarrativeReport(const NarrativeInput());
      expect(r.paragraph, contains('Profile'));
    });
  });

  // =================================================== Playback controls =====
  group('Playback controls', () {
    int channelsOf(Uint8List wav) => wav[22] | (wav[23] << 8);

    test('PlaybackPrefs identity + copyWith', () {
      const p = PlaybackPrefs();
      expect(p.isIdentity, isTrue);
      expect(p.copyWith(speed: 1.5).isIdentity, isFalse);
      expect(p.copyWith(channel: PlaybackChannel.left).isIdentity, isFalse);
    });

    test('resampleForSpeed changes length by the rate', () {
      final x = List<double>.filled(100, 0.5);
      expect(resampleForSpeed(x, 2.0).length, 50);
      expect(resampleForSpeed(x, 0.5).length, 200);
      expect(resampleForSpeed(x, 1.0).length, 100);
    });

    test('transformPlayback is a passthrough for identity prefs', () {
      final wav = encodeWav16(tone(seconds: 0.05, freqHz: 440));
      expect(identical(transformPlayback(wav, const PlaybackPrefs()), wav),
          isTrue);
    });

    test('transformPlayback resamples for speed (mono, both ears)', () {
      final wav = encodeWav16(tone(seconds: 0.1, freqHz: 440)); // 4800 samples
      final out = transformPlayback(
          wav, const PlaybackPrefs(speed: 2.0));
      expect(channelsOf(out), 1);
      expect(decodeWav16(out).samples.length, closeTo(2400, 2));
    });

    test('transformPlayback routes to a single channel (stereo output)', () {
      final wav = encodeWav16(tone(seconds: 0.05, freqHz: 440));
      final left =
          transformPlayback(wav, const PlaybackPrefs(channel: PlaybackChannel.left));
      final right =
          transformPlayback(wav, const PlaybackPrefs(channel: PlaybackChannel.right));
      expect(channelsOf(left), 2);
      expect(channelsOf(right), 2);
      // decodeWav16 returns the first (left) channel: full for left routing,
      // silent for right routing.
      expect(rms(decodeWav16(left).samples), greaterThan(0));
      expect(rms(decodeWav16(right).samples), 0);
    });

    test('PlaybackPrefsStore persists speed and channel', () async {
      final store = PlaybackPrefsStore();
      await store.setSpeed(1.5);
      await store.setChannel(PlaybackChannel.right);
      final loaded = await store.load();
      expect(loaded.speed, 1.5);
      expect(loaded.channel, PlaybackChannel.right);
    });
  });

  // ========================================================= Spectrogram =====
  group('Spectrogram', () {
    test('computes normalized frames of the right shape', () {
      final samples = tone(seconds: 0.05, freqHz: 1000); // 2400 samples
      final frames = computeSpectrogram(samples, fftSize: 32);
      expect(frames, isNotEmpty);
      expect(frames.first.length, 16); // fftSize / 2
      for (final f in frames) {
        for (final v in f) {
          expect(v, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('returns empty for too-few samples', () {
      expect(computeSpectrogram(List<double>.filled(10, 0.1), fftSize: 32),
          isEmpty);
    });

    test('colour map is bounded', () {
      expect(spectrogramColor(-1), spectrogramColor(0));
      expect(spectrogramColor(2), spectrogramColor(1));
    });
  });

  // ============================================================ Settings =====
  group('App settings (theme / motion / spectrogram)', () {
    test('ThemeChoice parsing and kidsMode getter', () {
      expect(ThemeChoiceInfo.fromStorage('kids'), ThemeChoice.kids);
      expect(ThemeChoiceInfo.fromStorage('light'), ThemeChoice.light);
      expect(ThemeChoiceInfo.fromStorage('nonsense'), ThemeChoice.dark);
      expect(const AppSettings(themeChoice: ThemeChoice.kids).kidsMode, isTrue);
      expect(const AppSettings().kidsMode, isFalse);
    });

    test('store persists theme, reduced motion and spectrogram', () async {
      final store = AppSettingsStore();
      await store.setThemeChoice(ThemeChoice.light);
      await store.setReducedMotion(true);
      await store.setShowSpectrogram(true);
      final loaded = await store.load();
      expect(loaded.themeChoice, ThemeChoice.light);
      expect(loaded.reducedMotion, isTrue);
      expect(loaded.showSpectrogram, isTrue);
    });

    test('kids_mode legacy flag stays in sync with the theme choice', () async {
      final store = AppSettingsStore();
      await store.setKidsMode(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppSettingsStore.kidsModeKey), isTrue);
      expect((await store.load()).themeChoice, ThemeChoice.kids);
      await store.setKidsMode(false);
      expect(prefs.getBool(AppSettingsStore.kidsModeKey), isFalse);
    });

    test('kids constants: mascot, greeting and reward stickers', () {
      expect(kKidsGreeting, contains('play'));
      expect(kKidsMascot, isNotEmpty);
      expect(kRewardStickers.length, 4);
      expect(kidsSticker(5), kRewardStickers[1]); // cycles
    });
  });

  // ========================================================= Widget tests =====
  group('Staircase plot widget', () {
    testWidgets('renders title and threshold legend', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 300, child: StaircasePlot(
            values: [12, 10, 8, 6, 8, 6, 4],
            reversalIndices: [3, 5],
            threshold: 5,
            title: 'Test staircase',
            unit: 'dB',
          )),
        ),
      ));
      await tester.pump();
      expect(find.text('Test staircase'), findsOneWidget);
      expect(find.text('Reversal'), findsOneWidget);
      expect(find.text('Threshold'), findsOneWidget);
    });

    testWidgets('empty values show a placeholder', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StaircasePlot(values: [])),
      ));
      await tester.pump();
      expect(find.textContaining('No adaptive trials'), findsOneWidget);
    });
  });

  group('Spectrogram widget', () {
    testWidgets('renders for a real buffer', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SpectrogramWidget(samples: tone(seconds: 0.05, freqHz: 800)),
        ),
      ));
      await tester.pump();
      expect(find.byType(SpectrogramWidget), findsOneWidget);
    });
  });

  group('Playback controls widget', () {
    testWidgets('opens a panel with speed and channel controls',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: Center(child: PlaybackControlsButton()),
        ),
      ));
      await tester.tap(find.byKey(const Key('playback-controls-button')));
      await tester.pumpAndSettle();
      expect(find.text('Playback controls'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Channel'), findsOneWidget);
    });
  });

  group('Kids mode banner', () {
    testWidgets('shows the greeting and mascot', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidsModeBanner()),
      ));
      await tester.pump();
      expect(find.text(kKidsGreeting), findsOneWidget);
      expect(find.text(kKidsMascot), findsOneWidget);
    });
  });

  group('Training pages smoke tests', () {
    testWidgets('Prosody page: pick a task then show choices', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: ProsodyPage(audioPort: SilentAudioPort())));
      await tester.pump();
      expect(find.text('Choose a listening game'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prosody-task-questionStatement')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // fire auto-play timer
      expect(find.text('Statement'), findsOneWidget);
      expect(find.text('Question'), findsOneWidget);
    });

    testWidgets('Reverb page renders choices', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: ReverbPage(audioPort: SilentAudioPort())));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Which word did you hear?'), findsOneWidget);
    });

    testWidgets('Timbre page renders four waveform choices', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: TimbrePage(audioPort: SilentAudioPort())));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sine'), findsOneWidget);
      expect(find.text('Square'), findsOneWidget);
    });

    testWidgets('Music emotion page renders four emotion choices',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: MusicEmotionPage(audioPort: SilentAudioPort())));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Happy'), findsOneWidget);
      expect(find.text('Calm'), findsOneWidget);
    });

    testWidgets('Pitch ranking page lets the user place tones',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
          MaterialApp(home: PitchRankingPage(audioPort: SilentAudioPort())));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tap the tones from LOWEST to HIGHEST'), findsOneWidget);
      // Place all tones (level 0 = 3 tones) then submit.
      await tester.tap(find.byKey(const Key('tone-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-2')));
      await tester.pump();
      expect(find.byKey(const Key('pitch-submit')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('pitch-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pitch-submit')));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });
  });
}
