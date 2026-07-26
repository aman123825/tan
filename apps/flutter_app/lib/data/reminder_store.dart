import 'package:shared_preferences/shared_preferences.dart';

/// Daily practice reminder preference (in-app only — an honest banner on the
/// home screen once the chosen hour has passed with no session that day;
/// there is no OS push-notification plumbing).
class ReminderSettings {
  const ReminderSettings({this.enabled = false, this.hour = 17});

  final bool enabled;

  /// Local hour of day (0–23) after which the reminder banner may appear.
  final int hour;
}

/// SharedPreferences-backed persistence for [ReminderSettings].
class ReminderStore {
  ReminderStore({this.prefix = 'hearbloom.reminder.v1'});

  final String prefix;

  String get _enabledKey => '$prefix.enabled';
  String get _hourKey => '$prefix.hour';
  String get _dismissedKey => '$prefix.dismissed_on';

  Future<ReminderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      hour: (prefs.getInt(_hourKey) ?? 17).clamp(0, 23),
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour.clamp(0, 23));
  }

  /// Snoozes the banner for the rest of [day] (stored as yyyy-mm-dd).
  Future<void> dismissFor(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, _dayKey(day));
  }

  Future<bool> isDismissedFor(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dismissedKey) == _dayKey(day);
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
