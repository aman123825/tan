/// Shared tinnitus utilities: the persisted result store (the safe
/// relative-dB → amplitude mapping now lives in the Flutter-free
/// `levels.dart` and is re-exported here for existing importers).
library;

import 'package:shared_preferences/shared_preferences.dart';

export 'levels.dart';

/// A stored tinnitus profile: matched pitch (Hz), matched loudness (dB SL) and
/// minimum masking level (dB). Any field may be null if not yet measured.
class TinnitusProfile {
  const TinnitusProfile({this.pitchHz, this.loudnessDb, this.mmlDb});

  final double? pitchHz;
  final double? loudnessDb;
  final double? mmlDb;

  bool get hasPitch => pitchHz != null;

  TinnitusProfile copyWith({double? pitchHz, double? loudnessDb, double? mmlDb}) =>
      TinnitusProfile(
        pitchHz: pitchHz ?? this.pitchHz,
        loudnessDb: loudnessDb ?? this.loudnessDb,
        mmlDb: mmlDb ?? this.mmlDb,
      );
}

/// Persists the tinnitus profile on-device (SharedPreferences). The stored
/// matched pitch is reused by the sound-therapy notch filter.
class TinnitusStore {
  TinnitusStore({this.prefix = 'hearbloom.tinnitus.v1'});

  final String prefix;

  Future<TinnitusProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TinnitusProfile(
      pitchHz: prefs.getDouble('$prefix.pitch_hz'),
      loudnessDb: prefs.getDouble('$prefix.loudness_db'),
      mmlDb: prefs.getDouble('$prefix.mml_db'),
    );
  }

  Future<void> savePitch(double hz) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$prefix.pitch_hz', hz);
  }

  Future<void> saveLoudness(double db) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$prefix.loudness_db', db);
  }

  Future<void> saveMml(double db) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$prefix.mml_db', db);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$prefix.pitch_hz');
    await prefs.remove('$prefix.loudness_db');
    await prefs.remove('$prefix.mml_db');
  }
}
