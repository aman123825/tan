/// Typed model for `GET /profiles/{id}/recommendation` (pure Dart).
///
/// The recommender is advisory and explainable: every recommendation carries a
/// human-readable [reason] and a [confidence]. It suggests what to train next
/// and can never change locked assessment scoring or raise master volume — a
/// clinician can always override it.
library;

class Recommendation {
  const Recommendation({
    required this.moduleId,
    required this.groupId,
    required this.reason,
    required this.confidence,
    required this.parameters,
  });

  final String moduleId;
  final String groupId;
  final String reason;
  final double confidence;
  final Map<String, dynamic> parameters;

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        moduleId: (json['module_id'] as String?) ?? '',
        groupId: (json['group_id'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        parameters: (json['parameters'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  int get confidencePercent => (confidence.clamp(0, 1) * 100).round();

  bool get hasReason => reason.trim().isNotEmpty;

  /// Advisory-only guarantee: a recommendation never instructs a master-volume
  /// increase. Should always be false; surfaced so the UI/tests can assert it.
  bool get raisesVolume =>
      parameters.keys.any((k) => k.toLowerCase().contains('volume'));
}
