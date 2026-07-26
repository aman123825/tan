/// Residual inhibition measurement (pure Dart, Flutter-free).
///
/// The classic RI procedure (Vernon & Meikle, 2003; Roberts, 2007): a masking
/// noise plays for one minute at MML + 10 dB; when it stops, many listeners'
/// tinnitus is briefly suppressed. The listener reports the suppression depth
/// (complete / partial / none) and the page times how long it takes the
/// tinnitus to return to normal. Both are informational research
/// observations — RI does not treat tinnitus.
///
/// SAFETY: the masker level is `min(MML + 10, amplitude cap)` — it can never
/// exceed the app-wide on-signal cap, and master volume is untouched.
library;

import 'dart:math';

import '../protocol_engine.dart';
import 'levels.dart';

/// The listener's report of what the masker did to their tinnitus.
enum RiDepth { complete, partial, none }

extension RiDepthInfo on RiDepth {
  String get label => switch (this) {
        RiDepth.complete => 'Completely gone',
        RiDepth.partial => 'Quieter than usual',
        RiDepth.none => 'Unchanged',
      };
}

/// One residual-inhibition run.
class ResidualInhibitionSession {
  ResidualInhibitionSession({
    required this.mmlDb,
    this.maskerSeconds = 60,
  });

  final String moduleId = 'tinnitus';
  final String groupId = 'residual_inhibition';

  /// The stored minimum masking level (relative dB); the masker plays 10 dB
  /// above it, capped.
  final double mmlDb;
  final int maskerSeconds;

  /// Masker level in relative dB — MML + 10, hard-capped at the level where
  /// the amplitude cap engages (it cannot get louder than the cap anyway;
  /// clamping the *number* keeps the display honest).
  double get maskerDb => min(mmlDb + 10, amplitudeCapDb());

  /// Masker amplitude (always ≤ [kMaxSafeAmp]).
  double get maskerAmplitude => relativeDbToAmplitude(maskerDb);

  RiDepth? depth;
  double? returnSeconds;

  /// Records the immediate post-masker report.
  void recordDepth(RiDepth d) => depth = d;

  /// Records how long the suppression lasted (seconds from masker offset).
  void recordReturnSeconds(double s) => returnSeconds = max(0, s);

  bool get isComplete =>
      depth == RiDepth.none || (depth != null && returnSeconds != null);

  /// Whether any residual inhibition was observed.
  bool get positive => depth != null && depth != RiDepth.none;

  /// Event records for persistence/export (one record for the whole run).
  List<TrialRecord> get records => depth == null
      ? const <TrialRecord>[]
      : <TrialRecord>[
          TrialRecord(
            target: 'masker_offset',
            response: depth!.name,
            // "Correct" = any suppression observed (bookkeeping only).
            correct: positive,
            latencyMs: ((returnSeconds ?? 0) * 1000).round(),
            parameters: <String, Object?>{
              'mml_db': mmlDb,
              'masker_db': maskerDb,
              'masker_seconds': maskerSeconds,
              if (returnSeconds != null) 'return_seconds': returnSeconds,
            },
          ),
        ];

  /// Plain-language summary of the observation.
  String summary() {
    if (depth == null) return 'No report recorded.';
    if (!positive) {
      return 'No residual inhibition this run — the tinnitus was unchanged '
          'after the masker. This is common and not a bad sign.';
    }
    final secs = returnSeconds;
    final duration = secs == null
        ? ''
        : ' It took about ${secs.round()} s to return to normal.';
    return 'Residual inhibition observed: tinnitus was '
        '${depth == RiDepth.complete ? 'completely suppressed' : 'partially suppressed'} '
        'after the masker.$duration';
  }
}
