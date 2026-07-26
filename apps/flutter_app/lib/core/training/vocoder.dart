/// Noise-vocoded speech (cochlear-implant simulation) — pure Dart DSP + an
/// adaptive channel-count session controller.
///
/// A channel vocoder degrades speech into [channels] spectral bands:
///   1. split the signal into N log-spaced frequency bands (bandpass biquads);
///   2. extract each band's amplitude envelope (half-wave rectify + 50 Hz
///      low-pass);
///   3. modulate a band-limited white-noise carrier with that envelope;
///   4. sum the modulated bands.
/// Fewer channels ⇒ coarser spectral detail ⇒ a more degraded, more
/// "cochlear-implant-like" sound. This is an illustrative demonstration on
/// uncalibrated audio, NOT a validated CI simulation or clinical stimulus.
///
/// SAFETY: the adaptive staircase moves only the *channel count* (spectral
/// resolution) — never master volume. The layer is Flutter-free so it can be
/// unit-tested headlessly (see `test/final_features_test.dart`).
library;

import 'dart:math';

import '../audio/pcm_synth.dart' show kSampleRate, rms;
import '../speech_in_noise.dart' show FourAlternativeTrial, ProtocolMode;
import '../protocol_engine.dart';

/// Channel-count ladder from most degraded (4) to near-normal (32).
const List<int> kVocoderChannelLadder = <int>[4, 8, 16, 32];

/// Where training begins (a moderately degraded 16-channel vocoder).
const int kVocoderStartChannels = 16;

// ---------------------------------------------------------------------------
// DSP
// ---------------------------------------------------------------------------

/// Direct-form-I biquad application (shared by band-pass / low-pass helpers).
List<double> _applyBiquad(
  List<double> x,
  double b0,
  double b1,
  double b2,
  double a0,
  double a1,
  double a2,
) {
  final out = List<double>.filled(x.length, 0);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final x0 = x[i];
    final y0 = (b0 / a0) * x0 +
        (b1 / a0) * x1 +
        (b2 / a0) * x2 -
        (a1 / a0) * y1 -
        (a2 / a0) * y2;
    out[i] = y0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }
  return out;
}

/// Second-order constant-peak-gain band-pass biquad (RBJ cookbook) centred on
/// [centerHz] with quality [q]. Returns a new buffer the same length as input.
List<double> bandPassBiquad(
  List<double> samples,
  double centerHz,
  double q, {
  int sampleRate = kSampleRate,
}) {
  if (samples.isEmpty) return List<double>.of(samples);
  if (centerHz <= 0 || centerHz >= sampleRate / 2 || q <= 0) {
    return List<double>.of(samples);
  }
  final w0 = 2 * pi * centerHz / sampleRate;
  final cosw0 = cos(w0);
  final sinw0 = sin(w0);
  final alpha = sinw0 / (2 * q);

  // Constant 0 dB peak-gain band-pass (b0 = alpha, b2 = -alpha).
  final b0 = alpha;
  const b1 = 0.0;
  final b2 = -alpha;
  final a0 = 1 + alpha;
  final a1 = -2 * cosw0;
  final a2 = 1 - alpha;
  return _applyBiquad(samples, b0, b1, b2, a0, a1, a2);
}

/// Second-order (Butterworth-Q) low-pass biquad at [cutoffHz]. Used for
/// envelope smoothing. Returns a new buffer the same length as input.
List<double> _lowPass(
  List<double> samples,
  double cutoffHz, {
  int sampleRate = kSampleRate,
  double q = 0.70710678,
}) {
  if (samples.isEmpty) return List<double>.of(samples);
  if (cutoffHz <= 0 || cutoffHz >= sampleRate / 2) {
    return List<double>.of(samples);
  }
  final w0 = 2 * pi * cutoffHz / sampleRate;
  final cosw0 = cos(w0);
  final sinw0 = sin(w0);
  final alpha = sinw0 / (2 * q);

  final b0 = (1 - cosw0) / 2;
  final b1 = 1 - cosw0;
  final b2 = (1 - cosw0) / 2;
  final a0 = 1 + alpha;
  final a1 = -2 * cosw0;
  final a2 = 1 - alpha;
  return _applyBiquad(samples, b0, b1, b2, a0, a1, a2);
}

/// Log-spaced band edges (Hz), [channels] + 1 of them, from [lowHz] to [highHz].
List<double> vocoderBandEdges(
  int channels, {
  double lowHz = 150,
  double highHz = 7000,
}) {
  final n = channels < 1 ? 1 : channels;
  final lo = log(lowHz);
  final hi = log(highHz);
  return <double>[
    for (var i = 0; i <= n; i++) exp(lo + (hi - lo) * (i / n)),
  ];
}

/// Deterministic white noise of [length] samples in [-1, 1] (seeded).
List<double> _noise(int length, int seed) {
  final rng = Random(seed);
  return List<double>.generate(length, (_) => rng.nextDouble() * 2 - 1);
}

