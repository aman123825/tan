/// Pure-Dart stimulus synthesis for the generic interval-discrimination tasks
/// (level/amplitude, tone detection incl. forward masking, and rhythm).
///
/// All builders return a single concatenated buffer for the whole N-interval
/// trial in [-1, 1]. A trial-wide gain is applied so the buffer never clips,
/// which preserves the *within-trial* level relationships that carry the cue
/// (unlike per-interval normalization). No builder touches master volume.
library;

import 'dart:math';

import 'pcm_synth.dart';

/// Linear amplitude scaled from [baseAmp] by [db] (20*log10 convention).
double ampFromDb(double baseAmp, double db) =>
    baseAmp * pow(10, db / 20).toDouble();

/// Scales the whole buffer by a single gain if its peak exceeds [peak], so
/// relative levels between intervals are preserved.
List<double> _limitPeak(List<double> x, [double peak = 0.95]) {
  var mx = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > mx) mx = a;
  }
  if (mx <= peak || mx == 0) return x;
  final k = peak / mx;
  for (var i = 0; i < x.length; i++) {
    x[i] *= k;
  }
  return x;
}

/// Level/amplitude-discrimination stimulus: [intervals] bursts of the same
/// carrier; the [targetInterval] burst is [deltaDb] louder. The listener picks
/// the louder one; smaller [deltaDb] is harder.
List<double> levelDiscriminationStimulus({
  required int targetInterval,
  required double deltaDb,
  int intervals = 3,
  double baseAmp = 0.2,
  double toneHz = 1000,
  double toneSeconds = 0.4,
  double gapSeconds = 0.2,
  bool useNoise = false,
  int seed = 1,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(gapSeconds));
    final amp = i == targetInterval ? ampFromDb(baseAmp, deltaDb) : baseAmp;
    parts.add(
      useNoise
          ? whiteNoise(seconds: toneSeconds, amp: amp, seed: seed + i)
          : tone(seconds: toneSeconds, freqHz: toneHz, amp: amp),
    );
  }
  return _limitPeak(concat(parts));
}

/// Tone-detection stimulus: only the [targetInterval] contains a probe tone.
/// With [maskerAmp] > 0 the probe sits in noise; with [forwardGapMs] > 0 the
/// masker precedes the probe (forward masking). [toneLevelDb] is the probe
/// level relative to the reference (masker level, or a fixed baseline in quiet);
/// lower (more negative) is harder to detect.
///
/// RESEARCH ONLY: this is a relative-level detection task, not audiometry, and
/// yields no dB HL threshold.
List<double> detectionStimulus({
  required int targetInterval,
  required double toneLevelDb,
  int intervals = 3,
  double probeHz = 1000,
  double maskerAmp = 0,
  double toneSeconds = 0.3,
  double gapSeconds = 0.25,
  double forwardGapMs = 0,
  int seed = 1,
}) {
  final ref = maskerAmp > 0 ? maskerAmp : 0.25;
  final toneAmp = ampFromDb(ref, toneLevelDb);
  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(gapSeconds));
    final hasTone = i == targetInterval;
    if (maskerAmp > 0 && forwardGapMs > 0) {
      // Forward masking: masker, silent gap, then the probe (target only).
      final masker =
          whiteNoise(seconds: toneSeconds, amp: maskerAmp, seed: seed + i);
      final gap = silence(forwardGapMs / 1000.0);
      final probe = hasTone
          ? tone(seconds: toneSeconds * 0.5, freqHz: probeHz, amp: toneAmp)
          : silence(toneSeconds * 0.5);
      parts.add(concat(<List<double>>[masker, gap, probe]));
    } else {
      // Simultaneous masking or quiet detection: sum masker + probe.
      final masker = maskerAmp > 0
          ? whiteNoise(seconds: toneSeconds, amp: maskerAmp, seed: seed + i)
          : silence(toneSeconds);
      final probe = hasTone
          ? tone(seconds: toneSeconds, freqHz: probeHz, amp: toneAmp)
          : const <double>[];
      parts.add(<double>[
        for (var k = 0; k < masker.length; k++)
          masker[k] + (k < probe.length ? probe[k] : 0.0),
      ]);
    }
  }
  return _limitPeak(concat(parts));
}

/// Rhythm odd-one-out stimulus: [intervals] isochronous click trains; the
/// [targetInterval] has one inter-onset interval lengthened by [deltaMs].
/// Larger [deltaMs] is easier.
List<double> rhythmStimulus({
  required int targetInterval,
  required double deltaMs,
  int intervals = 3,
  double baseIoiMs = 250,
  int beats = 5,
  double clickHz = 1200,
  double clickSeconds = 0.03,
  double betweenIntervalsSeconds = 0.35,
}) {
  List<double> pattern(bool deviant) {
    final parts = <List<double>>[];
    for (var b = 0; b < beats; b++) {
      parts.add(tone(seconds: clickSeconds, freqHz: clickHz, amp: 0.3));
      if (b < beats - 1) {
        var ioiMs = baseIoiMs;
        if (deviant && b == beats ~/ 2) ioiMs += deltaMs;
        final restSeconds = (ioiMs / 1000.0) - clickSeconds;
        parts.add(silence(restSeconds > 0 ? restSeconds : 0.01));
      }
    }
    return concat(parts);
  }

  final parts = <List<double>>[];
  for (var i = 0; i < intervals; i++) {
    if (i > 0) parts.add(silence(betweenIntervalsSeconds));
    parts.add(pattern(i == targetInterval));
  }
  return _limitPeak(concat(parts));
}

/// Diatonic C-major notes (one octave) used by the melodic sequence tasks.
const Map<String, double> kMelodyNotesHz = <String, double>{
  'C': 261.63,
  'D': 293.66,
  'E': 329.63,
  'F': 349.23,
  'G': 392.00,
};

/// Builds an auditory note sequence: one pure tone per note name in order,
/// separated by short gaps. Used by the melodic sequence-recall tasks.
List<double> noteSequenceStimulus(
  List<String> names, {
  double noteSeconds = 0.35,
  double gapSeconds = 0.12,
  double amp = 0.22,
  Map<String, double> notes = kMelodyNotesHz,
  int sampleRate = kSampleRate,
}) {
  final parts = <List<double>>[];
  for (var i = 0; i < names.length; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    final hz = notes[names[i]] ?? 440.0;
    parts.add(
      tone(seconds: noteSeconds, freqHz: hz, amp: amp, sampleRate: sampleRate),
    );
  }
  return _limitPeak(concat(parts));
}
