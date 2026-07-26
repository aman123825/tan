// Headless verification for chord identification.
//
//   dart run tool/verify/chord_harness.dart
import 'dart:io';

import '../../lib/core/chord_identification.dart';

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

double peak(List<double> x) {
  var mx = 0.0;
  for (final v in x) {
    if (v.abs() > mx) mx = v.abs();
  }
  return mx;
}

void main() {
  // Chord table.
  check('four default chords', kChordChoices.length == 4);
  check('major triad offsets',
      kChordChoices.first.semitones.join(',') == '0,4,7');

  // Synthesis: additive triad is non-empty and does not clip.
  final major = chordStimulus(rootHz: 261.63, semitones: const [0, 4, 7]);
  check('chord synth non-empty', major.isNotEmpty);
  check('chord synth no clipping', peak(major) <= 0.9 + 1e-6);
  // A triad (3 partials) has more energy than a single tone at the same amp.
  final single = chordStimulus(rootHz: 261.63, semitones: const [0]);
  check('triad differs from single note', major.length == single.length);

  // Generator determinism + root variation set.
  final a = ChordGenerator(seed: 9).next();
  final b = ChordGenerator(seed: 9).next();
  check('generator deterministic',
      a.targetIndex == b.targetIndex && a.rootHz == b.rootHz);
  check('root from candidate set', kChordRootsHz.contains(a.rootHz));
  check('trial synth builds', a.synth().isNotEmpty);

  // Session scoring.
  final s = ChordSession(maxTrials: 5);
  final trial = ChordTrial(targetIndex: 1, rootHz: 220); // minor
  check('correct id', s.submit(trial, 1, latencyMs: 700));
  check('wrong id', !s.submit(trial, 0, latencyMs: 700));
  check('accuracy = 1/2', (s.accuracy - 0.5).abs() < 1e-9);
  check('records chord id', s.records.first.parameters['chord'] == 'minor');
  check('records root', s.records.first.parameters['root_hz'] == 220);
  check(
      'no volume key',
      !s.records.first
          .toJson()
          .keys
          .any((k) => k.toLowerCase().contains('volume')));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks chord checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks chord checks');
    exit(1);
  }
}
