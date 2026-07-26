import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/audio/audio_port.dart';
import 'package:hearbloom/core/audio/pcm_synth.dart';
import 'package:hearbloom/core/fhir_export.dart';
import 'package:hearbloom/core/word_lists.dart';
import 'package:hearbloom/core/speech_in_noise.dart';
import 'package:hearbloom/core/tinnitus/pitch_match.dart';
import 'package:hearbloom/core/tinnitus/loudness_match.dart';
import 'package:hearbloom/core/tinnitus/mml.dart';
import 'package:hearbloom/core/tinnitus/ldl.dart';
import 'package:hearbloom/core/tinnitus/tinnitus_store.dart';
import 'package:hearbloom/core/tinnitus/therapy_sounds.dart';
import 'package:hearbloom/core/training/phonological.dart';
import 'package:hearbloom/core/training/scene_training.dart';
import 'package:hearbloom/core/training/interhemispheric.dart';
import 'package:hearbloom/core/training/sentence_closure.dart';
import 'package:hearbloom/data/api.dart';
import 'package:hearbloom/data/cloud_sync.dart';
import 'package:hearbloom/data/session_history.dart';
import 'package:hearbloom/features/remote/remote_sync_page.dart';
import 'package:hearbloom/features/settings/install_prompt.dart';
import 'package:hearbloom/features/tinnitus/pitch_match_page.dart';
import 'package:hearbloom/features/tinnitus/ldl_page.dart';
import 'package:hearbloom/features/tinnitus/sound_therapy_page.dart';
import 'package:hearbloom/features/training/phonological_page.dart';
import 'package:hearbloom/features/training/sentence_closure_page.dart';

