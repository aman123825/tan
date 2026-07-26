import 'dart:math';
import 'dart:typed_data';

import 'audio/pcm_synth.dart';

/// Masking Level Difference (MLD) test logic.
///
/// Presents a 500 Hz pulsed tone embedded in narrowband noise under two
/// binaural conditions:
/// - S₀N₀: signal and noise in-phase in both ears (homophasic)
/// - SπN₀: signal phase-inverted in one ear, noise same phase (antiphasic)
///
/// An adaptive 2-down/1-up staircase finds threshold in each condition.
/// MLD = threshold(S₀N₀) - threshold(SπN₀). Normal ≥ 10 dB.

/// Generate narrowband noise centered at [centerHz] with bandwidth [bwHz].
List<double> narrowbandNoise({
  required double seconds,
  double centerHz = 500,
  double bwHz = 100,
  double amplitude = 0.4,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  // Generate white noise then bandpass filter (simple FIR approximation)
  final rng = Random(seed);
  final n = (seconds * sampleRate).round();
  final white = List<double>.generate(n, (_) => (rng.nextDouble() * 2 - 1) * amplitude);

  // Simple 2nd-order bandpass via biquad coefficients
  final w0 = 2 * pi * centerHz / sampleRate;
  final q = centerHz / bwHz;
  final alpha = sin(w0) / (2 * q);

  final b0 = alpha;
  final b1 = 0.0;
  final b2 = -alpha;
  final a0 = 1 + alpha;
  final a1 = -2 * cos(w0);
  final a2 = 1 - alpha;

  final out = List<double>.filled(n, 0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < n; i++) {
    final x0 = white[i];
    out[i] = (b0 / a0) * x0 + (b1 / a0) * x1 + (b2 / a0) * x2 -
        (a1 / a0) * y1 - (a2 / a0) * y2;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = out[i];
  }
  return out;
}

/// Generate a 500 Hz pulsed tone (200ms on, 200ms off, repeated).
List<double> pulsedTone({
  required double seconds,
  double freqHz = 500,
  double amplitude = 0.3,
  double onMs = 200,
  double offMs = 200,
  double riseFallMs = 10,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  final onSamples = (onMs / 1000 * sampleRate).round();
  final offSamples = (offMs / 1000 * sampleRate).round();
  final riseFall = (riseFallMs / 1000 * sampleRate).round();
  final period = onSamples + offSamples;

  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final posInPeriod = i % period;
    if (posInPeriod < onSamples) {
      final t = i / sampleRate;
      var env = 1.0;
      if (posInPeriod < riseFall) {
        env = posInPeriod / riseFall;
      } else if (posInPeriod > onSamples - riseFall) {
        env = (onSamples - posInPeriod) / riseFall;
      }
      out[i] = amplitude * env * sin(2 * pi * freqHz * t);
    }
  }
  return out;
}

/// Build an MLD stimulus WAV for one trial.
///
/// [condition]: 'S0N0' (homophasic) or 'SpiN0' (signal inverted in right ear).
/// [signalLevel]: amplitude of the tone (0.0–1.0, adaptive).
/// [noiseLevel]: amplitude of the noise (fixed).
/// [tonePresent]: whether the tone is present this trial (for yes/no detection).
Uint8List buildMldStimulus({
  required String condition,
  required double signalLevel,
  double noiseLevel = 0.3,
  bool tonePresent = true,
  double seconds = 1.5,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  final noise = narrowbandNoise(
    seconds: seconds,
    amplitude: noiseLevel,
    seed: seed,
    sampleRate: sampleRate,
  );
  final n = noise.length;

  List<double> toneL, toneR;
  if (tonePresent) {
    final tone = pulsedTone(
      seconds: seconds,
      amplitude: signalLevel,
      sampleRate: sampleRate,
    );
    toneL = tone;
    if (condition == 'SpiN0') {
      // Invert signal phase in right ear
      toneR = tone.map((s) => -s).toList();
    } else {
      toneR = List<double>.from(tone);
    }
  } else {
    toneL = List<double>.filled(n, 0);
    toneR = List<double>.filled(n, 0);
  }

  // Mix: left = noise + toneL, right = noise + toneR
  final left = List<double>.generate(n, (i) => noise[i] + toneL[i]);
  final right = List<double>.generate(n, (i) => noise[i] + toneR[i]);

  return encodeWavStereo16(left, right, sampleRate: sampleRate);
}

/// Simple 2-down/1-up adaptive staircase for MLD threshold.
class MldStaircase {
  MldStaircase({
    this.startLevel = 0.4,
    this.stepDb = 4,
    this.minStepDb = 1,
    this.maxReversals = 8,
  });

  double startLevel;
  double stepDb;
  double minStepDb;
  int maxReversals;

  double _currentLevel = 0.4;
  int _correctStreak = 0;
  int _reversals = 0;
  bool _lastDirectionUp = false;
  final List<double> _reversalLevels = [];
  double _currentStepDb = 4;

  double get currentLevel => _currentLevel;
  int get reversals => _reversals;
  bool get isComplete => _reversals >= maxReversals;

  /// Threshold from the last N/2 reversals (standard clinical method).
  double? get threshold {
    if (_reversalLevels.length < 4) return null;
    final last = _reversalLevels.sublist(_reversalLevels.length ~/ 2);
    return last.reduce((a, b) => a + b) / last.length;
  }

  void init() {
    _currentLevel = startLevel;
    _correctStreak = 0;
    _reversals = 0;
    _lastDirectionUp = false;
    _reversalLevels.clear();
    _currentStepDb = stepDb;
  }

  /// Record a response. [detected] = true if listener heard the tone.
  void respond(bool detected, bool tonePresent) {
    final correct = detected == tonePresent;

    if (correct) {
      _correctStreak++;
      if (_correctStreak >= 2) {
        // Decrease level (harder)
        _correctStreak = 0;
        final newUp = false;
        if (_lastDirectionUp != newUp && _reversals > 0 || _reversals == 0) {
          if (_lastDirectionUp) {
            _reversals++;
            _reversalLevels.add(_currentLevel);
            if (_reversals >= 2 && _currentStepDb > minStepDb) {
              _currentStepDb = (_currentStepDb / 2).clamp(minStepDb, stepDb);
            }
          }
        }
        _lastDirectionUp = newUp;
        _currentLevel *= _dbToRatio(-_currentStepDb);
        if (_currentLevel < 0.001) _currentLevel = 0.001;
      }
    } else {
      _correctStreak = 0;
      // Increase level (easier)
      final newUp = true;
      if (!_lastDirectionUp && _reversals > 0) {
        _reversals++;
        _reversalLevels.add(_currentLevel);
        if (_reversals >= 2 && _currentStepDb > minStepDb) {
          _currentStepDb = (_currentStepDb / 2).clamp(minStepDb, stepDb);
        }
      }
      _lastDirectionUp = newUp;
      _currentLevel *= _dbToRatio(_currentStepDb);
      if (_currentLevel > 1.0) _currentLevel = 1.0;
    }
  }

  double _dbToRatio(double db) => pow(10, db / 20).toDouble();
}

/// MLD session that runs both conditions and computes the MLD.
class MldSession {
  /// [startLevel] sets the starting tone amplitude for both staircases (a
  /// higher level is easier to detect). Defaults to 0.4 to preserve the
  /// original behaviour; the difficulty-level system passes a level per preset.
  MldSession({double startLevel = 0.4})
      : s0n0 = (MldStaircase(startLevel: startLevel)..init()),
        spiN0 = (MldStaircase(startLevel: startLevel)..init());

  final MldStaircase s0n0;
  final MldStaircase spiN0;

  /// The MLD in dB (difference between thresholds). Null if not enough reversals.
  double? get mldDb {
    final t1 = s0n0.threshold;
    final t2 = spiN0.threshold;
    if (t1 == null || t2 == null) return null;
    // Convert amplitude ratios to dB, then subtract
    final db1 = 20 * log(t1) / ln10;
    final db2 = 20 * log(t2) / ln10;
    return db1 - db2; // S0N0 threshold is higher (worse), so MLD is positive
  }

  /// Normal MLD ≥ 10 dB (adults), ≥ 9 dB (children).
  String interpret(int ageYears) {
    final mld = mldDb;
    if (mld == null) return 'insufficient data';
    final cutoff = ageYears < 12 ? 9.0 : 10.0;
    if (mld >= cutoff) return 'normal binaural processing';
    if (mld >= cutoff - 3) return 'borderline';
    return 'below normal — possible brainstem binaural integration deficit';
  }
}
