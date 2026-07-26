import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Privacy-respecting usage statistics (J10): OPT-IN, on-device only,
/// aggregate counters of completed exercises per test id plus app opens.
/// Nothing is transmitted anywhere; the user can view, export (as part of
/// "Export my data") and clear them at any time. Disabled by default.
class UsageStats {
  UsageStats({this.prefix = 'hearbloom.usage.v1'});

  final String prefix;

  String get _enabledKey => '$prefix.enabled';
  String get _countsKey => '$prefix.counts';

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Increments the counter for [key] (e.g. a groupId or `app_open`).
  /// A silent no-op unless the user opted in.
  Future<void> record(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_enabledKey) ?? false)) return;
      final counts = await load();
      counts[key] = (counts[key] ?? 0) + 1;
      await prefs.setString(_countsKey, jsonEncode(counts));
    } catch (_) {
      // Analytics must never break the app.
    }
  }

  Future<Map<String, int>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_countsKey);
      if (raw == null || raw.isEmpty) return <String, int>{};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_countsKey);
  }
}
