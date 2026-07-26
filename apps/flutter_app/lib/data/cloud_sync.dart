import 'package:shared_preferences/shared_preferences.dart';

import '../features/remote/remote_sync_page.dart' show ClinicianLinkStore;
import 'api.dart';
import 'session_history.dart';

/// The outcome of a sync attempt.
class CloudSyncResult {
  const CloudSyncResult({
    required this.success,
    required this.attempted,
    required this.synced,
    required this.pending,
    required this.message,
    this.lastSync,
  });

  /// Whether the run ended in a good state (uploaded OK, or nothing to upload).
  final bool success;

  /// Whether a network upload was actually attempted this run.
  final bool attempted;

  /// Number of sessions marked synced during this run.
  final int synced;

  /// Sessions still pending upload after this run.
  final int pending;

  /// Human-readable status line for the UI.
  final String message;

  /// Timestamp of the last successful sync (if any).
  final DateTime? lastSync;
}

/// Uploads pending [SessionHistory] records to the linked clinician backend and
/// marks them synced. Offline / server failures are handled gracefully — the
/// records simply stay queued (unsynced) for a later attempt. No data ever
/// leaves the device unless a clinician code has been linked.
///
/// SAFETY: this only transmits locally-recorded session summaries the user
/// produced, and only to the configured research API. It never sends secrets.
class CloudSyncService {
  CloudSyncService({
    Api? api,
    SessionHistory? history,
    ClinicianLinkStore? linkStore,
    this.lastSyncKey = 'hearbloom.last_sync.v1',
    DateTime Function()? clock,
  })  : _api = api ?? Api(),
        _history = history ?? SessionHistory(),
        _linkStore = linkStore ?? ClinicianLinkStore(),
        _clock = clock ?? DateTime.now;

  final Api _api;
  final SessionHistory _history;
  final ClinicianLinkStore _linkStore;
  final String lastSyncKey;
  final DateTime Function() _clock;

  /// Count of sessions not yet uploaded.
  Future<int> pendingCount() async {
    final records = await _history.load();
    return records.where((r) => !r.synced).length;
  }

  /// The last successful-sync timestamp, or null if never.
  Future<DateTime?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(lastSyncKey);
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> _setLastSync(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSyncKey, when.toIso8601String());
  }

  /// The linked clinician code (empty when unlinked).
  Future<String> clinicianCode() => _linkStore.load();

  /// Attempts to upload all pending sessions. See [CloudSyncResult].
  Future<CloudSyncResult> syncNow() async {
    final code = (await _linkStore.load()).trim();
    final records = await _history.load();
    final pending = records.where((r) => !r.synced).toList();
    final last = await lastSync();

    if (code.isEmpty) {
      return CloudSyncResult(
        success: false,
        attempted: false,
        synced: 0,
        pending: pending.length,
        message: 'Enter a clinician code to enable sync.',
        lastSync: last,
      );
    }
    if (pending.isEmpty) {
      return CloudSyncResult(
        success: true,
        attempted: false,
        synced: 0,
        pending: 0,
        message: 'All sessions are already synced.',
        lastSync: last,
      );
    }

    try {
      final ok = await _api.postSessions(
        code,
        pending.map((r) => r.toJson()).toList(),
      );
      if (!ok) {
        return CloudSyncResult(
          success: false,
          attempted: true,
          synced: 0,
          pending: pending.length,
          message: 'Server refused the upload — sessions kept for retry.',
          lastSync: last,
        );
      }
      // Mark every previously-pending record synced and persist.
      final updated = <SessionRecord>[
        for (final r in records) r.synced ? r : r.copyWith(synced: true),
      ];
      await _history.saveAll(updated);
      final now = _clock();
      await _setLastSync(now);
      return CloudSyncResult(
        success: true,
        attempted: true,
        synced: pending.length,
        pending: 0,
        message: 'Synced ${pending.length} '
            'session${pending.length == 1 ? '' : 's'} to $code.',
        lastSync: now,
      );
    } catch (_) {
      // Offline or transport error → keep everything queued for later.
      return CloudSyncResult(
        success: false,
        attempted: true,
        synced: 0,
        pending: pending.length,
        message: 'Offline — ${pending.length} '
            'session${pending.length == 1 ? '' : 's'} queued for later.',
        lastSync: last,
      );
    }
  }
}
