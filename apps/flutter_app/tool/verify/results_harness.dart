// Headless verification harness for the results models.
//
//   dart run tool/verify/results_harness.dart
//
// The fixture below is a real `GET /profiles/{id}/results` payload captured
// from the backend, so this asserts the Dart model parses the true shape.
import 'dart:convert';
import 'dart:io';

import '../../lib/models/results.dart';

// Authentic backend response (trials array omitted; the model does not use it).
const String kFixture = '''
{
  "total_trials": 23,
  "accuracy": 0.8695652173913043,
  "pooling_policy": "not_pooled_across_condition_or_device",
  "separated": [
    {"condition": "binaural", "output_device": "bluetooth", "module_id": "noise",
     "group_id": "sentence_noise", "mode": "training", "n": 3, "accuracy": 0.0,
     "mean_latency_ms": 500.0,
     "reliability": {"reliable": false, "reason": "insufficient_trials"}},
    {"condition": "binaural", "output_device": "wired_headphones", "module_id": "noise",
     "group_id": "sentence_noise", "mode": "test", "n": 20, "accuracy": 1.0,
     "mean_latency_ms": 600.0,
     "reliability": {"reliable": true, "replay_rate": 0.0, "fast_rate": 0.0}}
  ]
}
''';

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

void main() {
  final summary = ResultsSummary.fromJson(
    jsonDecode(kFixture) as Map<String, dynamic>,
  );

  check('total_trials parsed', summary.totalTrials == 23);
  check(
    'overall accuracy parsed',
    summary.accuracy != null && (summary.accuracy! - 0.8695652).abs() < 1e-6,
  );
  check('not pooled across condition/device', summary.notPooled);
  check('two separated buckets', summary.separated.length == 2);

  // Buckets are NOT pooled: two distinct output devices are present.
  final devices = summary.separated.map((b) => b.outputDevice).toSet();
  check(
    'wired and bluetooth kept separate',
    devices.contains('wired_headphones') && devices.contains('bluetooth'),
  );

  final bt = summary.separated.firstWhere((b) => b.outputDevice == 'bluetooth');
  check('bluetooth bucket n=3', bt.n == 3);
  check(
    'bluetooth insufficient trials',
    !bt.reliability.reliable && bt.reliability.reason == 'insufficient_trials',
  );

  final wired = summary.separated.firstWhere(
    (b) => b.outputDevice == 'wired_headphones',
  );
  check('wired bucket n=20', wired.n == 20);
  check('wired accuracy 1.0', wired.accuracy == 1.0);
  check(
    'wired reliable with rates',
    wired.reliability.reliable &&
        wired.reliability.replayRate == 0.0 &&
        wired.reliability.fastRate == 0.0,
  );
  check('wired mode is test', wired.mode == 'test');

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks results checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks results checks');
    exit(1);
  }
}
