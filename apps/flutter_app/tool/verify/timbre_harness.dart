// Headless verification for timbre / SFX / melody synthesis.
//
//   dart run tool/verify/timbre_harness.dart
import 'dart:io';

import '../../lib/core/audio/timbre.dart';

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

const int sr = 48000;

void main() {
  check('6 instruments', kInstruments.length == 6);
  final flute = instrumentTone(instrument: 'flute', freqHz: 440, seconds: 0.5);
  final trumpet =
      instrumentTone(instrument: 'trumpet', freqHz: 440, seconds: 0.5);
  check('instrument length', flute.length == (0.5 * sr).round());
  check('instrument normalized', peak(flute) <= 0.25 + 1e-6);
  check('timbres differ', flute[500] != trumpet[500]);
  final fluteB = instrumentTone(instrument: 'flute', freqHz: 440, seconds: 0.5);
  check('instrument deterministic', flute[500] == fluteB[500]);
  check(
      'guitar decays',
      instrumentTone(instrument: 'guitar', freqHz: 440, seconds: 0.6)
              .last
              .abs() <
          instrumentTone(instrument: 'organ', freqHz: 440, seconds: 0.6)[24000]
                  .abs() +
              0.3);

  // Sound effects.
  check('6 sfx', kSfx.length == 6);
  for (final s in kSfx) {
    final buf = sfxStimulus(s);
    check('sfx $s builds, no clip', buf.isNotEmpty && peak(buf) <= 0.9 + 1e-6);
  }
  check('sfx deterministic',
      sfxStimulus('bell')[1000] == sfxStimulus('bell')[1000]);

  // Melodies.
  check('6 melodies', kMelodyIds.length == 6 && kMelodies.length == 6);
  final twinkle = melodySynth('twinkle');
  check('melody builds, no clip',
      twinkle.isNotEmpty && peak(twinkle) <= 0.9 + 1e-6);
  check('melody deterministic', twinkle[2000] == melodySynth('twinkle')[2000]);
  check('melodies differ',
      melodySynth('mary').length != melodySynth('ode').length);
  check('titles present',
      kMelodyIds.every((m) => (kMelodyTitles[m] ?? '').isNotEmpty));

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks timbre checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks timbre checks');
    exit(1);
  }
}
