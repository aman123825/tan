/// LiSN-S (Listening in Spatialized Noise – Sentences) diagnostic logic
/// (pure Dart).
///
/// A target sentence is presented at 0° azimuth (centre) while a competing
/// "story" masker is presented in one of four spatial/talker configurations.
/// An adaptive SNR staircase (2-down/1-up) finds the speech-reception
/// threshold (SRT) for each of the four conditions; three *advantage* measures
/// (talker, spatial, total) are then derived from the four SRTs — the LiSN-S
/// pattern of interest (Cameron & Dillon, 2007, JAAA 18:571–581).
///
/// SAFETY: adaptation moves only the speech-to-noise ratio (dB) — never master
/// volume. The DSP (spatialisation, pitch shift, SNR mix) is Flutter-free and
/// verified headlessly; the stimuli are labelled demonstrations on uncalibrated
/// audio, NOT validated clinical LiSN-S material.
library;

import 'dart:math';
import 'dart:typed_data';

import 'audio/pcm_synth.dart';
import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;
import 'training/spatial.dart' show spatialize;

/// The four LiSN-S conditions, ordered hardest → easiest.
///
/// The target is always centred (0°). Conditions vary the masker's *talker*
/// (same voice vs a pitch-shifted "different" voice) and its *spatial* position
/// (co-located at 0° vs separated to ±90°).
enum LisnsCondition {
  /// Same voice, co-located (0°) — the hardest, low-cue condition.
  sameTalker0,

  /// Same voice, spatially separated (±90°).
  sameTalker90,

  /// Different voice, co-located (0°).
  diffTalker0,

  /// Different voice, spatially separated (±90°) — the easiest, high-cue.
  diffTalker90,
}

/// Presentation + DSP flags for each [LisnsCondition].
extension LisnsConditionInfo on LisnsCondition {
  /// Short display label.
  String get label => switch (this) {
        LisnsCondition.sameTalker0 => 'Same voice · 0°',
        LisnsCondition.sameTalker90 => 'Same voice · ±90°',
        LisnsCondition.diffTalker0 => 'Diff voice · 0°',
        LisnsCondition.diffTalker90 => 'Diff voice · ±90°',
      };

  /// Stable id used in stored trial parameters.
  String get id => switch (this) {
        LisnsCondition.sameTalker0 => 'SV0',
        LisnsCondition.sameTalker90 => 'SV90',
        LisnsCondition.diffTalker0 => 'DV0',
        LisnsCondition.diffTalker90 => 'DV90',
      };

  /// Whether the masker is spatially separated to ±90° (else co-located 0°).
  bool get spatial =>
      this == LisnsCondition.sameTalker90 ||
      this == LisnsCondition.diffTalker90;

  /// Whether the masker is a different (pitch-shifted) talker.
  bool get differentTalker =>
      this == LisnsCondition.diffTalker0 ||
      this == LisnsCondition.diffTalker90;
}

/// A target sentence with its shipped demonstration audio asset. Text matches
/// the audio so typed responses can be scored by word accuracy.
class LisnsSentence {
  const LisnsSentence(this.id, this.text);

  final String id;
  final String text;

  /// Path to the shipped demonstration WAV for this sentence.
  String get assetPath => 'assets/stimuli/sentences/$id.wav';
}

/// The ten target sentences shipped as demonstration audio (`s1`–`s10`).
const List<LisnsSentence> kLisnsTargetSentences = <LisnsSentence>[
  LisnsSentence('s1', 'the boy runs home'),
  LisnsSentence('s2', 'she reads a book'),
  LisnsSentence('s3', 'the dog is black'),
  LisnsSentence('s4', 'we eat rice today'),
  LisnsSentence('s5', 'open the red door'),
  LisnsSentence('s6', 'birds fly very high'),
  LisnsSentence('s7', 'he drinks cold water'),
  LisnsSentence('s8', 'the sun is bright'),
  LisnsSentence('s9', 'put the cup down'),
  LisnsSentence('s10', 'they walk to school'),
];

