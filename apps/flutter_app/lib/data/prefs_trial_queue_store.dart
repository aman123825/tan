import 'package:shared_preferences/shared_preferences.dart';

import '../core/trial_queue.dart';

/// [TrialQueueStore] backed by SharedPreferences for on-device durability.
///
/// The queue logic lives in the pure-Dart [TrialQueue]; this adapter only owns
/// the key/value IO so it stays trivially correct.
class PrefsTrialQueueStore implements TrialQueueStore {
  PrefsTrialQueueStore({this.key = 'hearbloom.trial_queue.v1'});

  final String key;

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, data);
  }
}
