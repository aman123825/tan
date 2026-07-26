/// Pure-Dart timbre, sound-effect and melody synthesis for the music and
/// environmental-sound demo tasks. All output is synthesized `demo_only`
/// material (no recordings) in [-1, 1]; each buffer is peak-normalized so it
/// never clips. Nothing here touches master volume.
library;

import 'dart:math';

import 'pcm_synth.dart';

/// Relative harmonic amplitudes (harmonic 1..n) giving each instrument a
/// distinct timbre via additive synthesis.
const Map<String, List<double>> kInstrumentHarmonics = <String, List<double>>{
  'flute': [1.0, 0.25, 0.12, 0.05],
  'clarinet': [1.0, 0.0, 0.45, 0.0, 0.25, 0.0, 0.12],
  'trumpet': [1.0, 0.85, 0.65, 0.5, 0.4, 0.3, 0.2],
  'violin': [1.0, 0.7, 0.55, 0.45, 0.4, 0.32, 0.26, 0.2],
  'organ': [1.0, 0.6, 0.0, 0.6, 0.0, 0.0, 0.4],
  'guitar': [1.0, 0.55, 0.38, 0.26, 0.16, 0.1],
};

/// Exponential decay rate per instrument (0 = sustained, larger = plucked).
const Map<String, double> kInstrumentDecay = <String, double>{
  'flute': 0.0,
  'clarinet': 0.0,
  'trumpet': 0.0,
  'violin': 0.0,
  'organ': 0.0,
  'guitar': 4.0,
};

/// The six instrument choices.
const List<String> kInstruments = <String>[
  'flute',
  'clarinet',
  'trumpet',
  'violin',
  'organ',
  'guitar'
];

/// Additively synthesizes one instrument note, peak-normalized to [amp].
List<double> instrumentTone({
  required String instrument,
  required double freqHz,
  double seconds = 0.6,
  double amp = 0.25,
  int sampleRate = kSampleRate,
}) {
  final profile = kInstrumentHarmonics[instrument] ?? const <double>[1.0];
  final decay = kInstrumentDecay[instrument] ?? 0.0;
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0.0);
  for (var h = 0; h < profile.length; h++) {
    final a = profile[h];
    if (a == 0) continue;
    final f = freqHz * (h + 1);
    if (f > sampleRate / 2) break;
    for (var i = 0; i < n; i++) {
      out[i] += a * sin(2 * pi * f * i / sampleRate);
    }
  }
  final fade = (0.008 * sampleRate).round().clamp(1, n ~/ 2);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    var env = decay > 0 ? exp(-decay * i / sampleRate) : 1.0;
    if (i < fade) {
      env *= i / fade;
    } else if (i >= n - fade) {
      env *= (n - 1 - i) / fade;
    }
    out[i] *= env;
    final ab = out[i].abs();
    if (ab > peak) peak = ab;
  }
  if (peak > 0) {
    final k = amp / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= k;
    }
  }
  return out;
}

List<double> _peakNorm(List<double> x, [double peak = 0.9]) {
  var mx = 0.0;
  for (final v in x) {
    if (v.abs() > mx) mx = v.abs();
  }
  if (mx > 0 && mx != peak) {
    final k = peak / mx;
    for (var i = 0; i < x.length; i++) {
      x[i] *= k;
    }
  }
  return x;
}

/// The six synthesized sound-effect choices (demonstrations, not recordings).
const List<String> kSfx = <String>[
  'bell',
  'siren',
  'knock',
  'whistle',
  'buzzer',
  'phone'
];

/// Synthesizes a distinct demonstration sound effect.
List<double> sfxStimulus(String name, {int sampleRate = kSampleRate}) {
  switch (name) {
    case 'bell':
      // Inharmonic metallic partials with a long decay.
      final n = (1.2 * sampleRate).round();
      final out = List<double>.filled(n, 0.0);
      const partials = <double>[1.0, 2.76, 5.4, 8.9];
      const amps = <double>[1.0, 0.6, 0.4, 0.25];
      for (var p = 0; p < partials.length; p++) {
        final f = 660.0 * partials[p];
        for (var i = 0; i < n; i++) {
          out[i] += amps[p] *
              exp(-3.0 * i / sampleRate) *
              sin(2 * pi * f * i / sampleRate);
        }
      }
      return _peakNorm(out);
    case 'siren':
      // Frequency swept up and down (police-siren style).
      final n = (1.4 * sampleRate).round();
      final out = List<double>.filled(n, 0.0);
      var phase = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final f = 700 + 350 * sin(2 * pi * 0.9 * t);
        phase += 2 * pi * f / sampleRate;
        out[i] = sin(phase);
      }
      return _peakNorm(out);
    case 'knock':
      // Three short low-frequency thuds.
      final parts = <List<double>>[];
      for (var k = 0; k < 3; k++) {
        parts.add(
            tone(seconds: 0.05, freqHz: 90, amp: 0.9, sampleRate: sampleRate));
        parts.add(silence(0.12, sampleRate));
      }
      return _peakNorm(concat(parts));
    case 'whistle':
      // High tone with vibrato.
      final n = (0.9 * sampleRate).round();
      final out = List<double>.filled(n, 0.0);
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        out[i] = sin(2 * pi * 2100 * t + 0.15 * sin(2 * pi * 6 * t));
      }
      return _peakNorm(out);
    case 'buzzer':
      // Harsh low tone (many harmonics).
      final n = (0.7 * sampleRate).round();
      final out = List<double>.filled(n, 0.0);
      for (var h = 1; h <= 9; h += 2) {
        for (var i = 0; i < n; i++) {
          out[i] += (1.0 / h) * sin(2 * pi * 180 * h * i / sampleRate);
        }
      }
      return _peakNorm(out);
    case 'phone':
      // Two-tone ring pattern (on/off/on).
      List<double> ring() {
        final n = (0.4 * sampleRate).round();
        final out = List<double>.filled(n, 0.0);
        for (var i = 0; i < n; i++) {
          final t = i / sampleRate;
          out[i] = 0.5 * (sin(2 * pi * 480 * t) + sin(2 * pi * 620 * t));
        }
        return out;
      }
      return _peakNorm(
          concat(<List<double>>[ring(), silence(0.2, sampleRate), ring()]));
    default:
      return tone(seconds: 0.5, freqHz: 440, sampleRate: sampleRate);
  }
}

