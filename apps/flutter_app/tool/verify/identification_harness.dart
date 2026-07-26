// Headless verification for generic audio identification.
//
//   dart run tool/verify/identification_harness.dart
import 'dart:io';

import '../../lib/core/identification.dart';

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

const List<IdentificationChoice> _pool = <IdentificationChoice>[
  IdentificationChoice(id: 'flute', label: 'Flute'),
  IdentificationChoice(id: 'trumpet', label: 'Trumpet'),
  IdentificationChoice(id: 'violin', label: 'Violin'),
  IdentificationChoice(id: 'organ', label: 'Organ'),
  IdentificationChoice(id: 'guitar', label: 'Guitar', emoji: '🎸'),
];

void main() {
  final gen = IdentificationGenerator(pool: _pool, choiceCount: 4, seed: 6);
  final t = gen.next();
  check('choice count', t.choices.length == 4);
  check('target among choices', t.choices.any((c) => c.id == t.target.id));
  check('unique choices',
      t.choices.map((c) => c.id).toSet().length == t.choices.length);
  check('target index resolves', t.choices[t.targetIndex].id == t.target.id);
  final t2 =
      IdentificationGenerator(pool: _pool, choiceCount: 4, seed: 6).next();
  check(
      'deterministic',
      t2.target.id == t.target.id &&
          t2.choices.map((c) => c.id).join(',') ==
              t.choices.map((c) => c.id).join(','));

  final s = IdentificationSession(
      moduleId: 'music', groupId: 'instrument', maxTrials: 5);
  check('correct id', s.submit(t, t.targetIndex, latencyMs: 600));
  check('wrong id',
      !s.submit(t, (t.targetIndex + 1) % t.choices.length, latencyMs: 600));
  check('accuracy 1/2', (s.accuracy - 0.5).abs() < 1e-9);
  check('records target', s.records.first.target == t.target.id);
  check('records choices param', s.records.first.parameters['choices'] == 4);
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks identification checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks identification checks');
    exit(1);
  }
}
