import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearbloom/core/protocol_engine.dart';
import 'package:hearbloom/core/safety.dart';
import 'package:hearbloom/core/speech_in_noise.dart';
import 'package:hearbloom/core/trial_event.dart';
import 'package:hearbloom/core/trial_queue.dart';
import 'package:hearbloom/core/versions.dart';
import 'package:hearbloom/data/aes_gcm_cipher.dart';
import 'package:hearbloom/models/catalog.dart';
import 'package:hearbloom/models/recommendation.dart';
import 'package:hearbloom/models/results.dart';

void main() {
  group('Catalog models', () {
    final catalog = Catalog.fromJson(const {
      'schema_version': '1.0.0',
      'product': 'HearBloom',
      'status': 'research_specification',
      'modules': [
        {
          'id': 'noise',
          'name': 'Adaptive Speech in Noise',
          'audience': ['adult'],
          'groups': [
            {
              'id': 'sentence_noise',
              'name': 'Everyday Sentence Recognition in Noise',
              'protocol': 'adaptive_snr_4afc',
              'modes': [
                'introduction',
                'preview',
                'training',
                'test',
                'results',
              ],
              'validation_status': 'unvalidated',
              'parameters': {'step_db': 2},
            },
          ],
        },
      ],
    });

    test('parses structure and helpers', () {
      expect(catalog.isResearchSpecification, isTrue);
      expect(catalog.groupCount, 1);
      expect(catalog.moduleById('noise')!.name, 'Adaptive Speech in Noise');
      expect(catalog.moduleById('missing'), isNull);
    });

    test('group is unvalidated with canonical workflow', () {
      final g = catalog.moduleById('noise')!.groups.single;
      expect(g.isValidated, isFalse);
      expect(g.hasCanonicalWorkflow, isTrue);
      expect(g.protocol, 'adaptive_snr_4afc');
    });
  });

  group('Deterministic engine (golden vector)', () {
    const seq = <bool>[
      true, true, true, true, true, true, false, true, true, false, //
      false, true, true, false, true, true, false, false, true, true, //
      false, true, true, false,
    ];
    const traj = <double>[
      12, 10, 10, 8, 8, 6, 8, 8, 6, 8, //
      10, 10, 8, 10, 10, 8, 10, 12, 12, 10, //
      12, 12, 10, 12,
    ];

    test('snr staircase matches the Python golden trajectory', () {
      final track = AdaptiveTrack.snr();
      final out = [for (final c in seq) track.submit(c)];
      expect(out, traj);
      expect(track.reversals, [6, 8, 6, 10, 8, 10, 8, 12, 10, 12, 10]);
      expect(track.complete, isTrue);
      expect(track.threshold, closeTo(62 / 6, 1e-9));
    });

    test('session scores and never exposes volume', () {
      final session = SpeechInNoiseSession(
        moduleId: 'noise',
        groupId: 'sentence_noise',
        maxTrials: 1000,
      );
      for (final correct in seq) {
        session.submit(
          FourAlternativeTrial(
              choices: const ['a', 'b', 'c', 'd'], targetIndex: 0),
          correct ? 0 : 1,
          latencyMs: 500,
        );
      }
      expect(session.thresholdSnrDb, closeTo(62 / 6, 1e-9));
      expect(session.records.first.toJson().containsKey('parameters'), isTrue);
      expect(
        session.records.first.toJson().keys.any((k) => k.contains('volume')),
        isFalse,
      );
    });
  });

  group('Comfortable-level safety', () {
    test('auto volume is always off and level is a no-op on responses', () {
      final c = ComfortableLevelController(initialLevel: 0.3);
      expect(c.autoVolume, isFalse);
      expect(c.setLevel(0.5), 0.5);
      final before = c.level;
      for (var i = 0; i < 50; i++) {
        c.registerResponse(correct: false);
      }
      expect(c.level, before);
    });

    test('locking blocks changes; automatic source always denied', () {
      final c = ComfortableLevelController(initialLevel: 0.4);
      c.lock();
      expect(() => c.setLevel(0.9), throwsA(isA<VolumeChangeDenied>()));
      c.unlock();
      expect(
        () => c.setLevel(0.9, source: VolumeChangeSource.automatic),
        throwsA(isA<VolumeChangeDenied>()),
      );
    });
  });

  group('Offline trial queue', () {
    test('dedupe, offline-safe flush, then drain', () async {
      final q = TrialQueue(InMemoryTrialQueueStore());
      await q.enqueue(PendingTrial(id: 'a', payload: const {'x': 1}));
      await q.enqueue(PendingTrial(id: 'a', payload: const {'x': 1}));
      expect(q.length, 1);
      final offline = await q.flush((_) async => false);
      expect(offline.sent, 0);
      expect(q.length, 1);
      final online = await q.flush((_) async => true);
      expect(online.sent, 1);
      expect(q.isEmpty, isTrue);
    });

    test('buildTrialPayload stamps version lineage and matches backend keys',
        () {
      final rec = TrialRecord(
        target: 'bell',
        response: 'bell',
        correct: true,
        latencyMs: 500,
        parameters: const {'snr_db': 8},
      );
      final p = buildTrialPayload(
        sessionId: 's',
        moduleId: 'noise',
        groupId: 'sentence_noise',
        mode: 'training',
        record: rec,
      );
      expect(p['app_version'], kAppVersion);
      expect(p.keys.toSet(), kTrialPayloadKeys.toSet());
    });
  });

  group('Results & recommendation models', () {
    test('results parse with reliability and no pooling', () {
      final r = ResultsSummary.fromJson(const {
        'total_trials': 20,
        'accuracy': 1.0,
        'pooling_policy': 'not_pooled_across_condition_or_device',
        'separated': [
          {
            'condition': 'binaural',
            'output_device': 'wired_headphones',
            'module_id': 'noise',
            'group_id': 'sentence_noise',
            'mode': 'test',
            'n': 20,
            'accuracy': 1.0,
            'mean_latency_ms': 600.0,
            'reliability': {
              'reliable': true,
              'replay_rate': 0.0,
              'fast_rate': 0.0
            },
          },
        ],
      });
      expect(r.notPooled, isTrue);
      expect(r.separated.single.reliability.reliable, isTrue);
    });

    test('recommendation is explainable and advisory', () {
      final rec = Recommendation.fromJson(const {
        'group_id': 'sentence_noise',
        'module_id': 'noise',
        'reason': 'Start with an easy speech-in-noise baseline.',
        'confidence': 0.5,
        'parameters': {'snr_db': 12, 'mode': 'training'},
      });
      expect(rec.hasReason, isTrue);
      expect(rec.confidencePercent, 50);
      expect(rec.raisesVolume, isFalse);
    });
  });

  group('Encrypted local records (AES-GCM)', () {
    final key = List<int>.generate(32, (i) => (i * 7) % 256);

    test('round-trips and hides plaintext', () async {
      final cipher = AesGcmQueueCipher(key);
      const plain = '{"session_id":"secret-123"}';
      final enc = await cipher.encrypt(plain);
      expect(enc.contains('secret-123'), isFalse);
      expect(await cipher.decrypt(enc), plain);
    });

    test('tampering is detected (authenticated encryption)', () async {
      final cipher = AesGcmQueueCipher(key);
      final env =
          jsonDecode(await cipher.encrypt('hello')) as Map<String, dynamic>;
      final c = base64.decode(env['c'] as String);
      c[0] = c[0] ^ 0xFF; // flip a ciphertext byte
      env['c'] = base64.encode(c);
      await expectLater(cipher.decrypt(jsonEncode(env)), throwsA(anything));
    });

    test('encrypting store hides plaintext at rest and round-trips', () async {
      final backing = InMemoryTrialQueueStore();
      final store = EncryptingTrialQueueStore(backing, AesGcmQueueCipher(key));
      final q = TrialQueue(store);
      await q.enqueue(
        PendingTrial(id: 'x', payload: const {'session_id': 'secret-123'}),
      );
      final raw = await backing.read();
      expect(raw, isNotNull);
      expect(raw!.contains('secret-123'), isFalse);
      final q2 = TrialQueue(store);
      await q2.load();
      expect(q2.pending.first.payload['session_id'], 'secret-123');
    });
  });
}
