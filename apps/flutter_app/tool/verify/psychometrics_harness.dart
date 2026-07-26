/// Headless checks for `lib/core/psychometrics.dart`.
///
/// Pins the same golden values as `tests/test_psychometrics.py` so the Dart
/// and Python implementations cannot drift apart.
library;

import 'dart:io';

import '../../lib/core/psychometrics.dart';

int _failures = 0;

void check(String name, bool condition) {
  if (condition) {
    stdout.writeln('PASS $name');
  } else {
    _failures++;
    stdout.writeln('FAIL $name');
  }
}

void checkClose(String name, double? actual, double expected, double tol) {
  check('$name (${actual?.toStringAsFixed(7)} ~ $expected)',
      actual != null && (actual - expected).abs() < tol);
}

// The shared golden staircase-style run — identical to the Python test.
const goldenX = <double>[
  12, 10, 8, 6, 4, 6, 4, 2, 4, 2, 3, 2, 3, 2, 3, 2, 1, 2, 1, 2
];
const goldenCorrect = <bool>[
  true, true, true, true, false, true, true, false, true, false,
  true, false, true, true, false, true, false, true, false, true,
];

void main() {
  checkClose('normalCdf(0)', normalCdf(0), 0.5, 1e-9);
  checkClose('normalCdf(1)', normalCdf(1), 0.8413447, 2e-7);
  checkClose('normalCdf(-1)', normalCdf(-1), 0.1586553, 2e-7);

  // 2AFC closed form: pc = Phi(d'/sqrt(2)).
  checkClose('pcFromDPrime(1, 2)', pcFromDPrime(1, 2), 0.7602499, 1e-4);
  // Hacker & Ratcliff (1979): 3AFC, d' = 1 -> ~0.6337.
  checkClose('pcFromDPrime(1, 3)', pcFromDPrime(1, 3), 0.6337020, 1e-4);
  checkClose('pcFromDPrime(2, 4)', pcFromDPrime(2, 4), 0.8227929, 1e-4);

  checkClose('dPrimeFromPc(0.634, 3)', dPrimeFromPc(0.634, 3), 1.0010300, 1e-3);
  check('dPrimeFromPc at chance is null', dPrimeFromPc(0.33, 3) == null);
  check('dPrimeFromPc near 1 is null', dPrimeFromPc(0.9999, 3) == null);
  // Round trip: pc -> d' -> pc.
  final rt = pcFromDPrime(dPrimeFromPc(0.75, 3)!, 3);
  checkClose('round trip pc 0.75 (3AFC)', rt, 0.75, 1e-3);

  final fit = fitLogistic(goldenX, goldenCorrect, guessRate: 1 / 3);
  check('golden fit converges', fit != null);
  if (fit != null) {
    checkClose('golden fit alpha', fit.alpha, 3.2152778, 1e-5);
    checkClose('golden fit beta', fit.beta, 1.0375200, 1e-5);
    checkClose('golden fit threshold', fit.threshold, 3.5178188, 1e-5);
    checkClose('golden fit p(6)', fit.probabilityAt(6), 0.9459273, 1e-5);
    // The fitted curve is monotonically increasing in x.
    check('fit monotone',
        fit.probabilityAt(2) < fit.probabilityAt(4) &&
            fit.probabilityAt(4) < fit.probabilityAt(8));
    // Threshold proportion is honoured by the curve itself.
    checkClose('fit passes through target at threshold',
        fit.probabilityAt(fit.threshold!), fit.targetProportion, 1e-6);
  }

  check('degenerate all-correct refused',
      fitLogistic(goldenX, List.filled(goldenX.length, true), guessRate: 1 / 3) ==
          null);
  check('degenerate short run refused',
      fitLogistic(goldenX.sublist(0, 4), goldenCorrect.sublist(0, 4),
              guessRate: 1 / 3) ==
          null);
  check(
      'degenerate flat x refused',
      fitLogistic(List.filled(10, 2.0), goldenCorrect.sublist(0, 10),
              guessRate: 1 / 3) ==
          null);

  // ICC golden matrix — identical to GOLDEN_RETEST in the Python test
  // (MSR = 45.125, MSC = 0.125, MSE = 1.125 by hand).
  const goldenRetest = <List<double>>[
    [10, 12],
    [14, 13],
    [18, 19],
    [22, 21],
  ];
  checkClose('icc21 golden', icc21(goldenRetest), 0.9617486338797814, 1e-9);
  checkClose('icc31 golden', icc31(goldenRetest), 0.9513513513513514, 1e-9);
  // A constant occasion offset hurts absolute agreement, not consistency.
  final shifted = <List<double>>[
    for (final row in goldenRetest) [row[0], row[1] + 2],
  ];
  check('icc21 < icc31 under occasion offset',
      icc21(shifted)! < icc31(shifted)!);
  check('icc refuses one subject', icc21(<List<double>>[[1, 2]]) == null);
  check('icc refuses one occasion',
      icc21(<List<double>>[[1], [2]]) == null);
  check('icc refuses ragged rows',
      icc21(<List<double>>[[1, 2], [3]]) == null);
  check('icc refuses zero variance',
      icc21(<List<double>>[[5, 5], [5, 5]]) == null &&
          icc31(<List<double>>[[5, 5], [5, 5]]) == null);

  // Sanity: pc is monotone in d' for each m.
  var monotone = true;
  for (final m in [2, 3, 4]) {
    var prev = -1.0;
    for (var d = 0.0; d <= 4; d += 0.5) {
      final pc = pcFromDPrime(d, m);
      if (pc < prev) monotone = false;
      prev = pc;
    }
  }
  check('pcFromDPrime monotone in d\'', monotone);
  // d' = 0 means chance performance.
  checkClose('pc at d\'=0 (3AFC) is chance', pcFromDPrime(0, 3), 1 / 3, 1e-3);
  check('m < 2 throws', () {
    try {
      pcFromDPrime(1, 1);
      return false;
    } on ArgumentError {
      return true;
    }
  }());

  stdout.writeln(_failures == 0
      ? 'ALL PSYCHOMETRICS CHECKS PASSED'
      : '$_failures PSYCHOMETRICS CHECKS FAILED');
  if (_failures > 0) exit(1);
}
