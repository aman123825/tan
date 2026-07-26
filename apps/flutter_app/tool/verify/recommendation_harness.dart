// Headless verification harness for the recommendation model.
//
//   dart run tool/verify/recommendation_harness.dart
//
// Both fixtures are real `GET /profiles/{id}/recommendation` payloads captured
// from the backend recommender.
import 'dart:convert';
import 'dart:io';

import '../../lib/models/recommendation.dart';

const String kBaseline = '{"group_id": "sentence_noise", "module_id": "noise", '
    '"reason": "Start with an easy speech-in-noise baseline.", '
    '"confidence": 0.5, "parameters": {"snr_db": 12, "mode": "training"}}';

const String kWeak =
    '{"group_id": "initial_consonant_noise", "module_id": "noise", '
    '"reason": "initial_consonant_noise is the weakest practiced area (0% '
    'across 10 trials); reduce complexity without increasing volume.", '
    '"confidence": 0.7, "parameters": {"difficulty_delta": -1, '
    '"target_accuracy": [0.7, 0.85]}}';

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

Recommendation _parse(String s) =>
    Recommendation.fromJson(jsonDecode(s) as Map<String, dynamic>);

void main() {
  final baseline = _parse(kBaseline);
  check(
    'baseline group is sentence_noise',
    baseline.groupId == 'sentence_noise',
  );
  check('baseline module is noise', baseline.moduleId == 'noise');
  check('baseline has a reason', baseline.hasReason);
  check('baseline confidence 50%', baseline.confidencePercent == 50);
  check(
    'baseline parameters parsed',
    baseline.parameters['mode'] == 'training' &&
        baseline.parameters['snr_db'] == 12,
  );
  check('baseline is advisory (no volume)', !baseline.raisesVolume);

  final weak = _parse(kWeak);
  check(
    'weak targets weakest group',
    weak.groupId == 'initial_consonant_noise',
  );
  check('weak reason explains why', weak.reason.contains('weakest'));
  check('weak confidence 70%', weak.confidencePercent == 70);
  check(
    'weak reduces complexity, not volume',
    weak.parameters['difficulty_delta'] == -1 && !weak.raisesVolume,
  );
  check(
    'confidence clamped into [0,1] display',
    baseline.confidencePercent >= 0 && baseline.confidencePercent <= 100,
  );

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks recommendation checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks recommendation checks');
    exit(1);
  }
}