/// Noise-vocodes [input] into [channels] spectral bands (see file header).
///
/// The output is RMS-matched to the input and peak-limited to avoid clipping,
/// so degradation changes *spectral detail*, not loudness. Deterministic for a
/// given [noiseSeed].
List<double> vocode(
  List<double> input,
  int channels, {
  int sampleRate = kSampleRate,
  int noiseSeed = 1,
  double lowHz = 150,
  double highHz = 7000,
}) {
  if (input.isEmpty || channels < 1) return List<double>.of(input);
  final nyquist = sampleRate / 2;
  final top = min(highHz, nyquist * 0.9);
  final edges = vocoderBandEdges(channels, lowHz: lowHz, highHz: top);
  final carrier = _noise(input.length, noiseSeed);
  final out = List<double>.filled(input.length, 0);

  for (var c = 0; c < channels; c++) {
    final flo = edges[c];
    final fhi = edges[c + 1];
    final center = sqrt(flo * fhi);
    final bandwidth = max(1.0, fhi - flo);
    final q = (center / bandwidth).clamp(0.4, 20.0);

    // Analysis band + its amplitude envelope (half-wave rectify + 50 Hz LP).
    final band = bandPassBiquad(input, center, q, sampleRate: sampleRate);
    final rectified = <double>[
      for (final s in band) s > 0 ? s : 0.0,
    ];
    final envelope = _lowPass(rectified, 50, sampleRate: sampleRate);

    // Band-limited noise carrier modulated by the envelope.
    final carrierBand =
        bandPassBiquad(carrier, center, q, sampleRate: sampleRate);
    for (var i = 0; i < out.length; i++) {
      out[i] += carrierBand[i] * envelope[i];
    }
  }

  return _matchRms(out, input);
}

/// Scales [signal] so its RMS matches [reference], then peak-limits to 0.98.
List<double> _matchRms(List<double> signal, List<double> reference) {
  final sRms = rms(signal);
  if (sRms <= 0) return signal;
  final gain = rms(reference) / sRms;
  var peak = 0.0;
  for (final x in signal) {
    final a = (x * gain).abs();
    if (a > peak) peak = a;
  }
  final limit = peak > 0.98 ? 0.98 / peak : 1.0;
  final k = gain * limit;
  for (var i = 0; i < signal.length; i++) {
    signal[i] *= k;
  }
  return signal;
}

// ---------------------------------------------------------------------------
// Adaptive session
// ---------------------------------------------------------------------------

/// Sequences and scores a noise-vocoder word-identification run.
///
/// The staircase moves along [kVocoderChannelLadder]: [ruleCorrect] correct
/// answers in a row step DOWN to fewer channels (harder, more degraded); one
/// wrong answer steps UP to more channels (easier). It reports the fewest
/// channels at which the listener still identified a word — the most degraded
/// "cochlear-implant-like" speech they mastered.
class VocoderSession {
  VocoderSession({
    this.moduleId = 'auditory',
    this.groupId = 'vocoder',
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
    this.ruleCorrect = 2,
    int startChannels = kVocoderStartChannels,
  }) : _index = _ladderIndexFor(startChannels);

  final String moduleId;
  final String groupId;
  final int maxTrials;
  final ProtocolMode mode;
  final int ruleCorrect;

  final List<TrialRecord> records = <TrialRecord>[];

  int _index;
  int _consecutiveCorrect = 0;
  int? _fewestMastered;

  static int _ladderIndexFor(int channels) {
    final i = kVocoderChannelLadder.indexOf(channels);
    return i < 0 ? kVocoderChannelLadder.indexOf(kVocoderStartChannels) : i;
  }

  /// Spectral channels for the next trial.
  int get currentChannels => kVocoderChannelLadder[_index];

  /// Fewest channels at which a word was correctly identified (null if none).
  /// Fewer channels = more degraded = harder, so this is the mastery headline.
  int? get fewestChannelsMastered => _fewestMastered;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  int get correctCount => records.where((TrialRecord r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  int get percent => (accuracy * 100).round();

  /// Records a response and advances the channel staircase.
  ///
  /// SAFETY: only the channel count changes — never master volume.
  bool submit(
    FourAlternativeTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final channelsAtPresentation = currentChannels;
    final response = (chosenIndex >= 0 && chosenIndex < trial.choices.length)
        ? trial.choices[chosenIndex]
        : '';
    records.add(
      TrialRecord(
        target: trial.target,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{'channels': channelsAtPresentation},
      ),
    );
    if (correct) {
      _fewestMastered = _fewestMastered == null
          ? channelsAtPresentation
          : min(_fewestMastered!, channelsAtPresentation);
      _consecutiveCorrect++;
      if (_consecutiveCorrect >= ruleCorrect) {
        _index = max(0, _index - 1); // fewer channels → harder
        _consecutiveCorrect = 0;
      }
    } else {
      _consecutiveCorrect = 0;
      _index = min(kVocoderChannelLadder.length - 1, _index + 1); // easier
    }
    return correct;
  }
}