/// Twenty simple sentences used to build the competing "story" masker. These
/// are synthesised (speech-like placeholder), so they need no audio assets and
/// can be freely pitch-shifted for the different-talker conditions.
const List<String> kLisnsMaskerStoryPool = <String>[
  'the cat sat on the mat',
  'a bird flew over the hill',
  'we went to the market',
  'the rain fell all day',
  'she painted the old fence',
  'they played in the park',
  'the train left on time',
  'he found a shiny coin',
  'the soup was very hot',
  'the moon rose slowly',
  'children ran down the lane',
  'the kettle began to sing',
  'a dog barked at the gate',
  'the leaves turned gold',
  'we baked a round cake',
  'the river flows to the sea',
  'she wrote a long letter',
  'the clock struck twelve',
  'birds nested in the tree',
  'the wind shook the door',
];

/// Pitch ratio applied to the masker for the different-talker conditions
/// (≈ +3 semitones; deterministic resample). > 1 raises pitch.
const double kLisnsTalkerShiftRatio = 1.18;

/// Builds a mono competing-"story" masker at least [seconds] long by
/// concatenating speech-like placeholders of sentences drawn from
/// [kLisnsMaskerStoryPool]. Deterministic for a given [seed].
List<double> lisnsMaskerStory({
  int seed = 0,
  double seconds = 3.0,
  int sampleRate = kSampleRate,
}) {
  final rng = Random(seed);
  final need = (seconds * sampleRate).round();
  final out = <double>[];
  while (out.length < need) {
    final s = kLisnsMaskerStoryPool[rng.nextInt(kLisnsMaskerStoryPool.length)];
    out.addAll(_sentencePlaceholder(s, rng, sampleRate));
  }
  return out.sublist(0, need);
}

/// One amplitude-shaped tone burst per word (a labelled demonstration proxy —
/// NOT recorded speech), with a per-sentence base pitch so the masker reads as
/// continuous "speech".
List<double> _sentencePlaceholder(String sentence, Random rng, int sampleRate) {
  final words = sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final basePitch = 130.0 + rng.nextInt(90); // 130–220 Hz "voice"
  final out = <double>[];
  for (final w in words) {
    final durSec = (0.11 + w.length * 0.018).clamp(0.10, 0.28);
    final f = basePitch * (0.85 + rng.nextDouble() * 0.5);
    final fundamental =
        tone(seconds: durSec, freqHz: f, amp: 0.22, sampleRate: sampleRate);
    final harmonic =
        tone(seconds: durSec, freqHz: f * 2, amp: 0.06, sampleRate: sampleRate);
    for (var j = 0; j < fundamental.length; j++) {
      out.add(fundamental[j] + (j < harmonic.length ? harmonic[j] : 0.0));
    }
    out.addAll(silence(0.04, sampleRate)); // brief inter-word gap
  }
  return out;
}

/// Naive linear-interpolation resample by [ratio] (> 1 shortens → raises
/// pitch). Used to synthesise the "different talker" masker by changing its
/// playback frequency.
List<double> _resample(List<double> input, double ratio) {
  if (input.isEmpty || ratio <= 0) return List<double>.of(input);
  final outLen = (input.length / ratio).floor();
  final out = List<double>.filled(outLen, 0.0);
  for (var i = 0; i < outLen; i++) {
    final pos = i * ratio;
    final i0 = pos.floor();
    final i1 = min(i0 + 1, input.length - 1);
    final frac = pos - i0;
    out[i] = input[i0] * (1 - frac) + input[i1] * frac;
  }
  return out;
}

/// Loops or truncates [samples] to exactly [length].
List<double> _fit(List<double> samples, int length) {
  if (samples.isEmpty) return List<double>.filled(length, 0.0);
  return List<double>.generate(length, (i) => samples[i % samples.length]);
}

