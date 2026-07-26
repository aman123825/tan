/// Trial event payload construction (pure Dart).
///
/// Produces the exact JSON shape accepted by the backend `POST /trials`
/// (`TrialIn` in `services/api/main.py`) and enqueued for offline sync. The key
/// set is asserted by `tool/verify/persistence_harness.dart` and mirrored by
/// `tests/test_persistence.py`, tying the client payload to the server
/// contract.
library;

import 'protocol_engine.dart';
import 'trial_queue.dart';
import 'versions.dart';

/// Canonical ordered key set of a trial payload (used by verification).
const List<String> kTrialPayloadKeys = <String>[
  'session_id',
  'module_id',
  'group_id',
  'mode',
  'target',
  'response',
  'correct',
  'latency_ms',
  'replay_count',
  'parameters',
  'app_version',
  'protocol_version',
  'stimulus_version',
];

/// Builds a trial event payload from a completed [record], stamping the
/// app/protocol/stimulus version lineage.
Map<String, dynamic> buildTrialPayload({
  required String sessionId,
  required String moduleId,
  required String groupId,
  required String mode,
  required TrialRecord record,
  String appVersion = kAppVersion,
  String protocolVersion = kProtocolVersion,
  String stimulusVersion = kStimulusVersion,
}) {
  return <String, dynamic>{
    'session_id': sessionId,
    'module_id': moduleId,
    'group_id': groupId,
    'mode': mode,
    'target': record.target,
    'response': record.response,
    'correct': record.correct,
    'latency_ms': record.latencyMs,
    'replay_count': record.replays,
    'parameters': record.parameters,
    'app_version': appVersion,
    'protocol_version': protocolVersion,
    'stimulus_version': stimulusVersion,
  };
}

/// Enqueues every [record] of a completed session as a pending trial.
///
/// Ids are deterministic (`"<sessionId>#<index>"`) so re-enqueuing the same
/// session is idempotent (the queue dedupes by id) — safe to call after a
/// crash or retry without duplicating trials.
Future<void> enqueueSessionTrials(
  TrialQueue queue, {
  required String sessionId,
  required String moduleId,
  required String groupId,
  required String mode,
  required List<TrialRecord> records,
  String appVersion = kAppVersion,
  String protocolVersion = kProtocolVersion,
  String stimulusVersion = kStimulusVersion,
}) async {
  for (var i = 0; i < records.length; i++) {
    final payload = buildTrialPayload(
      sessionId: sessionId,
      moduleId: moduleId,
      groupId: groupId,
      mode: mode,
      record: records[i],
      appVersion: appVersion,
      protocolVersion: protocolVersion,
      stimulusVersion: stimulusVersion,
    );
    await queue.enqueue(PendingTrial(id: '$sessionId#$i', payload: payload));
  }
}
