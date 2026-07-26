/// Headless checks for the Tier-2 (27 Jul 2026) additions: TMTF multi-rate
/// session, spectral ripple + IRN synthesis, rhythm-change melodies, beat
/// tapping, the stimulus level envelope and the trial flag helper.
library;

import 'dart:io';
import 'dart:math' as math;

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/music_perception.dart';
import '../../lib/core/protocol_engine.dart';
import '../../lib/core/psychoacoustics.dart';
import '../../lib/core/session_summary.dart';

int _failures = 0;

void check(String name, bool condition) {
  if (condition) {
    stdout.writeln('PASS $name');
  } else {
    _failures++;
    stdout.writeln('FAIL $name');
  }
}

void main() {
  // --- TMTF session ---
  {
    final s = TmtfSession();
    check('TMTF starts at the lowest rate', s.currentRateHz == 4);
    // Simulated listener: hears modulation at depth ≥ −16 dB at every rate.
    var guard = 0;
    final rng = math.Random(3);
    while (!s.isComplete && guard < 600) {
      final target = rng.nextInt(3);
      final heard = s.currentDepthDb >= -16;
      s.submit(target, heard ? target : (target + 1) % 3);
      guard++;
    }
    check('TMTF completes all rates', s.isComplete);
    var allNear = true;
    for (final r in kTmtfRatesHz) {
      final t = s.thresholdFor(r);
      if (t == null || (t - -16).abs() > 6) allNear = false;
    }
    check('TMTF thresholds near the simulated −16 dB edge', allNear);
    final m = summarizeSession(s)!;
    check('TMTF metric: per-rate sub-scores + mean, lower is better',
        m.sub!.containsKey('r4') &&
            m.sub!.containsKey('r512') &&
            m.value != null &&
            m.higherIsBetter == false);
    final seq = buildTmtfSequence(
        targetInterval: 1, depthDb: -6, rateHz: 8, seed: 2);
    final expectedLen = ((0.5 * 3 + 0.25 * 2) * kSampleRate).round();
    check('TMTF sequence = 3 intervals + 2 gaps',
        (seq.length - expectedLen).abs() <= 3);
  }

  // --- Spectral ripple ---
  {
    final a = rippleStimulus(periodOct: 0.5, ripplePhase: 0, seed: 5);
    final b = rippleStimulus(periodOct: 0.5, ripplePhase: 0, seed: 5);
    final inv = rippleStimulus(periodOct: 0.5, ripplePhase: math.pi, seed: 5);
    check('ripple deterministic for a seed', () {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }());
    var diff = 0.0;
    for (var i = 0; i < a.length; i++) {
      diff += (a[i] - inv[i]).abs();
    }
    check('phase-inverted ripple differs from standard',
        diff / a.length > 0.01);
    check('ripple peak-normalized within amp',
        a.every((v) => v.abs() <= 0.5 + 1e-9));
    check('ripple track: 1 oct start down to 0.1 oct min',
        rippleTrack().value == 1.0 && rippleTrack().min == 0.1);
    final odd = buildRippleOddballSequence(
        targetInterval: 2, periodOct: 0.8, seed: 4);
    check('ripple oddball assembles 3 intervals', odd.length > a.length * 2);
  }

  // --- IRN ---
  {
    final plain = irnStimulus(iterations: 1, seed: 9);
    final strong = irnStimulus(iterations: 16, seed: 9);
    check('IRN RMS matched across iterations',
        (rms(strong) - rms(plain)).abs() / rms(plain) < 0.05);
    // Pitch strength = normalized autocorrelation at the delay lag.
    double acAtDelay(List<double> x, int lag) {
      var num = 0.0, den = 0.0;
      for (var i = lag; i < x.length; i++) {
        num += x[i] * x[i - lag];
        den += x[i] * x[i];
      }
      return den == 0 ? 0 : num / den;
    }

    final lag = (kSampleRate / 125).round();
    check('IRN regularity grows with iterations',
        acAtDelay(strong, lag) > acAtDelay(plain, lag) + 0.2);
    check('IRN track adapts iterations 8 → min 1',
        irnTrack().value == 8 && irnTrack().min == 1);
    final seq = buildIrnSequence(targetInterval: 0, iterations: 7.6, seed: 3);
    check('IRN 2AFC sequence assembles', seq.length > plain.length * 2);
  }

  // --- Rhythm change ---
  {
    final same = buildRhythmChangeSequence(
        targetInterval: 0, displaceMs: 0, seed: 11);
    final same2 = buildRhythmChangeSequence(
        targetInterval: 0, displaceMs: 0, seed: 11);
    check('rhythm sequence deterministic', same.length == same2.length);
    final shifted = buildRhythmChangeSequence(
        targetInterval: 0, displaceMs: 120, seed: 11);
    var diff = 0.0;
    final n = math.min(same.length, shifted.length);
    for (var i = 0; i < n; i++) {
      diff += (same[i] - shifted[i]).abs();
    }
    check('displaced rhythm differs from even rendition',
        diff / n > 1e-4);
    check('rhythm track: 120 ms start, 5 ms floor',
        rhythmChangeTrack().value == 120 && rhythmChangeTrack().min == 5);
  }

  // --- Beat tapping ---
  {
    final s = BeatTapSession(bpm: 120, beats: 8, leadInBeats: 2);
    final interval = s.beatIntervalMs; // 500 ms
    check('beat interval from bpm', interval == 500);
    final track = buildBeatTrack(bpm: 120, beats: 8, leadInBeats: 2);
    check('beat track length = (leadIn+beats) × interval',
        (track.length - (10 * 0.5 * kSampleRate).round()).abs() <= 2);
    // Perfect taps on every scored beat.
    for (var b = 2; b < 10; b++) {
      s.addTap(b * interval);
    }
    check('perfect taps: SD 0, hit rate 1, tempo 1',
        s.sdAsynchronyMs! < 1e-9 &&
            s.hitRate == 1.0 &&
            (s.tempoRatio! - 1).abs() < 1e-9);
    // Constant +40 ms latency shifts the mean but not the SD.
    final s2 = BeatTapSession(bpm: 120, beats: 8, leadInBeats: 2);
    for (var b = 2; b < 10; b++) {
      s2.addTap(b * interval + 40);
    }
    check('constant latency: mean 40, SD ~0',
        (s2.meanAsynchronyMs! - 40).abs() < 1e-9 &&
            s2.sdAsynchronyMs! < 1e-9);
    // Lead-in taps are ignored.
    final s3 = BeatTapSession(bpm: 120, beats: 8, leadInBeats: 2);
    s3.addTap(0);
    s3.addTap(interval * 0.4);
    check('count-in taps are not scored', s3.scoredTapCount == 0);
    check('beat records carry asynchrony parameters',
        s2.records.length == 8 &&
            s2.records.first.parameters['asynchrony_ms'] == 40.0);
    final m = summarizeSession(s2)!;
    check('beat metric: SD headline with hit/tempo subs',
        m.unit == 'ms' &&
            m.sub!['hit_pct'] == 100 &&
            m.higherIsBetter == false);
  }

  // --- Level envelope + trial flag ---
  {
    final env = levelEnvelope(
        tone(seconds: 0.3, freqHz: 440, amp: 0.4), frames: 20);
    check('level envelope: 20 frames, peak-normalized to 1',
        env.length == 20 &&
            (env.reduce(math.max) - 1).abs() < 1e-9 &&
            env.every((v) => v >= 0 && v <= 1));
    check('level envelope of silence is empty-safe',
        levelEnvelope(const <double>[]).isEmpty);

    final records = <TrialRecord>[
      TrialRecord(target: 'a', response: 'b', correct: false, latencyMs: 5),
    ];
    check('flagLastTrial marks the record and preserves fields', () {
      final ok = flagLastTrial(records);
      final r = records.single;
      return ok &&
          lastTrialFlagged(records) &&
          r.target == 'a' &&
          r.response == 'b' &&
          r.correct == false &&
          r.parameters['flagged'] == true;
    }());
    check('flagLastTrial refuses empty lists',
        flagLastTrial(<TrialRecord>[]) == false &&
            lastTrialFlagged(<TrialRecord>[]) == false);
  }

  stdout.writeln(_failures == 0
      ? 'ALL PSYCHOACOUSTICS CHECKS PASSED'
      : '$_failures PSYCHOACOUSTICS CHECKS FAILED');
  if (_failures > 0) exit(1);
}
