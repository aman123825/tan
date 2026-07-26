/// Music-perception additions (pure Dart, Flutter-free): rhythm-change
/// detection in melodies and beat-tapping (production) scoring.
///
/// * **Rhythm change (E6)** — two renditions of the SAME familiar melody
///   play; one is evenly timed, the other has one note's onset displaced by
///   an adaptive number of milliseconds (total duration preserved). The
///   listener picks the uneven one; 2-down/1-up converges on the timing JND
///   within a melodic context.
/// * **Beat tapping (E11)** — a production task: the listener taps along
///   with an isochronous click track; scoring reports the variability (SD)
///   of tap-to-beat asynchronies — the standard sensorimotor-synchronization
///   consistency measure (Repp, 2005) — plus mean asynchrony, hit rate and
///   tempo matching. Absolute asynchrony includes device audio latency, so
///   the SD (consistency) is the headline.
///
/// SAFETY: adaptation moves the onset displacement only; nothing here can
/// change master volume. Deterministic for a given seed.
library;

import 'dart:math';

import 'audio/pcm_synth.dart';
import 'audio/timbre.dart';
import 'protocol_engine.dart';

// ---------------------------------------------------------------------------
// Rhythm change in melody (E6)
// ---------------------------------------------------------------------------

/// Onset-displacement staircase (ms): 120 start, Levitt-reduced 30 → 10 ms.
AdaptiveTrack rhythmChangeTrack() => AdaptiveTrack(
      value: 120,
      min: 5,
      max: 200,
      step: 30,
      stepFactor: 0.5,
      stepReductionReversals: 2,
      minStep: 10,
    );

/// Renders [melodyId] with per-note onset gaps. [gapsSeconds] has one entry
/// per note (the silence BEFORE that note; first entry usually 0).
List<double> _melodyWithGaps(
  String melodyId,
  List<double> gapsSeconds, {
  double noteSeconds = 0.3,
  int sampleRate = kSampleRate,
}) {
  final offsets = kMelodies[melodyId] ?? const <int>[0];
  final parts = <List<double>>[];
  for (var i = 0; i < offsets.length; i++) {
    final gap = i < gapsSeconds.length ? gapsSeconds[i] : 0.0;
    if (gap > 0) parts.add(silence(gap, sampleRate));
    parts.add(instrumentTone(
      instrument: 'flute',
      freqHz: shiftSemitones(261.63, offsets[i].toDouble()),
      seconds: noteSeconds,
      sampleRate: sampleRate,
    ));
  }
  return concat(parts);
}

/// Builds one 2AFC rhythm-change trial: both intervals are the same seeded
/// melody; the target has one interior note delayed by [displaceMs], with
/// the following gap shrunk (clamped at zero) so the change is in the
/// timing pattern, not the notes.
List<double> buildRhythmChangeSequence({
  required int targetInterval,
  required double displaceMs,
  required int seed,
  double gapSeconds = 0.5,
  int sampleRate = kSampleRate,
}) {
  final rng = Random(seed);
  final melodyId = kMelodyIds[rng.nextInt(kMelodyIds.length)];
  final noteCount = (kMelodies[melodyId] ?? const <int>[0]).length;
  // Displace an interior note so the change is never just at the edges.
  final noteIndex = 1 + rng.nextInt(max(1, noteCount - 2));

  const evenGap = 0.06;
  final even = List<double>.filled(noteCount, evenGap)..[0] = 0;
  final shift = (displaceMs / 1000).clamp(0.0, 0.25);
  final uneven = List<double>.of(even);
  uneven[noteIndex] = evenGap + shift;
  if (noteIndex + 1 < uneven.length) {
    uneven[noteIndex + 1] = max(0.0, evenGap - shift);
  }

  final parts = <List<double>>[];
  for (var i = 0; i < 2; i++) {
    if (i > 0) parts.add(silence(gapSeconds, sampleRate));
    parts.add(_melodyWithGaps(
      melodyId,
      i == targetInterval ? uneven : even,
      sampleRate: sampleRate,
    ));
  }
  return concat(parts);
}

// ---------------------------------------------------------------------------
// Beat tapping (E11)
// ---------------------------------------------------------------------------

/// A short click (1 kHz tone burst) marking one beat.
List<double> beatClick({
  double seconds = 0.03,
  double amp = 0.3,
  int sampleRate = kSampleRate,
}) =>
    tone(seconds: seconds, freqHz: 1000, amp: amp, fadeMs: 4,
        sampleRate: sampleRate);

