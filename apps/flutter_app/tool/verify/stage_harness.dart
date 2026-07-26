// Headless verification harness for the five-stage protocol workflow.
//
//   dart run tool/verify/stage_harness.dart
import 'dart:io';

import '../../lib/core/protocol_stage.dart';

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
  check('five stages in canonical order', ProtocolStage.values.length == 5);
  check(
    'order is intro->preview->training->test->results',
    ProtocolStage.values.join(',') ==
        'ProtocolStage.introduction,ProtocolStage.preview,'
            'ProtocolStage.training,ProtocolStage.test,ProtocolStage.results',
  );
  check('labels', protocolStageLabel(ProtocolStage.training) == 'Training');

  final c = ProtocolStageController();
  check('starts at introduction', c.current == ProtocolStage.introduction);
  check('isFirst', c.isFirst);
  check('canAdvance at start', c.canAdvance);
  check('advance -> preview', c.advance() == ProtocolStage.preview);
  check('advance -> training', c.advance() == ProtocolStage.training);
  check('advance -> test', c.advance() == ProtocolStage.test);
  check('advance -> results', c.advance() == ProtocolStage.results);
  check('isLast at results', c.isLast);
  check('cannot advance past results', !c.canAdvance);
  check('advance at last is a no-op', c.advance() == ProtocolStage.results);
  c.reset();
  check(
      'reset returns to introduction', c.current == ProtocolStage.introduction);

  final two = ProtocolStageController(
    stages: const [ProtocolStage.introduction, ProtocolStage.preview],
  );
  check('custom stage list respected', two.stages.length == 2);
  check('custom list advances to last',
      two.advance() == ProtocolStage.preview && two.isLast);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks stage checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks stage checks');
    exit(1);
  }
}
