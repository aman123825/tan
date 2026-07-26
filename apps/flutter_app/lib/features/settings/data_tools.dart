import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/consent_store.dart';

/// Builds the complete "export my data" JSON: every locally-stored
/// HearBloom value (session history, tinnitus results, gamification,
/// favourites, settings, consent record) keyed as stored, plus metadata.
/// Complete by construction — the app keeps ALL its data in
/// SharedPreferences, so dumping the store cannot miss anything (J8 data
/// portability).
Future<String> buildLocalDataExport() async {
  final prefs = await SharedPreferences.getInstance();
  final data = <String, Object?>{};
  for (final key in prefs.getKeys().toList()..sort()) {
    final value = prefs.get(key);
    // Stored JSON strings are inlined as structures for a readable export.
    if (value is String && value.isNotEmpty &&
        (value.startsWith('{') || value.startsWith('['))) {
      try {
        data[key] = jsonDecode(value);
        continue;
      } catch (_) {
        // Not JSON after all — fall through to the raw value.
      }
    }
    data[key] = value;
  }
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'research_only': true,
    'exported_at': DateTime.now().toIso8601String(),
    'consent_version': kConsentVersion,
    'note': 'Complete dump of HearBloom\'s on-device storage. Server-side '
        'data (if a study server was linked) is exported via the API\'s '
        '/profiles/{id}/export.json endpoint.',
    'data': data,
  });
}

/// Right-to-erasure (J8): wipes EVERY locally-stored HearBloom value —
/// session history, queue, tinnitus results, gamification, favourites,
/// reminders, settings and the consent record itself (the consent screen
/// shows again on next launch). Returns the number of keys removed.
Future<int> deleteAllLocalData() async {
  final prefs = await SharedPreferences.getInstance();
  final count = prefs.getKeys().length;
  await prefs.clear();
  consentState.value = null;
  return count;
}