/// Public-domain melodies as semitone offsets from the root (equal durations).
const Map<String, List<int>> kMelodies = <String, List<int>>{
  'twinkle': [0, 0, 7, 7, 9, 9, 7, 5, 5, 4, 4, 2, 2, 0],
  'mary': [4, 2, 0, 2, 4, 4, 4, 2, 2, 2, 4, 7, 7],
  'jingle': [4, 4, 4, 4, 4, 4, 4, 7, 0, 2, 4],
  'ode': [4, 4, 5, 7, 7, 5, 4, 2, 0, 0, 2, 4, 4, 2, 2],
  'frere': [0, 2, 4, 0, 0, 2, 4, 0, 4, 5, 7],
  'london': [7, 9, 7, 5, 4, 5, 7, 2, 4, 5],
};

/// Human-readable melody titles.
const Map<String, String> kMelodyTitles = <String, String>{
  'twinkle': 'Twinkle, Twinkle',
  'mary': 'Mary Had a Little Lamb',
  'jingle': 'Jingle Bells',
  'ode': 'Ode to Joy',
  'frere': 'Frère Jacques',
  'london': 'London Bridge',
};

const List<String> kMelodyIds = <String>[
  'twinkle',
  'mary',
  'jingle',
  'ode',
  'frere',
  'london'
];

/// Synthesizes a melody as a sequence of instrument notes from its semitone
/// offsets (equal note durations; short gaps between notes).
List<double> melodySynth(
  String melodyId, {
  double rootHz = 261.63,
  double noteSeconds = 0.35,
  double gapSeconds = 0.06,
  String instrument = 'flute',
  int sampleRate = kSampleRate,
}) {
  final offsets = kMelodies[melodyId] ?? const <int>[0];
  final parts = <List<double>>[];
  for (var i = 0; i < offsets.length; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    parts.add(instrumentTone(
      instrument: instrument,
      freqHz: shiftSemitones(rootHz, offsets[i].toDouble()),
      seconds: noteSeconds,
      sampleRate: sampleRate,
    ));
  }
  return _peakNorm(concat(parts));
}

/// Builds an auditory instrument sequence: each named instrument played at a
/// fixed pitch (so timbre, not pitch, is the cue), separated by short gaps.
List<double> instrumentSequenceStimulus(
  List<String> instruments, {
  double freqHz = 330,
  double noteSeconds = 0.45,
  double gapSeconds = 0.1,
  int sampleRate = kSampleRate,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < instruments.length; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    parts.add(instrumentTone(
      instrument: instruments[i],
      freqHz: freqHz,
      seconds: noteSeconds,
      sampleRate: sampleRate,
    ));
  }
  return _peakNorm(concat(parts));
}

/// Instrumental music masker (K4): two seeded public-domain melodies on
/// different synthesized instruments, offset in time and pitch, looped to
/// fill [seconds] -- competing MUSIC rather than noise/babble, for
/// music-in-noise style tasks. Deterministic per [seed]; peak-normalized so
/// the caller's SNR mix governs level.
List<double> musicMaskerStimulus({
  double seconds = 6,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  final rng = Random(seed);
  final ids = List<String>.of(kMelodyIds)..shuffle(rng);
  final a = melodySynth(ids[0],
      instrument: 'organ',
      rootHz: 196.0, // G3: below the target melodies' usual C4 root
      noteSeconds: 0.4,
      sampleRate: sampleRate);
  final b = melodySynth(ids[1],
      instrument: 'violin',
      rootHz: 246.94, // B3
      noteSeconds: 0.31,
      sampleRate: sampleRate);
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0);
  final offsetB = (0.7 * sampleRate).round();
  for (var i = 0; i < n; i++) {
    out[i] = a[i % a.length] * 0.7 + b[(i + offsetB) % b.length] * 0.5;
  }
  return _peakNorm(out);
}
