/// Typed, immutable models for the HearBloom protocol catalog.
///
/// This file is intentionally **pure Dart** (it imports nothing from
/// `package:flutter`). That keeps the parsing/validation logic runnable in a
/// headless harness (`dart run tool/verify/catalog_harness.dart`) and unit
/// tests, independent of the UI layer.
///
/// The catalog is a *research specification*. Nothing here asserts clinical
/// validity: every group carries an explicit [ProtocolGroup.validationStatus]
/// that the UI must surface to the user.
library;

/// Canonical five-stage protocol workflow, in required order.
///
/// Mirrors the `modes` array carried by every catalog group and the
/// KIRO_HANDOFF "Definition of done for a protocol".
const List<String> kWorkflowStages = <String>[
  'introduction',
  'preview',
  'training',
  'test',
  'results',
];

/// Root catalog document (`protocols/catalog.json`).
class Catalog {
  const Catalog({
    required this.schemaVersion,
    required this.product,
    required this.status,
    required this.modules,
  });

  /// Schema version of the catalog document itself (e.g. `1.0.0`).
  final String schemaVersion;

  /// Product name (e.g. `HearBloom`).
  final String product;

  /// Lifecycle status. For research builds this is `research_specification`.
  final String status;

  /// Ordered list of protocol modules.
  final List<Module> modules;

  factory Catalog.fromJson(Map<String, dynamic> json) {
    final rawModules = (json['modules'] as List<dynamic>?) ?? const <dynamic>[];
    return Catalog(
      schemaVersion: (json['schema_version'] as String?) ?? '',
      product: (json['product'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      modules: rawModules
          .map((dynamic m) => Module.fromJson(m as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// True only for the non-diagnostic research specification. The UI keys its
  /// "RESEARCH ONLY" boundary messaging off this.
  bool get isResearchSpecification => status == 'research_specification';

  /// Total number of explicitly defined groups across all modules.
  int get groupCount =>
      modules.fold<int>(0, (int n, Module m) => n + m.groups.length);

  Module? moduleById(String id) {
    for (final Module m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// A protocol module (e.g. "Adaptive Speech in Noise").
class Module {
  const Module({
    required this.id,
    required this.name,
    required this.audience,
    required this.groups,
    this.inherits,
  });

  final String id;
  final String name;

  /// Intended audience tags (e.g. `adult`, `teen`, `child`, `caregiver`).
  final List<String> audience;

  /// When set, this module inherits another module's groups (e.g. the
  /// Telephone module inherits `foundation`). Such modules may carry an empty
  /// [groups] list of their own.
  final String? inherits;

  final List<ProtocolGroup> groups;

  factory Module.fromJson(Map<String, dynamic> json) {
    final rawGroups = (json['groups'] as List<dynamic>?) ?? const <dynamic>[];
    final rawAudience =
        (json['audience'] as List<dynamic>?) ?? const <dynamic>[];
    return Module(
      id: json['id'] as String,
      name: json['name'] as String,
      audience:
          rawAudience.map((dynamic e) => e as String).toList(growable: false),
      inherits: json['inherits'] as String?,
      groups: rawGroups
          .map((dynamic g) => ProtocolGroup.fromJson(g as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  bool get inheritsAnother => inherits != null && inherits!.isNotEmpty;
}

/// A single trainable/assessable protocol group within a [Module].
class ProtocolGroup {
  const ProtocolGroup({
    required this.id,
    required this.name,
    required this.protocol,
    required this.modes,
    required this.validationStatus,
    required this.parameters,
  });

  final String id;
  final String name;

  /// Renderer/engine key, e.g. `adaptive_snr_4afc`, `mci_9choice`,
  /// `typed_open_set`.
  final String protocol;

  /// Workflow stages offered by this group (normally [kWorkflowStages]).
  final List<String> modes;

  /// Research validation state. `unvalidated` for every group in the current
  /// specification; never silently treated as validated.
  final String validationStatus;

  /// Free-form protocol parameters (trials, levels, step_db, noises, ...).
  final Map<String, dynamic> parameters;

  factory ProtocolGroup.fromJson(Map<String, dynamic> json) {
    final rawModes = (json['modes'] as List<dynamic>?) ?? const <dynamic>[];
    return ProtocolGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: (json['protocol'] as String?) ?? 'unspecified',
      modes: rawModes.map((dynamic e) => e as String).toList(growable: false),
      validationStatus: (json['validation_status'] as String?) ?? 'unvalidated',
      parameters: (json['parameters'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
  }

  /// A group is only "validated" when explicitly marked so. Anything else
  /// (including the default) must be presented to the user as not validated.
  bool get isValidated => validationStatus == 'validated';

  /// True when this group follows the full five-stage workflow.
  bool get hasCanonicalWorkflow =>
      modes.length == kWorkflowStages.length &&
      List<int>.generate(
        modes.length,
        (int i) => i,
      ).every((int i) => modes[i] == kWorkflowStages[i]);
}
