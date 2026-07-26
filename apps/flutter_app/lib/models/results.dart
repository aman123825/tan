/// Typed models for `GET /profiles/{id}/results` (pure Dart).
///
/// Mirrors the backend response in `services/api/main.py`. Results are
/// presented per (condition, output_device, module, group, mode) bucket and are
/// never pooled across ear-condition or output device — [ResultsSummary.notPooled]
/// reflects the server's pooling policy so the UI can state it plainly.
library;

/// Reliability verdict for a bucket, produced by the deterministic engine's
/// `Score.reliability`.
class Reliability {
  const Reliability({
    required this.reliable,
    this.reason,
    this.replayRate,
    this.fastRate,
  });

  final bool reliable;

  /// Present when not assessable (e.g. `insufficient_trials`).
  final String? reason;
  final double? replayRate;
  final double? fastRate;

  factory Reliability.fromJson(Map<String, dynamic> json) => Reliability(
        reliable: (json['reliable'] as bool?) ?? false,
        reason: json['reason'] as String?,
        replayRate: (json['replay_rate'] as num?)?.toDouble(),
        fastRate: (json['fast_rate'] as num?)?.toDouble(),
      );
}

/// One separated result bucket.
class ConditionResult {
  const ConditionResult({
    required this.condition,
    required this.outputDevice,
    required this.moduleId,
    required this.groupId,
    required this.mode,
    required this.n,
    required this.accuracy,
    required this.meanLatencyMs,
    required this.reliability,
  });

  final String? condition;
  final String? outputDevice;
  final String moduleId;
  final String groupId;
  final String mode;
  final int n;
  final double? accuracy;
  final double? meanLatencyMs;
  final Reliability reliability;

  factory ConditionResult.fromJson(Map<String, dynamic> json) =>
      ConditionResult(
        condition: json['condition'] as String?,
        outputDevice: json['output_device'] as String?,
        moduleId: json['module_id'] as String,
        groupId: json['group_id'] as String,
        mode: json['mode'] as String,
        n: (json['n'] as num).toInt(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        meanLatencyMs: (json['mean_latency_ms'] as num?)?.toDouble(),
        reliability: Reliability.fromJson(
          (json['reliability'] as Map).cast<String, dynamic>(),
        ),
      );
}

/// Full results payload for a profile.
class ResultsSummary {
  const ResultsSummary({
    required this.totalTrials,
    required this.accuracy,
    required this.poolingPolicy,
    required this.separated,
  });

  final int totalTrials;
  final double? accuracy;
  final String poolingPolicy;
  final List<ConditionResult> separated;

  factory ResultsSummary.fromJson(Map<String, dynamic> json) => ResultsSummary(
        totalTrials: (json['total_trials'] as num?)?.toInt() ?? 0,
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        poolingPolicy: (json['pooling_policy'] as String?) ?? '',
        separated: ((json['separated'] as List<dynamic>?) ?? const <dynamic>[])
            .map(
              (dynamic e) =>
                  ConditionResult.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList(growable: false),
      );

  /// True when the server guarantees results are not pooled across condition or
  /// output device (the safety invariant).
  bool get notPooled =>
      poolingPolicy == 'not_pooled_across_condition_or_device';
}
