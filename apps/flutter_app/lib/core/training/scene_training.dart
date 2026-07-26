/// Real-world "scene" listening training (pure Dart).
///
/// Target speech is presented inside one of three everyday acoustic scenes and
/// the listener identifies the word from four choices. SNR adapts per scene
/// (2-down/1-up on the shared [AdaptiveTrack]); the scene determines the
/// background:
///  * Restaurant — multi-talker babble + clinking-dish bursts.
///  * Classroom  — modulated ("children's") background noise.
///  * Phone call — speech band-limited to 300–3200 Hz.
///
/// SAFETY: adaptation only moves SNR; master volume is never changed. DSP is
/// dependency-free (uses `core/audio/pcm_synth.dart`) so it is unit-testable
/// headlessly.
library;

import 'dart:math';

import '../audio/pcm_synth.dart';
import '../protocol_engine.dart';
import '../speech_in_noise.dart';

/// The three training scenes.
enum TrainingScene { restaurant, classroom, phone }

extension TrainingSceneInfo on TrainingScene {
  String get title => switch (this) {
        TrainingScene.restaurant => 'Restaurant',
        TrainingScene.classroom => 'Classroom',
        TrainingScene.phone => 'Phone call',
      };

  String get groupId => switch (this) {
        TrainingScene.restaurant => 'scene_restaurant',
        TrainingScene.classroom => 'scene_classroom',
        TrainingScene.phone => 'scene_phone',
      };

  String get emoji => switch (this) {
        TrainingScene.restaurant => '🍽️',
        TrainingScene.classroom => '🏫',
        TrainingScene.phone => '📞',
      };

  String get description => switch (this) {
        TrainingScene.restaurant =>
          'Follow the talker over background chatter and clinking dishes.',
        TrainingScene.classroom =>
          'Follow the teacher over a modulated children\'s background.',
        TrainingScene.phone => 'Understand speech over a narrow phone band.',
      };
}

/// One-pole low-pass filter (RC). Returns a new buffer.
List<double> onePoleLowPass(List<double> x, double cutoffHz, int sampleRate) {
  if (x.isEmpty || cutoffHz <= 0) return List<double>.of(x);
  final dt = 1.0 / sampleRate;
  final rc = 1.0 / (2 * pi * cutoffHz);
  final alpha = dt / (rc + dt);
  final out = List<double>.filled(x.length, 0.0);
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    y += alpha * (x[i] - y);
    out[i] = y;
  }
  return out;
}

/// One-pole high-pass filter (RC). Returns a new buffer.
List<double> onePoleHighPass(List<double> x, double cutoffHz, int sampleRate) {
  if (x.isEmpty || cutoffHz <= 0) return List<double>.of(x);
  final dt = 1.0 / sampleRate;
  final rc = 1.0 / (2 * pi * cutoffHz);
  final alpha = rc / (rc + dt);
  final out = List<double>.filled(x.length, 0.0);
  var prevX = x[0];
  var prevY = x[0];
  for (var i = 0; i < x.length; i++) {
    final y = alpha * (prevY + x[i] - prevX);
    out[i] = y;
    prevY = y;
    prevX = x[i];
  }
  return out;
}

/// Cascaded band-pass (high-pass then low-pass) — the phone-band filter when
/// used with 300–3200 Hz. Applied twice per stage for a steeper skirt.
List<double> bandPass(
  List<double> x,
  double lowHz,
  double highHz,
  int sampleRate,
) {
  var out = onePoleHighPass(x, lowHz, sampleRate);
  out = onePoleHighPass(out, lowHz, sampleRate);
  out = onePoleLowPass(out, highHz, sampleRate);
  out = onePoleLowPass(out, highHz, sampleRate);
  return out;
}

