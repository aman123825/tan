/// Difficulty-level system for HearBloom tests and training (pure Dart).
///
/// THE PROBLEM this solves: every adaptive test currently starts at its easiest
/// setting and adapts toward threshold. A listener with mild (or no) difficulty
/// therefore wastes trials on easy items before the staircase reaches a useful
/// range. Letting them START at a harder level shortens the run and puts trials
/// where they actually discriminate.
///
/// This layer only describes *starting parameters*. It is deliberately:
///   • Flutter-free, so it can be unit-tested headlessly and reused anywhere.
///   • Non-destructive to the locked engine: it never changes master volume,
///     and it never mutates the golden-pinned `AdaptiveTrack.*()` defaults —
///     the presets are passed in explicitly at launch, so the deterministic
///     engine's own defaults (and their golden vectors) are untouched.
library;

/// The four selectable difficulty levels, ordered from the most assistance
/// (easy) to near-normal research/validation parameters (expert).
enum DifficultyLevel { easy, medium, hard, expert }

/// Immutable bundle of starting parameters for one difficulty level.
///
/// A single config carries starting values for every task family; each task
/// reads the field(s) relevant to it (e.g. speech-in-noise reads [startSnrDb],
/// pattern tests read [trialsPerEar]). Values that a given task does not use are
/// simply ignored — the config is a data descriptor, not a controller.
class DifficultyConfig {
  const DifficultyConfig({
    required this.startValue,
    required this.stepSize,
    required this.trialsPerEar,
    required this.speedMultiplier,
    required this.startingChannels,
    required this.startGapMs,
    required this.startSnrDb,
  });

  /// Generic starting "assistance" for adaptive interval tasks, in [0, 1] where
  /// 1.0 = maximum help (largest, most obvious difference). Task-specific fields
  /// below take precedence where they exist.
  final double startValue;

  /// Initial adaptation step for SNR-style staircases (dB). Larger = the task
  /// changes faster per reversal (faster convergence, coarser precision).
  final double stepSize;

  /// Trials per ear for the pattern tests (DPT / FPT). Fewer trials = a shorter,
  /// harder run for a more capable listener.
  final int trialsPerEar;

  /// Training speech-rate multiplier (1.0 = natural rate; higher = faster and
  /// harder to follow).
  final double speedMultiplier;

  /// Vocoder starting channel count (more channels = clearer, easier speech).
  final int startingChannels;

  /// Gap-detection starting gap (ms) — a larger gap is easier to hear.
  final double startGapMs;

  /// Speech-in-noise starting SNR (dB) — a higher SNR is easier.
  final double startSnrDb;
}

// -----------------------------------------------------------------------------
// The four presets, with clinically-motivated starting values.
// -----------------------------------------------------------------------------

/// Beginner / severe deficit: starts at maximum assistance, slow adaptation.
const DifficultyConfig _easyConfig = DifficultyConfig(
  startValue: 1.0,
  stepSize: 1.5,
  trialsPerEar: 30,
  speedMultiplier: 1.0,
  startingChannels: 32,
  startGapMs: 20,
  startSnrDb: 15,
);

/// Moderate deficit: starts midway with normal adaptation. The default.
const DifficultyConfig _mediumConfig = DifficultyConfig(
  startValue: 0.7,
  stepSize: 2.0,
  trialsPerEar: 25,
  speedMultiplier: 1.3,
  startingChannels: 16,
  startGapMs: 10,
  startSnrDb: 10,
);

/// Mild deficit / normal hearing: starts near threshold with fast adaptation.
const DifficultyConfig _hardConfig = DifficultyConfig(
  startValue: 0.4,
  stepSize: 3.0,
  trialsPerEar: 20,
  speedMultiplier: 1.5,
  startingChannels: 8,
  startGapMs: 6,
  startSnrDb: 5,
);

/// Validation / research: starts at near-normal parameters, minimal adaptation.
const DifficultyConfig _expertConfig = DifficultyConfig(
  startValue: 0.2,
  stepSize: 1.0,
  trialsPerEar: 15,
  speedMultiplier: 1.8,
  startingChannels: 4,
  startGapMs: 4,
  startSnrDb: 0,
);

/// Presentation + configuration helpers for [DifficultyLevel].
extension DifficultyLevelInfo on DifficultyLevel {
  /// Starting-parameter bundle for this level.
  DifficultyConfig get config => switch (this) {
        DifficultyLevel.easy => _easyConfig,
        DifficultyLevel.medium => _mediumConfig,
        DifficultyLevel.hard => _hardConfig,
        DifficultyLevel.expert => _expertConfig,
      };

  /// Short display name ("Easy", "Medium", "Hard", "Expert").
  String get label => switch (this) {
        DifficultyLevel.easy => 'Easy',
        DifficultyLevel.medium => 'Medium',
        DifficultyLevel.hard => 'Hard',
        DifficultyLevel.expert => 'Expert',
      };

  /// One-line card subtitle.
  String get shortDescription => switch (this) {
        DifficultyLevel.easy => 'For beginners',
        DifficultyLevel.medium => 'Standard clinical',
        DifficultyLevel.hard => 'For mild deficits',
        DifficultyLevel.expert => 'Research validation',
      };

  /// Fuller explanation for tooltips / help text.
  String get longDescription => switch (this) {
        DifficultyLevel.easy =>
          'Starts at maximum assistance and adapts slowly. Best for a first '
              'session or a more severe deficit.',
        DifficultyLevel.medium =>
          'Starts midway with normal adaptation — the standard clinical '
              'starting point.',
        DifficultyLevel.hard =>
          'Starts near threshold and adapts quickly. Suited to a mild deficit '
              'or normal hearing.',
        DifficultyLevel.expert =>
          'Starts at near-normal parameters with minimal adaptation, for '
              'validation and research runs.',
      };

  /// Stable string used for persistence.
  String get storageKey => name;

  /// Level for a stored [value], falling back to [DifficultyLevel.medium].
  static DifficultyLevel fromStorage(String? value) {
    for (final level in DifficultyLevel.values) {
      if (level.name == value) return level;
    }
    return DifficultyLevel.medium;
  }
}
