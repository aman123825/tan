import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Supplies the 32-byte key used to encrypt local records.
///
/// This dev-grade store generates a cryptographically-random key once
/// (`Random.secure`) and persists it in SharedPreferences. It protects records
/// from casual inspection but is NOT hardware-backed — production builds should
/// swap in platform secure storage (e.g. flutter_secure_storage / Keychain /
/// Keystore) behind this same interface.
class LocalKeyStore {
  LocalKeyStore({this.prefsKey = 'hearbloom.queue_key.v1'});

  final String prefsKey;

  Future<List<int>> loadOrCreateKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(prefsKey);
    if (existing != null) {
      final bytes = base64.decode(existing);
      if (bytes.length == 32) return bytes;
    }
    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    await prefs.setString(prefsKey, base64.encode(key));
    return key;
  }
}
