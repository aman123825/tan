/// Offline-first trial queue (pure Dart).
///
/// Trials are captured locally and synced to the backend when connectivity
/// allows. The queue is storage-agnostic: it persists through an injected
/// [TrialQueueStore] (SharedPreferences in the app, in-memory in tests). All
/// ordering/dedupe/flush logic lives here and is verified headlessly by
/// `tool/verify/persistence_harness.dart`.
library;

import 'dart:convert';

/// One queued trial: a stable client-generated [id] (for dedupe/idempotency)
/// plus the API [payload].
class PendingTrial {
  PendingTrial({required this.id, required this.payload});

  final String id;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'payload': payload,
      };

  factory PendingTrial.fromJson(Map<String, dynamic> json) => PendingTrial(
        id: json['id'] as String,
        payload: (json['payload'] as Map).cast<String, dynamic>(),
      );
}

/// Persistence backend for the queue. Reads/writes a single serialized string.
abstract class TrialQueueStore {
  Future<String?> read();
  Future<void> write(String data);
}

/// In-memory store for tests/harnesses.
class InMemoryTrialQueueStore implements TrialQueueStore {
  String? _data;

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async => _data = data;
}

/// Reversible codec used to encrypt the queue's serialized payload at rest.
abstract class QueueCipher {
  Future<String> encrypt(String plaintext);
  Future<String> decrypt(String ciphertext);
}

/// Identity cipher (no encryption). For non-sensitive or development use only.
class PlaintextQueueCipher implements QueueCipher {
  const PlaintextQueueCipher();

  @override
  Future<String> encrypt(String plaintext) async => plaintext;

  @override
  Future<String> decrypt(String ciphertext) async => ciphertext;
}

/// Wraps a [TrialQueueStore], encrypting on write and decrypting on read so
/// local records are encrypted at rest (docs/SAFETY.md: "encrypt local
/// records"). The cipher is injected — the real one (AES-GCM) lives in
/// `data/aes_gcm_cipher.dart`; tests use a simple reversible cipher.
class EncryptingTrialQueueStore implements TrialQueueStore {
  EncryptingTrialQueueStore(this._inner, this._cipher);

  final TrialQueueStore _inner;
  final QueueCipher _cipher;

  @override
  Future<String?> read() async {
    final raw = await _inner.read();
    if (raw == null || raw.isEmpty) return raw;
    return _cipher.decrypt(raw);
  }

  @override
  Future<void> write(String data) async {
    await _inner.write(await _cipher.encrypt(data));
  }
}

/// Result of a [TrialQueue.flush].
class FlushResult {
  const FlushResult({required this.sent, required this.remaining});

  final int sent;
  final int remaining;
}

/// FIFO queue of pending trials with durable persistence.
class TrialQueue {
  TrialQueue(this._store);

  final TrialQueueStore _store;
  final List<PendingTrial> _pending = <PendingTrial>[];

  List<PendingTrial> get pending => List<PendingTrial>.unmodifiable(_pending);
  int get length => _pending.length;
  bool get isEmpty => _pending.isEmpty;

  /// Rehydrates the queue from the store. Safe to call on startup.
  Future<void> load() async {
    final raw = await _store.read();
    _pending.clear();
    if (raw == null || raw.isEmpty) return;
    final decoded = (jsonDecode(raw) as List<dynamic>).map(
      (dynamic e) => PendingTrial.fromJson((e as Map).cast<String, dynamic>()),
    );
    _pending.addAll(decoded);
  }

  /// Adds a trial (idempotent by [PendingTrial.id]) and persists.
  Future<void> enqueue(PendingTrial trial) async {
    if (_pending.any((PendingTrial p) => p.id == trial.id)) return;
    _pending.add(trial);
    await _persist();
  }

  /// The oldest [n] pending trials, without removing them.
  List<PendingTrial> takeBatch(int n) =>
      _pending.take(n).toList(growable: false);

  /// Removes acknowledged (successfully sent) trials by id and persists.
  Future<void> ackSent(Iterable<String> ids) async {
    final set = ids.toSet();
    _pending.removeWhere((PendingTrial p) => set.contains(p.id));
    await _persist();
  }

  /// Sends pending trials in FIFO order via [send]. Stops at the first failure
  /// (treated as offline) so ordering and at-least-once delivery are preserved.
  /// Each success is acknowledged and persisted individually, so a crash never
  /// loses or double-commits more than the in-flight trial.
  Future<FlushResult> flush(
    Future<bool> Function(Map<String, dynamic> payload) send,
  ) async {
    var sent = 0;
    for (final PendingTrial trial in List<PendingTrial>.of(_pending)) {
      final ok = await send(trial.payload);
      if (!ok) break;
      await ackSent(<String>[trial.id]);
      sent++;
    }
    return FlushResult(sent: sent, remaining: _pending.length);
  }

  Future<void> _persist() async {
    await _store.write(
      jsonEncode(_pending.map((PendingTrial p) => p.toJson()).toList()),
    );
  }
}