/// Builds a stereo LiSN-S stimulus: [target] centred (0°) plus [masker] placed
/// per [condition] and mixed at [snrDb] (target = signal). Returns a 16-bit
/// stereo WAV.
///
/// SAFETY: [snrDb] scales the masker only; the target level is never boosted on
/// wrong answers and master volume is untouched.
Uint8List buildLisnsStimulus({
  required List<double> target,
  required List<double> masker,
  required LisnsCondition condition,
  required double snrDb,
  int sampleRate = kSampleRate,
}) {
  final n = target.length;
  // Different-talker: pitch-shift the masker by changing its playback rate.
  var m = condition.differentTalker
      ? _resample(masker, kLisnsTalkerShiftRatio)
      : List<double>.of(masker);
  m = _fit(m, n);

  // Scale the masker to the requested SNR relative to the target.
  final sRms = rms(target);
  final nRms = rms(m);
  final gain =
      (sRms <= 0 || nRms <= 0) ? 0.0 : (sRms / pow(10, snrDb / 20)) / nRms;
  final scaled = <double>[for (final x in m) x * gain];

  final left = List<double>.filled(n, 0.0);
  final right = List<double>.filled(n, 0.0);

  if (condition.spatial) {
    // Two competing streams at ±90° (symmetric), each ~0.7× so the combined
    // masker energy stays close to the co-located case.
    final atRight = spatialize(
        <double>[for (final x in scaled) x * 0.7], 90,
        sampleRate: sampleRate);
    final atLeft = spatialize(
        <double>[for (final x in scaled) x * 0.7], -90,
        sampleRate: sampleRate);
    for (var i = 0; i < n; i++) {
      left[i] = target[i] + atLeft.left[i] + atRight.left[i];
      right[i] = target[i] + atLeft.right[i] + atRight.right[i];
    }
  } else {
    // Co-located at 0°: masker is diotic (identical in both ears).
    for (var i = 0; i < n; i++) {
      left[i] = target[i] + scaled[i];
      right[i] = target[i] + scaled[i];
    }
  }
  _peakNormalizeStereo(left, right, 0.9);
  return encodeWavStereo16(left, right, sampleRate: sampleRate);
}

void _peakNormalizeStereo(List<double> left, List<double> right, double peak) {
  var mx = 0.0;
  for (final x in left) {
    if (x.abs() > mx) mx = x.abs();
  }
  for (final x in right) {
    if (x.abs() > mx) mx = x.abs();
  }
  if (mx > peak && mx > 0) {
    final k = peak / mx;
    for (var i = 0; i < left.length; i++) {
      left[i] *= k;
    }
    for (var i = 0; i < right.length; i++) {
      right[i] *= k;
    }
  }
}

/// Word-accuracy fraction at or above which a LiSN-S trial counts as "correct"
/// for the staircase (majority of key words repeated).
const double kLisnsCorrectThreshold = 0.5;

/// Sequences and scores an adaptive LiSN-S run across the four conditions.
///
/// Each condition owns its own SNR staircase; trials are interleaved
/// round-robin so no single condition dominates fatigue. SRTs and the three
/// advantage measures are derived once the run completes.
class LisnsSession {
  LisnsSession({
    this.moduleId = 'noise',
    this.groupId = 'lisn_s',
    this.maxTrialsPerCondition = 5,
    this.mode = ProtocolMode.test,
    double startSnrDb = 4,
    double stepDb = 2,
  })  : _tracks = {
          for (final c in LisnsCondition.values)
            c: AdaptiveTrack.snr(start: startSnrDb, step: stepDb),
        },
        _presented = {for (final c in LisnsCondition.values) c: <double>[]};

  final String moduleId;
  final String groupId;
  final int maxTrialsPerCondition;
  final ProtocolMode mode;

  final Map<LisnsCondition, AdaptiveTrack> _tracks;
  final Map<LisnsCondition, List<double>> _presented;
  final Map<LisnsCondition, int> _completed = {
    for (final c in LisnsCondition.values) c: 0,
  };

