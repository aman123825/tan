// Headless verification harness for trial persistence (payload + offline queue).
//
//   dart run tool/verify/persistence_harness.dart
import 'dart:convert';
import 'dart:io';

import '../../lib/core/protocol_engine.dart';
import '../../lib/core/trial_event.dart';
import '../../lib/core/trial_queue.dart';
import '../../lib/core/versions.dart';

int _checks = 0;
int _failures = 0;

void check(String name, bool condition) {
  _checks++;
  if (condition) {
    stdout.writeln('  ok   $name');
  } else {
    _failures++;
    stdout.writeln('  FAIL $name');
  }
}

PendingTrial _mk(String id, {int snr = 8, bool correct = true}) {
  final record = TrialRecord(
    target: 'bell',
    response: correct ? 'bell' : 'ball',
    correct: correct,
    latencyMs: 640,
    replays: 0,
    parameters: <String, Object?>{'snr_db': snr},
  );
  final payload = buildTrialPayload(
    sessionId: 'sess-1',
    moduleId: 'noise',
    groupId: 'sentence_noise',
    mode: 'training',
    record: record,
  );
  return PendingTrial(id: id, payload: payload);
}

Future<void> main() async {
  // 1) Payload shape and version lineage.
  final p = _mk('t1');
  check(
    'payload has exactly the backend key set',
    p.payload.keys.toSet().length == kTrialPayloadKeys.length &&
        kTrialPayloadKeys.every(p.payload.containsKey),
  );
  check('app_version stamped', p.payload['app_version'] == kAppVersion);
  check(
    'protocol_version stamped',
    p.payload['protocol_version'] == kProtocolVersion,
  );
  check(
    'stimulus_version stamped',
    p.payload['stimulus_version'] == kStimulusVersion,
  );
  check(
    'all version fields non-empty',
    (p.payload['app_version'] as String).isNotEmpty &&
        (p.payload['protocol_version'] as String).isNotEmpty &&
        (p.payload['stimulus_version'] as String).isNotEmpty,
  );
  check(
    'parameters carry snr_db',
    (p.payload['parameters'] as Map)['snr_db'] == 8,
  );

  // 2) Enqueue + FIFO + dedupe + persistence.
  final store = InMemoryTrialQueueStore();
  final q = TrialQueue(store);
  await q.enqueue(_mk('t1'));
  await q.enqueue(_mk('t2'));
  await q.enqueue(_mk('t1')); // duplicate id -> ignored
  check('dedupe by id', q.length == 2);
  check(
    'FIFO order preserved',
    q.pending.first.id == 't1' && q.pending.last.id == 't2',
  );

  // Reload from the same store simulates an app restart.
  final q2 = TrialQueue(store);
  await q2.load();
  check('queue survives reload', q2.length == 2);
  check(
    'reloaded order preserved',
    q2.pending.first.id == 't1' && q2.pending.last.id == 't2',
  );

  // 3) Offline flush: sender fails -> nothing acked, queue intact.
  final offline = await q2.flush((_) async => false);
  check('offline flush sends nothing', offline.sent == 0);
  check('offline flush keeps queue', q2.length == 2);

  // 4) Partial flush: fail after the first -> ordering preserved.
  await q2.enqueue(_mk('t3'));
  var calls = 0;
  final partial = await q2.flush((_) async {
    calls++;
    return calls <= 1; // only the first succeeds
  });
  check('partial flush sends only up to first failure', partial.sent == 1);
  check(
    'partial flush removes the sent (oldest) trial',
    q2.length == 2 && q2.pending.first.id == 't2',
  );

  // 5) Online flush: all succeed -> queue drains and store is emptied.
  final online = await q2.flush((_) async => true);
  check('online flush drains queue', online.sent == 2 && q2.isEmpty);
  final q3 = TrialQueue(store);
  await q3.load();
  check('drained state persisted across reload', q3.isEmpty);

  // 6) enqueueSessionTrials: full session -> queue, idempotent by id.
  final records = <TrialRecord>[
    for (var i = 0; i < 5; i++)
      TrialRecord(
        target: 'bell',
        response: i.isEven ? 'bell' : 'ball',
        correct: i.isEven,
        latencyMs: 500 + i,
        parameters: <String, Object?>{'snr_db': 12 - i},
      ),
  ];
  final sq = TrialQueue(InMemoryTrialQueueStore());
  await enqueueSessionTrials(
    sq,
    sessionId: 'sessX',
    moduleId: 'noise',
    groupId: 'sentence_noise',
    mode: 'training',
    records: records,
  );
  check('session enqueued all records', sq.length == records.length);
  check('deterministic ids', sq.pending.first.id == 'sessX#0');
  check(
    'enqueued payloads carry version lineage',
    sq.pending.every((p) => p.payload['app_version'] == kAppVersion),
  );
  await enqueueSessionTrials(
    sq,
    sessionId: 'sessX',
    moduleId: 'noise',
    groupId: 'sentence_noise',
    mode: 'training',
    records: records,
  );
  check('re-enqueue is idempotent', sq.length == records.length);

  // 7) EncryptingTrialQueueStore hides plaintext at rest and round-trips.
  final backing = InMemoryTrialQueueStore();
  final encStore = EncryptingTrialQueueStore(backing, _Base64Cipher());
  final eq = TrialQueue(encStore);
  await eq.enqueue(PendingTrial(id: 'e1', payload: _mk('e1').payload));
  final rawAtRest = await backing.read();
  check(
      'something is stored at rest', rawAtRest != null && rawAtRest.isNotEmpty);
  check('plaintext session id is NOT present at rest',
      rawAtRest != null && !rawAtRest.contains('sess-1'));
  check('at-rest bytes differ from plaintext json',
      rawAtRest != null && !rawAtRest.contains('"session_id"'));
  final eq2 = TrialQueue(encStore);
  await eq2.load();
  check('encrypted queue decrypts on reload', eq2.length == 1);
  check('decrypted payload is intact',
      eq2.pending.first.payload['session_id'] == 'sess-1');

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks persistence checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks persistence checks');
    exit(1);
  }
}

/// A reversible, non-identity cipher for verifying [EncryptingTrialQueueStore]
/// wraps correctly (real AES-GCM is exercised in `flutter test`).
class _Base64Cipher implements QueueCipher {
  @override
  Future<String> encrypt(String plaintext) async =>
      base64.encode(utf8.encode(plaintext));

  @override
  Future<String> decrypt(String ciphertext) async =>
      utf8.decode(base64.decode(ciphertext));
}
