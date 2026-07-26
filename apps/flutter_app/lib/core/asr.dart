/// Optional speech-to-text answer assistance for open-set tasks (pure Dart).
///
/// ASR here is strictly *assistance*: it may pre-fill the answer field with a
/// best-effort transcript that the listener can always edit, but it never
/// auto-submits, never scores, and never changes the locked deterministic
/// scoring. It is kept behind an interface so a concrete on-device (offline)
/// engine is a plug-in/product decision; the default [DisabledAsrProvider]
/// requires no dependency and no network, so builds and tests are unaffected.
library;

/// A best-effort transcript with an optional confidence in [0, 1].
class AsrResult {
  const AsrResult(this.transcript, {this.confidence = 1.0});

  final String transcript;
  final double confidence;
}

/// A speech-to-text provider. Implementations must operate offline or decline
/// (return `isAvailable == false` / `null`).
abstract class AsrProvider {
  /// Whether assistance is available on this device/build. When false, the UI
  /// shows no microphone affordance and behaves exactly as before.
  bool get isAvailable;

  /// Captures one spoken response and returns a best-effort transcript, or null
  /// if unavailable, cancelled, or nothing was recognized. Never throws for the
  /// normal "no result" case.
  Future<AsrResult?> listen();
}

/// The default: assistance disabled. No microphone, no dependency, no network.
class DisabledAsrProvider implements AsrProvider {
  const DisabledAsrProvider();

  @override
  bool get isAvailable => false;

  @override
  Future<AsrResult?> listen() async => null;
}
