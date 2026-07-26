// Headless verification harness for the normative interpretation module.
//
//   dart run tool/verify/norms_harness.dart
//
// Asserts the research-derived band boundaries. The same boundaries are checked
// in tests/test_norms.py, keeping the Dart/Python interpretation identical.
import 'dart:io';

import '../../lib/core/norms.dart';

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
  // Null / too-few-trials => insufficient (never a fabricated interpretation).
  check('gap null -> insufficient', Norms.gapMs(null).isInsufficient);
  check('freq null -> insufficient',
      Norms.frequencySemitones(null).isInsufficient);
  check('am null -> insufficient', Norms.amDepthDb(null).isInsufficient);
  check('snr null -> insufficient', Norms.speechSnrDb(null).isInsufficient);
  check('dichotic null -> insufficient',
      Norms.dichoticPercent(null).isInsufficient);

  // Gap detection (GIN ≤ 6 ms normal).
  check('gap 3.5 -> better', Norms.gapMs(3.5).band == NormBand.betterThanTypical);
  check('gap 5 -> within', Norms.gapMs(5).band == NormBand.withinTypical);
  check('gap 6 -> within (cut-off inclusive)',
      Norms.gapMs(6).band == NormBand.withinTypical);
  check('gap 8 -> slightly below',
      Norms.gapMs(8).band == NormBand.slightlyBelowTypical);
  check('gap 20 -> below', Norms.gapMs(20).band == NormBand.belowTypical);
  check('gap carries a citation', Norms.gapMs(5).citation.contains('GIN'));

  // Frequency (semitones).
  check('freq 0.3 -> better',
      Norms.frequencySemitones(0.3).band == NormBand.betterThanTypical);
  check('freq 1 -> within',
      Norms.frequencySemitones(1).band == NormBand.withinTypical);
  check('freq 1.5 -> slightly below',
      Norms.frequencySemitones(1.5).band == NormBand.slightlyBelowTypical);
  check('freq 4 -> below',
      Norms.frequencySemitones(4).band == NormBand.belowTypical);

  // AM depth (dB; more negative better).
  check('am -22 -> better', Norms.amDepthDb(-22).band == NormBand.betterThanTypical);
  check('am -15 -> within', Norms.amDepthDb(-15).band == NormBand.withinTypical);
  check('am -8 -> slightly below',
      Norms.amDepthDb(-8).band == NormBand.slightlyBelowTypical);
  check('am -3 -> below', Norms.amDepthDb(-3).band == NormBand.belowTypical);

  // Speech-in-noise SNR (dB; lower better).
  check('snr -2 -> better', Norms.speechSnrDb(-2).band == NormBand.betterThanTypical);
  check('snr 3 -> within', Norms.speechSnrDb(3).band == NormBand.withinTypical);
  check('snr 6 -> slightly below',
      Norms.speechSnrDb(6).band == NormBand.slightlyBelowTypical);
  check('snr 12 -> below', Norms.speechSnrDb(12).band == NormBand.belowTypical);

  // Dichotic digits (% per ear; higher better).
  check('dichotic 97 -> better',
      Norms.dichoticPercent(97).band == NormBand.betterThanTypical);
  check('dichotic 91 -> within',
      Norms.dichoticPercent(91).band == NormBand.withinTypical);
  check('dichotic 85 -> slightly below',
      Norms.dichoticPercent(85).band == NormBand.slightlyBelowTypical);
  check('dichotic 70 -> below',
      Norms.dichoticPercent(70).band == NormBand.belowTypical);

  // Guessing correction (Abbott's formula) for nAFC tasks.
  check('chance-corrected 4AFC 0.6 ~ 0.467',
      (Norms.chanceCorrected(0.6, 4) - 0.4666666666666667).abs() < 1e-9);
  check('chance-corrected at chance -> 0', Norms.chanceCorrected(0.25, 4) == 0);
  check('chance-corrected perfect -> 1', Norms.chanceCorrected(1.0, 3) == 1);
  check('chance-corrected below chance clamps to 0',
      Norms.chanceCorrected(0.1, 4) == 0);

  // Favourable helper.
  check('within is favourable', NormBand.withinTypical.isFavorable);
  check('below is not favourable', !NormBand.belowTypical.isFavorable);

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('PASS $_checks/$_checks norms checks');
    exit(0);
  } else {
    stdout.writeln('FAILED $_failures/$_checks norms checks');
    exit(1);
  }
}