void main() {
  // ================================================= T3-2 FHIR export ====
  group('FHIR export', () {
    test('parseScore extracts value + unit', () {
      expect(parseScore('7.5 ms').value, 7.5);
      expect(parseScore('7.5 ms').unit, 'ms');
      expect(parseScore('78%').value, 78);
      expect(parseScore('+1.2 dB').value, 1.2);
      expect(parseScore('5 digits').unit, 'digits');
      expect(parseScore('n/a').value, isNull);
    });

    test('fhirObservation is a valid R4 Observation', () {
      final obs = fhirObservation(
        const FhirObservationInput(
          testName: 'Random Gap Detection',
          value: 7.5,
          unit: 'ms',
          ear: 'Both',
          interpretation: 'Normal',
        ),
        effective: DateTime.utc(2026, 1, 1),
        patientName: 'Test Patient',
      );
      expect(obs['resourceType'], 'Observation');
      expect(obs['status'], 'final');
      final code = obs['code'] as Map<String, dynamic>;
      final coding = (code['coding'] as List).first as Map<String, dynamic>;
      expect(coding['system'], 'http://loinc.org');
      expect((obs['valueQuantity'] as Map)['value'], 7.5);
      expect((obs['valueQuantity'] as Map)['unit'], 'ms');
      expect(obs['component'], isNotNull); // ear-specific component
      expect((obs['subject'] as Map)['display'], 'Test Patient');
    });

    test('fhirBundle wraps one observation per input', () {
      final bundle = fhirBundle(const [
        FhirObservationInput(testName: 'A', value: 1, unit: 'dB'),
        FhirObservationInput(testName: 'B', value: 2, unit: '%'),
      ]);
      expect(bundle['resourceType'], 'Bundle');
      expect(bundle['type'], 'collection');
      expect((bundle['entry'] as List).length, 2);
    });
  });

  // ================================================= T3-5 word lists ====
  group('Word lists', () {
    test('CNC has 10 lists of 50 and NU-6 has 4 lists of 50', () {
      expect(kCncLists.length, 10);
      expect(kNu6Lists.length, 4);
      for (final l in kCncLists) {
        expect(l.words.length, 50, reason: l.name);
      }
      for (final l in kNu6Lists) {
        expect(l.words.length, 50, reason: l.name);
      }
    });
    test('pools are looked up by id', () {
      expect(wordPoolById('cnc_1')!.family, 'CNC');
      expect(wordPoolById('nu6_a')!.family, 'NU-6');
      expect(wordPoolById('nope'), isNull);
    });
  });

  // ============================================== T4-1 tinnitus pitch ====
  group('Tinnitus pitch match', () {
    test('binary search narrows the range and converges', () {
      final s = PitchMatchSession(maxTrials: 18);
      final startOct = s.rangeOctaves;
      s.submit(true); // chose higher
      expect(s.rangeOctaves, lessThan(startOct));
      expect(s.matchedHz, inInclusiveRange(125, 16000));
      final before = s.matchedHz;
      for (var i = 0; i < 6; i++) {
        s.submit(true);
      }
      expect(s.matchedHz, greaterThan(before));
    });
    test('completes by the trial budget', () {
      final s = PitchMatchSession(maxTrials: 18);
      var guard = 0;
      while (!s.isComplete && guard++ < 100) {
        s.submit(guard.isEven);
      }
      expect(s.isComplete, isTrue);
    });
  });

  // ============================================ T4-2 tinnitus loudness ====
  group('Tinnitus loudness match', () {
    test('louder lowers level; same records a match; completes', () {
      final s = LoudnessMatchSession(frequencyHz: 4000, startDb: 15, step: 6);
      s.submit(LoudnessResponse.louder);
      expect(s.levelDb, lessThan(15));
      s.submit(LoudnessResponse.same);
      s.submit(LoudnessResponse.same);
      s.submit(LoudnessResponse.same);
      expect(s.isComplete, isTrue);
      expect(s.matchedDb, greaterThanOrEqualTo(0));
    });
  });

  // ================================================= T4-3 tinnitus MML ====
  group('Tinnitus MML', () {
    test('ascends on still-hear, records on gone, completes at 3 samples', () {
      final s = MmlSession(startDb: 0, step: 4);
      s.submit(MaskingResponse.stillHear);
      expect(s.levelDb, 4);
      s.submit(MaskingResponse.gone);
      expect(s.samplesCollected, 1);
      s.submit(MaskingResponse.gone);
      s.submit(MaskingResponse.gone);
      expect(s.isComplete, isTrue);
      expect(s.mmlDb, inInclusiveRange(0, 40));
    });
  });

  // ============================================== T4-5 hyperacusis LDL ====
  group('Hyperacusis LDL', () {
    test('amplitude never exceeds the 0.7 safety cap', () {
      expect(relativeDbToAmplitude(0), closeTo(kRefAmp, 1e-9));
      expect(relativeDbToAmplitude(1000), lessThanOrEqualTo(kMaxSafeAmp));
      final s = LdlSession();
      var guard = 0;
      while (!s.isComplete && guard++ < 500) {
        expect(s.currentAmplitude, lessThanOrEqualTo(kMaxSafeAmp));
        s.louder();
      }
      expect(s.isComplete, isTrue);
      expect(s.results.length, s.frequencies.length);
    });
    test('too-loud records an LDL and advances', () {
      final s = LdlSession();
      s.tooLoud();
      expect(s.results.length, 1);
      expect(s.frequencyIndex, 1);
    });
  });

  // ============================================== T4-4 therapy sounds ====
  group('Therapy sounds', () {
    test('generators return the requested length and safe peak', () {
      for (final type in TherapySound.values) {
        final buf = buildTherapy(type, seconds: 0.2, amp: 0.4);
        expect(buf.length, (0.2 * kSampleRate).round());
        for (final v in buf) {
          expect(v.abs(), lessThanOrEqualTo(0.41));
        }
      }
    });
    test('notch filter preserves length and attenuates its frequency', () {
      final input = tone(seconds: 0.3, freqHz: 1000, amp: 0.5);
      final notched = notchFilter(input, 1000, sampleRate: kSampleRate);
      expect(notched.length, input.length);
      final inRms = rms(input.sublist(input.length ~/ 2));
      final outRms = rms(notched.sublist(notched.length ~/ 2));
      expect(outRms, lessThan(inRms * 0.5));
    });
  });

  // ============================================ T4-6 phonological games ====
  group('Phonological games', () {
    for (final game in PhonoGame.values) {
      test('${game.title} generates valid trials and scores', () {
        final gen = PhonologicalGenerator(game, seed: 1);
        final session = PhonologicalSession(game: game, maxTrials: 15);
        for (var i = 0; i < 15; i++) {
          final t = gen.next();
          expect(t.choices.length, greaterThanOrEqualTo(3));
          expect(t.correctIndex, inInclusiveRange(0, t.choices.length - 1));
          expect(t.choices[t.correctIndex], t.answer);
          session.submit(t, t.correctIndex, latencyMs: 10);
        }
        expect(session.isComplete, isTrue);
        expect(session.accuracy, 1.0);
      });
    }
  });

  // ============================================ T4-7 scene training DSP ====
  group('Scene training', () {
    test('filters and backgrounds preserve length', () {
      final n = (0.2 * kSampleRate).round();
      final babble = multiTalkerBabble(seconds: 0.2, seed: 1);
      expect(babble.length, n);
      expect(bandPass(babble, 300, 3200, kSampleRate).length, n);
      for (final scene in TrainingScene.values) {
        expect(sceneBackground(scene, seconds: 0.2, seed: 1).length, n);
      }
    });
    test('SNR staircase adapts on correct responses', () {
      final s = SceneTrainingSession(scene: TrainingScene.restaurant);
      final trial = FourAlternativeTrial(
          choices: const ['a', 'b', 'c', 'd'], targetIndex: 0);
      final start = s.currentSnrDb;
      s.submit(trial, 0, latencyMs: 5);
      s.submit(trial, 0, latencyMs: 5); // 2 correct → harder (lower SNR)
      expect(s.currentSnrDb, lessThan(start));
    });
  });

  // ============================================== T4-8 interhemispheric ====
  group('Interhemispheric', () {
    test('exact reproduction scores correct', () {
      final gen = InterhemisphericGenerator(seed: 2);
      final s = InterhemisphericSession(maxTrials: 4);
      final t = gen.next(s.currentLevel);
      expect(t.pattern.length, inInclusiveRange(2, 4));
      final ok = s.submit(t, List<Beat>.of(t.pattern), latencyMs: 5);
      expect(ok, isTrue);
      expect(s.elementAccuracy, 1.0);
      expect(rhythmSamples(t.pattern).length, greaterThan(0));
    });
    test('ear maps to the opposite hand', () {
      expect(Ear.left.oppositeHand, 'RIGHT');
      expect(Ear.right.oppositeHand, 'LEFT');
    });
  });

  // ============================================== T4-10 sentence closure ====
  group('Sentence closure', () {
    test('generates 4AFC trials with a masked frame', () {
      final gen = SentenceClosureGenerator(seed: 3);
      final s = SentenceClosureSession(maxTrials: 20);
      for (var i = 0; i < 20; i++) {
        final t = gen.next();
        expect(t.choices.length, 4);
        expect(t.choices[t.correctIndex], t.answer);
        expect(t.maskedFrame, contains('⟨ ? ⟩'));
        s.submit(t, t.correctIndex, latencyMs: 5);
      }
      expect(s.isComplete, isTrue);
      expect(s.accuracy, 1.0);
    });
  });

  // ================================================= T3-1 cloud sync ====
  group('Cloud sync', () {
    test('SessionRecord round-trips the synced flag', () {
      final r = SessionRecord(
        timestamp: DateTime.utc(2026, 1, 1),
        moduleId: 'm',
        groupId: 'g',
        title: 't',
        accuracy: 0.5,
        trials: 4,
        synced: true,
      );
      expect(SessionRecord.fromJson(r.toJson()).synced, isTrue);
      final legacy = SessionRecord.fromJson(<String, dynamic>{
        'ts': '2026-01-01T00:00:00.000Z',
        'mod': 'm',
        'grp': 'g',
        'title': 't',
        'acc': 0.5,
        'n': 4,
      });
      expect(legacy.synced, isFalse);
    });

    test('syncNow uploads pending sessions and marks them synced', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final history = SessionHistory();
      await history.add(SessionRecord(
        timestamp: DateTime.now(),
        moduleId: 'm',
        groupId: 'g',
        title: 't',
        accuracy: 1,
        trials: 5,
      ));
      final link = ClinicianLinkStore();
      await link.save('CLIN-1');
      final api =
          Api(client: MockClient((req) async => http.Response('{}', 200)));
      final svc = CloudSyncService(api: api, history: history, linkStore: link);
      final res = await svc.syncNow();
      expect(res.success, isTrue);
      expect(res.synced, 1);
      expect(res.pending, 0);
      expect((await history.load()).first.synced, isTrue);
      expect(await svc.lastSync(), isNotNull);
    });

    test('syncNow without a code prompts to link one', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final svc = CloudSyncService(
        api: Api(client: MockClient((req) async => http.Response('{}', 200))),
        history: SessionHistory(),
        linkStore: ClinicianLinkStore(),
      );
      final res = await svc.syncNow();
      expect(res.success, isFalse);
      expect(res.message, contains('clinician code'));
    });

    test('syncNow keeps sessions queued when offline', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final history = SessionHistory();
      await history.add(SessionRecord(
        timestamp: DateTime.now(),
        moduleId: 'm',
        groupId: 'g',
        title: 't',
        accuracy: 1,
        trials: 5,
      ));
      final link = ClinicianLinkStore();
      await link.save('CLIN-1');
      final api =
          Api(client: MockClient((req) async => throw Exception('net')));
      final svc = CloudSyncService(api: api, history: history, linkStore: link);
      final res = await svc.syncNow();
      expect(res.success, isFalse);
      expect(res.pending, 1);
      expect((await history.load()).first.synced, isFalse);
    });
  });

  // ============================================ widget smoke tests ====
  group('New pages render', () {
    testWidgets('PitchMatchPage plays and reveals two choices', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(MaterialApp(
        home: PitchMatchPage(audioPort: SilentAudioPort(), maxTrials: 4),
      ));
      await tester.pump();
      expect(
          find.text('Which tone is closer to your tinnitus?'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.text('Tone 1'), findsOneWidget);
      expect(find.text('Tone 2'), findsOneWidget);
    });

    testWidgets('LdlPage renders with the safety cap pill', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LdlPage(audioPort: SilentAudioPort()),
      ));
      await tester.pump();
      expect(find.text('Cap 0.7'), findsOneWidget);
    });

    testWidgets('PhonologicalPage shows the three games', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PhonologicalPage(audioPort: SilentAudioPort()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Rhyming'), findsOneWidget);
      expect(find.text('Sound Blending'), findsOneWidget);
      expect(find.text('Sound Deletion'), findsOneWidget);
    });

    testWidgets('SentenceClosurePage renders a masked prompt', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SentenceClosurePage(
            audioPort: SilentAudioPort(), maxTrials: 2, seed: 5),
      ));
      await tester.pump();
      expect(find.textContaining('completes the sentence'), findsOneWidget);
    });

    testWidgets('SoundTherapyPage renders sound choices', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(MaterialApp(
        home: SoundTherapyPage(audioPort: SilentAudioPort()),
      ));
      await tester.pump();
      expect(find.text('White noise'), findsOneWidget);
      expect(find.text('Pink noise'), findsOneWidget);
    });

    testWidgets('InstallAppButton renders on the VM', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InstallAppButton()),
      ));
      await tester.pump();
      expect(find.byKey(const Key('install-app-button')), findsOneWidget);
      expect(find.text('Install app'), findsOneWidget);
    });
  });
}
