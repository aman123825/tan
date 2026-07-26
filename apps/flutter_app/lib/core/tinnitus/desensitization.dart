/// Hyperacusis sound-desensitization program logic (pure Dart, Flutter-free).
///
/// A graded-exposure listening program (cf. Formby et al., 2015; TRT category
/// practice): daily 10-minute sessions of broadband noise starting well below
/// the listener's measured discomfort level and rising by 2 dB per completed
/// step across 14 steps. Education/self-practice framing only — a clinical
/// hyperacusis program belongs with an audiologist.
///
/// SAFETY (non-negotiable):
///  * every level is clamped ≥ 10 dB BELOW the stored LDL (when measured);
///  * every level is clamped at the app-wide amplitude cap;
///  * at most one step advances per calendar day;
///  * levels only rise between sessions, never during one, and stopping
///    early never advances the step. Master volume is untouched.
library;

import 'dart:math';

import 'levels.dart';

/// Total steps in the program (one per day at most).
const int kDesensitizationSteps = 14;

/// Minutes of listening per step.
const int kDesensitizationMinutes = 10;

/// Per-step level increase (relative dB).
const double kDesensitizationStepDb = 2;

/// Starting level relative to the ceiling (start 26 dB below it, so a
/// completed program ends exactly at the ceiling).
const double kDesensitizationStartOffsetDb = -26;

/// The graded-exposure ladder derived from the listener's measurements.
class DesensitizationProgram {
  DesensitizationProgram({this.ldlDb, this.completedSteps = 0});

  /// Stored loudness-discomfort level (relative dB), when measured.
  final double? ldlDb;

  /// Steps completed so far (0..[kDesensitizationSteps]).
  int completedSteps;

  /// The hard level ceiling: 10 dB below the measured LDL, never above the
  /// app-wide amplitude cap. Without a measured LDL, 10 dB below the cap.
  double get ceilingDb {
    final capDb = amplitudeCapDb();
    return ldlDb == null ? capDb - 10 : min(ldlDb! - 10, capDb);
  }

  /// Level (relative dB) for step [index] (0-based), always ≤ [ceilingDb].
  double levelForStep(int index) {
    final i = index.clamp(0, kDesensitizationSteps - 1);
    final level =
        ceilingDb + kDesensitizationStartOffsetDb + kDesensitizationStepDb * i;
    return min(level, ceilingDb);
  }

  /// Level for the next (current) session.
  double get currentLevelDb =>
      levelForStep(min(completedSteps, kDesensitizationSteps - 1));

  /// Amplitude for the current session (always ≤ the safety cap).
  double get currentAmplitude => relativeDbToAmplitude(currentLevelDb);

  bool get isFinished => completedSteps >= kDesensitizationSteps;

  /// Marks today's step complete (idempotent per day — the caller checks the
  /// last-completed date via [DesensitizationStore]).
  void completeStep() {
    if (!isFinished) completedSteps++;
  }
}

/// Formats a calendar day as `yyyy-mm-dd` for the one-step-per-day rule.
String desensitizationDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Whether a step may be completed on [today] given the [lastCompletedDay]
/// (yyyy-mm-dd or null): at most one step per calendar day.
bool canCompleteStepToday(String? lastCompletedDay, DateTime today) =>
    lastCompletedDay != desensitizationDayKey(today);
