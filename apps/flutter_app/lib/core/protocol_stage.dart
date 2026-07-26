/// Five-stage protocol workflow (pure Dart).
///
/// Every catalog group declares the canonical workflow
/// `introduction → preview → training → test → results` (see
/// `models/catalog.dart::kWorkflowStages` and the KIRO handoff "Definition of
/// done for a protocol"). This controller models progression through those
/// stages deterministically so the UI and its transitions can be unit-tested.
library;

/// The five workflow stages, in canonical order.
enum ProtocolStage { introduction, preview, training, test, results }

/// Human-readable label for a stage.
String protocolStageLabel(ProtocolStage stage) => switch (stage) {
      ProtocolStage.introduction => 'Introduction',
      ProtocolStage.preview => 'Preview',
      ProtocolStage.training => 'Training',
      ProtocolStage.test => 'Test',
      ProtocolStage.results => 'Results',
    };

/// Drives forward progression through a fixed ordered list of stages.
class ProtocolStageController {
  ProtocolStageController({List<ProtocolStage>? stages})
      : stages = List<ProtocolStage>.unmodifiable(
          stages ?? ProtocolStage.values,
        ),
        assert((stages ?? ProtocolStage.values).isNotEmpty);

  final List<ProtocolStage> stages;
  int _index = 0;

  ProtocolStage get current => stages[_index];
  int get index => _index;
  bool get isFirst => _index == 0;
  bool get isLast => _index == stages.length - 1;
  bool get canAdvance => !isLast;

  /// Advances to the next stage (no-op at the last stage). Returns [current].
  ProtocolStage advance() {
    if (!isLast) _index++;
    return current;
  }

  void reset() => _index = 0;
}