/// Builds the full click track: [leadInBeats] + [beats] clicks at [bpm].
List<double> buildBeatTrack({
  required double bpm,
  required int beats,
  int leadInBeats = 4,
  int sampleRate = kSampleRate,
}) {
  final interval = 60.0 / bpm;
  final click = beatClick(sampleRate: sampleRate);
  final total = leadInBeats + beats;
  final n = (total * interval * sampleRate).round();
  final out = List<double>.filled(n, 0);
  for (var b = 0; b < total; b++) {
    final start = (b * interval * sampleRate).round();
    for (var i = 0; i < click.length && start + i < n; i++) {
      out[start + i] += click[i];
    }
  }
  return out;
}

/// Scores a beat-tapping run. Taps arrive as milliseconds since audio onset;
/// the first [leadInBeats] beats are a listen-only count-in (taps there are
/// ignored). Each remaining tap is matched to its nearest beat.
class BeatTapSession {
  BeatTapSession({
    this.moduleId = 'music',
    this.groupId = 'beat_tapping',
    this.bpm = 90,
    this.beats = 24,
    this.leadInBeats = 4,
  });

  final String moduleId;
  final String groupId;
  final double bpm;
  final int beats;
  final int leadInBeats;

  final List<double> tapTimesMs = <double>[];

  double get beatIntervalMs => 60000.0 / bpm;

  /// Duration of the whole click track (count-in + scored beats).
  double get totalDurationMs => (leadInBeats + beats) * beatIntervalMs;

  void addTap(double msSinceAudioStart) => tapTimesMs.add(msSinceAudioStart);

  /// (tap, asynchrony) pairs for taps in the scored region, each against its
  /// nearest beat.
  List<double> get asynchroniesMs {
    final startMs = leadInBeats * beatIntervalMs;
    final out = <double>[];
    for (final t in tapTimesMs) {
      if (t < startMs - beatIntervalMs / 2) continue;
      final beatNumber = (t / beatIntervalMs).round();
      if (beatNumber < leadInBeats ||
          beatNumber >= leadInBeats + beats) {
        continue;
      }
      out.add(t - beatNumber * beatIntervalMs);
    }
    return out;
  }

  int get scoredTapCount => asynchroniesMs.length;

  /// Mean signed asynchrony (ms; negative = anticipating the beat). Includes
  /// device audio latency — interpret relatively.
  double? get meanAsynchronyMs {
    final a = asynchroniesMs;
    if (a.isEmpty) return null;
    return a.reduce((x, y) => x + y) / a.length;
  }

  /// SD of asynchronies (ms) — tapping CONSISTENCY, the headline (latency
  /// cancels out of a spread measure).
  double? get sdAsynchronyMs {
    final a = asynchroniesMs;
    if (a.length < 2) return null;
    final m = a.reduce((x, y) => x + y) / a.length;
    final v =
        a.map((x) => (x - m) * (x - m)).reduce((x, y) => x + y) / a.length;
    return sqrt(v);
  }

  /// Fraction of scored beats that received a tap within ±25% of the beat
  /// interval (each beat counted once).
  double get hitRate {
    if (beats == 0) return 0;
    final window = beatIntervalMs * 0.25;
    final hit = <int>{};
    final startBeat = leadInBeats;
    for (final t in tapTimesMs) {
      final beatNumber = (t / beatIntervalMs).round();
      if (beatNumber < startBeat || beatNumber >= startBeat + beats) continue;
      if ((t - beatNumber * beatIntervalMs).abs() <= window) {
        hit.add(beatNumber);
      }
    }
    return hit.length / beats;
  }

  /// Mean inter-tap interval / beat interval (1.0 = perfect tempo match).
  double? get tempoRatio {
    if (tapTimesMs.length < 3) return null;
    final sorted = List<double>.of(tapTimesMs)..sort();
    final itis = <double>[
      for (var i = 1; i < sorted.length; i++) sorted[i] - sorted[i - 1],
    ];
    final mean = itis.reduce((x, y) => x + y) / itis.length;
    return mean / beatIntervalMs;
  }

  /// Per-tap event records for persistence (one record per scored tap).
  List<TrialRecord> get records => <TrialRecord>[
        for (final a in asynchroniesMs)
          TrialRecord(
            target: 'beat',
            response: 'tap',
            correct: a.abs() <= beatIntervalMs * 0.25,
            latencyMs: a.round(),
            parameters: <String, Object?>{
              'asynchrony_ms': double.parse(a.toStringAsFixed(1)),
              'bpm': bpm,
            },
          ),
      ];
}
