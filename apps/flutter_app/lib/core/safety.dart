/// Safety invariants for comfortable-level (master volume) handling.
///
/// Pure Dart (no Flutter imports) so the invariants can be exercised in a
/// headless harness and unit tests. This encodes the non-negotiable rules from
/// `docs/SAFETY.md` and `KIRO_HANDOFF.md`:
///
///  * `auto_volume` is ALWAYS false — there is no code path that turns it on.
///  * Wrong answers NEVER increase master volume.
///  * Master volume cannot change while a test is in progress (it is *locked*).
///  * Home audio never reports dB HL. [ComfortableLevelController.level] is a
///    unitless comfortable setting in `[minLevel, maxLevel]`, NOT a calibrated
///    hearing level.
///
/// ANSD precaution: speech understanding may not improve with louder
/// presentation. Difficulty must be adapted via SNR / rate / temporal
/// complexity / response choices elsewhere — never by raising master volume.
library;

/// Thrown when a volume change is requested that safety rules forbid.
class VolumeChangeDenied implements Exception {
  VolumeChangeDenied(this.reason);
  final String reason;
  @override
  String toString() => 'VolumeChangeDenied: $reason';
}

/// The provenance of a level-change request. The controller only ever honours
/// [userCalibration]; every other source is rejected. This makes it impossible
/// to wire a performance-driven ("got it wrong, turn it up") increase.
enum VolumeChangeSource {
  /// Explicit, user-driven calibration before a test is locked.
  userCalibration,

  /// Any automatic/derived source. Always denied.
  automatic,
}

/// Owns the single master "comfortable level" and enforces the safety rules
/// around changing it.
class ComfortableLevelController {
  ComfortableLevelController({
    this.minLevel = 0.0,
    this.maxLevel = 1.0,
    double initialLevel = 0.3,
  })  : assert(minLevel < maxLevel),
        _level = initialLevel.clamp(minLevel, maxLevel).toDouble();

  final double minLevel;
  final double maxLevel;

  double _level;
  bool _locked = false;

  /// Auto-volume is a constant: always false. There is deliberately no setter.
  bool get autoVolume => false;

  /// Current unitless comfortable level (NOT dB HL).
  double get level => _level;

  /// Whether the level is locked for an in-progress test.
  bool get isLocked => _locked;

  /// The ONLY way to change the level. Permitted only for explicit
  /// [VolumeChangeSource.userCalibration] and only while unlocked.
  ///
  /// Throws [VolumeChangeDenied] if the level is locked or the source is not
  /// user calibration. Returns the (clamped) new level on success.
  double setLevel(
    double value, {
    VolumeChangeSource source = VolumeChangeSource.userCalibration,
  }) {
    if (source != VolumeChangeSource.userCalibration) {
      throw VolumeChangeDenied('level may only change via user calibration');
    }
    if (_locked) {
      throw VolumeChangeDenied('master volume is locked during a test');
    }
    _level = value.clamp(minLevel, maxLevel).toDouble();
    return _level;
  }

  /// Locks the level for the duration of a test. Idempotent.
  void lock() => _locked = true;

  /// Unlocks the level after a test finishes or the user leaves to
  /// re-calibrate. Idempotent.
  void unlock() => _locked = false;

  /// Called for every response during a test. It is intentionally a no-op with
  /// respect to [_level]; its existence documents and enforces (via tests) the
  /// invariant that responses — correct or incorrect — never move master
  /// volume. Adaptation happens on SNR/rate/complexity, not level.
  void registerResponse({required bool correct}) {
    // No effect on master volume, by design. Do not add level changes here.
  }

  /// Safety snapshot suitable for logging / attaching to a session. Never
  /// reports an absolute (dB HL) threshold.
  Map<String, Object> safetyState() => <String, Object>{
        'auto_volume': autoVolume,
        'absolute_thresholds': false,
        'comfortable_level': _level,
        'locked': _locked,
      };
}