/// Multi-talker babble: the sum of several detuned, speech-rate-modulated noise
/// streams, peak-normalized. A dependency-free stand-in for recorded babble.
List<double> multiTalkerBabble({
  required double seconds,
  int seed = 0,
  int talkers = 5,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0.0);
  final rng = Random(seed);
  for (var t = 0; t < talkers; t++) {
    final rate = 2.5 + rng.nextDouble() * 4; // 2.5–6.5 Hz syllabic rate
    final stream = amNoise(
      seconds: seconds,
      rateHz: rate,
      depthDb: -3,
      amp: 0.2,
      seed: seed * 131 + t * 17 + 1,
      sampleRate: sampleRate,
    );
    for (var i = 0; i < n && i < stream.length; i++) {
      out[i] += stream[i];
    }
  }
  // Band-limit to a vocal range so it reads as chatter, then peak-normalize.
  final voiced = bandPass(out, 200, 4000, sampleRate);
  var mx = 0.0;
  for (final v in voiced) {
    final a = v.abs();
    if (a > mx) mx = a;
  }
  if (mx > 0) {
    final k = 0.25 / mx;
    for (var i = 0; i < voiced.length; i++) {
      voiced[i] *= k;
    }
  }
  return voiced;
}

/// Sparse high-frequency "clink" bursts mixed over a scene (dish clatter).
List<double> clinkBursts({
  required double seconds,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  final n = (seconds * sampleRate).round();
  final out = List<double>.filled(n, 0.0);
  final rng = Random(seed * 7 + 3);
  final count = max(1, (seconds * 2).round());
  for (var c = 0; c < count; c++) {
    final start = rng.nextInt(n);
    final freq = 2500.0 + rng.nextDouble() * 3500; // 2.5–6 kHz
    final burst = tone(
      seconds: 0.05,
      freqHz: freq,
      amp: 0.12,
      fadeMs: 5,
      sampleRate: sampleRate,
    );
    for (var i = 0; i < burst.length && start + i < n; i++) {
      // Fast exponential decay for a percussive clink.
      out[start + i] += burst[i] * exp(-i / (0.01 * sampleRate));
    }
  }
  return out;
}

/// The background bed for a [scene] (before mixing with speech at the SNR).
List<double> sceneBackground(
  TrainingScene scene, {
  required double seconds,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  switch (scene) {
    case TrainingScene.restaurant:
      final babble =
          multiTalkerBabble(seconds: seconds, seed: seed, sampleRate: sampleRate);
      final clinks =
          clinkBursts(seconds: seconds, seed: seed, sampleRate: sampleRate);
      return <double>[
        for (var i = 0; i < babble.length; i++)
          babble[i] + (i < clinks.length ? clinks[i] : 0.0)
      ];
    case TrainingScene.classroom:
      return amNoise(
        seconds: seconds,
        rateHz: 4,
        depthDb: -6,
        amp: 0.22,
        seed: seed + 5,
        sampleRate: sampleRate,
      );
    case TrainingScene.phone:
      // Light line-noise; the speech itself is band-limited in the page.
      return whiteNoise(
        seconds: seconds,
        amp: 0.12,
        seed: seed + 9,
        sampleRate: sampleRate,
      );
  }
}

/// Sequences and scores an adaptive scene-training run (SNR staircase, 4AFC).
class SceneTrainingSession {
  SceneTrainingSession({
    this.moduleId = 'noise',
    required this.scene,
    AdaptiveTrack? track,
    this.maxTrials = 10,
    this.mode = ProtocolMode.training,
  }) : track = track ?? AdaptiveTrack.snr(start: 8);

  final String moduleId;
  final TrainingScene scene;
  final AdaptiveTrack track;
  final int maxTrials;
  final ProtocolMode mode;

  String get groupId => scene.groupId;

  final List<TrialRecord> records = <TrialRecord>[];

  double get currentSnrDb => track.value;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => track.complete || records.length >= maxTrials;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;
  double? get thresholdSnrDb => track.threshold;

  bool submit(
    FourAlternativeTrial trial,
    int chosenIndex, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosenIndex);
    final snrAtPresentation = track.value;
    records.add(
      TrialRecord(
        target: trial.target,
        response: (chosenIndex >= 0 && chosenIndex < trial.choices.length)
            ? trial.choices[chosenIndex]
            : '',
        correct: correct,
        latencyMs: latencyMs,
        replays: replays,
        parameters: <String, Object?>{
          'snr_db': snrAtPresentation,
          'scene': scene.name,
        },
      ),
    );
    track.submit(correct);
    return correct;
  }
}
