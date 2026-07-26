// Headless verification harness for the catalog models.
//
// Runnable WITHOUT Flutter or `pub get`:
//   dart run tool/verify/catalog_harness.dart
//
// It parses the real asset (assets/protocols/catalog.json) through the same
// pure-Dart models the app uses, and asserts the catalog contract the UI and
// engine rely on. Exits non-zero on any failure.
import 'dart:convert';
import 'dart:io';

import '../../lib/models/catalog.dart';

int _checks = 0;
int _failures = 0;

void check(String name, bool condition) {
  _checks++;
  if (condition) {
    stdout.writeln('  ok   $name');
  } else {
    _failures++;
    stdout.writeln('  FAIL $name');
  }
}

File _resolveCatalog(List<String> args) {
  if (args.isNotEmpty) return File(args.first);
  // tool/verify/ -> ../../ == flutter_app root
  final uri = Platform.script.resolve('../../assets/protocols/catalog.json');
  return File.fromUri(uri);
}

void main(List<String> args) {
  final file = _resolveCatalog(args);
  if (!file.existsSync()) {
    stderr.writeln('catalog not found: ${file.path}');
    exit(2);
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final catalog = Catalog.fromJson(json);

  stdout.writeln('catalog_harness: ${file.path}');

  // Document-level contract.
  check('schema_version present', catalog.schemaVersion.isNotEmpty);
  check('product is HearBloom', catalog.product == 'HearBloom');
  check('status is research_specification', catalog.isResearchSpecification);
  check('nine modules', catalog.modules.length == 9);
  check('56 explicit groups', catalog.groupCount == 56);

  // Module lookup works.
  check(
    'moduleById(noise) resolves',
    catalog.moduleById('noise')?.name == 'Adaptive Speech in Noise',
  );
  check('unknown module id -> null', catalog.moduleById('nope') == null);

  // Telephone module inherits foundation and carries no own groups.
  final telephone = catalog.moduleById('telephone');
  check(
    'telephone inherits foundation',
    telephone != null && telephone.inherits == 'foundation',
  );
  check(
    'telephone has empty own groups',
    telephone != null && telephone.groups.isEmpty,
  );

  // Per-group invariants across the whole catalog.
  final seenGlobalKeys = <String>{};
  var allUnvalidated = true;
  var allCanonicalWorkflow = true;
  var allProtocolNonEmpty = true;
  var allIdsNonEmpty = true;
  var duplicateWithinModule = false;

  for (final module in catalog.modules) {
    final idsInModule = <String>{};
    for (final g in module.groups) {
      final globalKey = '${module.id}/${g.id}';
      seenGlobalKeys.add(globalKey);
      if (!idsInModule.add(g.id)) duplicateWithinModule = true;
      if (g.validationStatus != 'unvalidated') allUnvalidated = false;
      if (!g.hasCanonicalWorkflow) allCanonicalWorkflow = false;
      if (g.protocol.isEmpty || g.protocol == 'unspecified') {
        allProtocolNonEmpty = false;
      }
      if (g.id.isEmpty || g.name.isEmpty) allIdsNonEmpty = false;
    }
  }

  check('every group unvalidated', allUnvalidated);
  check('every group has canonical 5-stage workflow', allCanonicalWorkflow);
  check('every group has a concrete protocol key', allProtocolNonEmpty);
  check('every group has non-empty id and name', allIdsNonEmpty);
  check('no duplicate group ids within a module', !duplicateWithinModule);
  check('56 unique module/group keys', seenGlobalKeys.length == 56);

  // Spot-check a known adaptive-SNR group used by later slices.
  final sin = catalog.moduleById('noise')?.groups.firstWhere(
        (g) => g.id == 'sentence_noise',
        orElse: () => throw StateError('sentence_noise missing'),
      );
  check(
    'sentence_noise protocol is adaptive_snr_4afc',
    sin?.protocol == 'adaptive_snr_4afc',
  );
  check('sentence_noise carries step_db=2', sin?.parameters['step_db'] == 2);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks catalog checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks catalog checks');
    exit(1);
  }
}
