import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// The consent-text version the app currently shows. Keep in sync with
/// `docs/CONSENT.md` and `CONSENT_VERSION` in `services/api/main.py`.
const String kConsentVersion = '2026-07-research-v1';

/// The participant's research-consent decision.
///
///  * null — not asked yet (the consent screen should be shown).
///  * true — agreed: results may be stored locally and synced when linked.
///  * false — declined: the app stays fully usable but NOTHING is persisted
///    (no session history, no queue, no gamification).
final ValueNotifier<bool?> consentState = ValueNotifier<bool?>(null);

/// SharedPreferences-backed record of the consent decision (J8).
class ConsentStore {
  ConsentStore({this.prefix = 'hearbloom.consent.v1'});

  final String prefix;

  String get _decisionKey => '$prefix.consented';
  String get _versionKey => '$prefix.version';
  String get _atKey => '$prefix.at';

  /// Loads the stored decision into [consentState]; null when never asked or
  /// when the consent text changed since (re-ask on version bump).
  Future<bool?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final decided = prefs.getBool(_decisionKey);
      final version = prefs.getString(_versionKey);
      final value =
          (decided != null && version == kConsentVersion) ? decided : null;
      consentState.value = value;
      return value;
    } catch (_) {
      return consentState.value;
    }
  }

  Future<void> record({required bool consented}) async {
    consentState.value = consented;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_decisionKey, consented);
      await prefs.setString(_versionKey, kConsentVersion);
      await prefs.setString(_atKey, DateTime.now().toIso8601String());
    } catch (_) {
      // In-memory state still governs this session.
    }
  }

  Future<DateTime?> decidedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_atKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }
}

/// Whether persisting results is currently allowed. Unasked (null) counts as
/// allowed so pre-existing installs keep working until the screen is shown;
/// an explicit decline always wins.
bool get persistenceAllowed => consentState.value != false;
