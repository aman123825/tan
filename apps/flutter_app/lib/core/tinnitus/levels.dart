/// Safe relative-dB → amplitude mapping for tinnitus/hyperacusis generators
/// (pure Dart, Flutter-free so headless harnesses can exercise it).
///
/// SAFETY: [relativeDbToAmplitude] clamps generated amplitude to
/// [kMaxSafeAmp] (0.7). This is the on-signal amplitude cap; the app's
/// master-volume lock still applies on top and is never raised by any
/// response.
library;

import 'dart:math' as math;

/// Hard on-signal amplitude cap for tinnitus/hyperacusis generators.
const double kMaxSafeAmp = 0.7;

/// Soft reference amplitude for 0 relative-dB.
const double kRefAmp = 0.02;

/// Converts a relative-dB level into a normalized amplitude in [0, cap].
///
/// `amp = kRefAmp * 10^(db/20)`, clamped to [0, cap]. Relative only — the
/// audio is uncalibrated and this is NOT dB SPL/HL. [cap] defaults to
/// [kMaxSafeAmp] and can only be lowered by callers, never raised above it.
double relativeDbToAmplitude(double db, {double cap = kMaxSafeAmp}) {
  final safeCap = cap.clamp(0.0, kMaxSafeAmp);
  final amp = kRefAmp * math.pow(10, db / 20).toDouble();
  return amp.clamp(0.0, safeCap).toDouble();
}

/// The relative-dB level at which [relativeDbToAmplitude] first reaches
/// [cap] (i.e. the ceiling level). Above this, amplitude is clamped and no
/// longer increases — used so ascending tasks know when they have hit the
/// safety cap.
double amplitudeCapDb({double cap = kMaxSafeAmp}) {
  final safeCap = cap.clamp(1e-6, kMaxSafeAmp);
  return 20 * (math.log(safeCap / kRefAmp) / math.ln10);
}
