/// Patient-reported fatigue scale (pure Dart).
///
/// A 0–10 self-report collected after a session. Fatigue is informational only:
/// it is never used to alter the locked deterministic scoring or to change
/// master volume — it simply travels with the session (`fatigue_after`) so
/// research can account for tiredness. "Fatigue is not failure."
library;

class FatigueScale {
  const FatigueScale._();

  static const int min = 0;
  static const int max = 10;

  static bool isValid(int value) => value >= min && value <= max;

  static int clamp(int value) =>
      value < min ? min : (value > max ? max : value);

  /// Coarse bucket label for a rating (for display/summaries).
  static String bucket(int value) {
    final v = clamp(value);
    if (v <= 1) return 'None';
    if (v <= 3) return 'Mild';
    if (v <= 6) return 'Moderate';
    if (v <= 8) return 'High';
    return 'Severe';
  }
}
