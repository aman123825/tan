/// Contextual encouragement messages (pure Dart).
///
/// A tiny motivational helper that maps a trial outcome + session progress to a
/// short encouragement string, or null when nothing should be shown. Purely
/// motivational — it never affects scoring, adaptation or master volume.
///
/// Flutter-free so it can be unit-tested headlessly; the animated banner that
/// displays these lives in `trial_scaffold.dart`.
library;

import 'dart:math';

/// Selects short encouragement lines based on streaks and progress.
class Encouragement {
  const Encouragement._();

  /// Shown after 3+ correct answers in a row.
  static const List<String> streak = <String>[
    'Great streak!',
    'On fire! 🔥',
    'Excellent!',
    'Perfect hearing!',
  ];

  /// Shown after a wrong answer that broke a streak.
  static const List<String> brokeStreak = <String>[
    'Keep going!',
    'That was tough.',
    'Stay focused!',
  ];

  /// Shown once when the listener passes the halfway point.
  static const List<String> halfway = <String>[
    'Halfway there!',
    'Great progress!',
  ];

  /// Shown when every trial has been completed.
  static const List<String> complete = <String>[
    'Session complete! Well done!',
  ];

  /// A streak counts as "broken" (worth an encouraging nudge) from this many
  /// consecutive-correct answers.
  static const int brokeStreakThreshold = 2;

  /// The consecutive-correct count that earns a streak celebration.
  static const int streakThreshold = 3;

  /// Returns an encouragement line for the trial that just finished, or null.
  ///
  /// [correct] whether the just-answered trial was correct.
  /// [streakAfter] consecutive-correct count *after* this trial (0 when wrong).
  /// [priorStreak] consecutive-correct count *before* this trial.
  /// [completed] number of trials completed so far (including this one).
  /// [total] total trials in the session.
  ///
  /// Priority: session-complete → halfway milestone → active streak →
  /// broken streak. [rng] is injectable for deterministic tests.
  static String? forTrial({
    required bool correct,
    required int streakAfter,
    required int priorStreak,
    required int completed,
    required int total,
    Random? rng,
  }) {
    final r = rng ?? Random();
    if (total > 0 && completed >= total) {
      return _pick(complete, r);
    }
    // Fire the halfway nudge exactly once, on the trial that crosses 50%.
    if (total > 1 && completed == (total / 2).floor() && completed > 0) {
      return _pick(halfway, r);
    }
    if (correct && streakAfter >= streakThreshold) {
      return _pick(streak, r);
    }
    if (!correct && priorStreak >= brokeStreakThreshold) {
      return _pick(brokeStreak, r);
    }
    return null;
  }

  static String _pick(List<String> options, Random r) =>
      options[r.nextInt(options.length)];
}