  final List<TrialRecord> records = <TrialRecord>[];

  /// Feedback is never shown during this (locked) diagnostic measurement.
  bool get showsFeedback => mode == ProtocolMode.training;

  int get completedTrials => records.length;
  int get totalTrials => maxTrialsPerCondition * LisnsCondition.values.length;
  int get trialNumber => records.length + 1;

  bool get isComplete =>
      LisnsCondition.values.every((c) => _completed[c]! >= maxTrialsPerCondition);

  /// The condition for the next trial: the least-completed unfinished one
  /// (deterministic round-robin by enum order on ties).
  LisnsCondition get currentCondition {
    LisnsCondition? best;
    for (final c in LisnsCondition.values) {
      if (_completed[c]! >= maxTrialsPerCondition) continue;
      if (best == null || _completed[c]! < _completed[best]!) best = c;
    }
    return best ?? LisnsCondition.sameTalker0;
  }

  /// SNR (dB) at which the next trial for [condition] will be presented.
  double currentSnrDb(LisnsCondition condition) => _tracks[condition]!.value;

  int completedFor(LisnsCondition condition) => _completed[condition]!;

  /// Records a scored response for [condition] and advances that condition's
  /// staircase. [scoreFraction] is the word-accuracy in [0, 1]; a trial is
  /// "correct" (task gets harder) when it meets [kLisnsCorrectThreshold].
  bool submit(
    LisnsCondition condition, {
    required String target,
    required String response,
    required double scoreFraction,
    required int latencyMs,
    int replays = 0,
  }) {
    final track = _tracks[condition]!;
    final snr = track.value;
    final correct = scoreFraction >= kLisnsCorrectThreshold;
    _presented[condition]!.add(snr);
    records.add(TrialRecord(
      target: target,
      response: response,
      correct: correct,
      latencyMs: latencyMs,
      replays: replays,
      parameters: <String, Object?>{
        'condition': condition.id,
        'snr_db': snr,
        'score': scoreFraction,
      },
    ));
    track.submit(correct);
    _completed[condition] = _completed[condition]! + 1;
    return correct;
  }

  /// Estimated SRT (dB) for [condition]: the reversal-averaged staircase
  /// threshold, falling back to the mean presented SNR (short demo runs rarely
  /// accrue the full reversal count).
  double? srtFor(LisnsCondition condition) {
    final t = _tracks[condition]!.threshold;
    if (t != null) return t;
    final pres = _presented[condition]!;
    if (pres.isEmpty) return null;
    return pres.reduce((a, b) => a + b) / pres.length;
  }

  /// Standard deviation of the reversals averaged for [condition]'s SRT (a
  /// research-only precision indicator), or null if too few reversals.
  double? srtSdFor(LisnsCondition condition) => _tracks[condition]!.thresholdSd;

  double _srtOr(LisnsCondition c) => srtFor(c) ?? 0;

  /// Talker advantage (dB): benefit of a different masker voice at 0°
  /// = SRT(same-voice 0°) − SRT(different-voice 0°). Positive = benefit.
  double get talkerAdvantage =>
      _srtOr(LisnsCondition.sameTalker0) - _srtOr(LisnsCondition.diffTalker0);

  /// Spatial advantage (dB): benefit of ±90° separation with the same voice
  /// = SRT(same-voice 0°) − SRT(same-voice ±90°). Positive = benefit.
  double get spatialAdvantage =>
      _srtOr(LisnsCondition.sameTalker0) - _srtOr(LisnsCondition.sameTalker90);

  /// Total advantage (dB): combined talker + spatial benefit
  /// = SRT(same-voice 0°) − SRT(different-voice ±90°). Positive = benefit.
  double get totalAdvantage =>
      _srtOr(LisnsCondition.sameTalker0) - _srtOr(LisnsCondition.diffTalker90);
}
