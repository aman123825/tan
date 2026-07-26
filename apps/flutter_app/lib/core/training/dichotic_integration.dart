/// Dichotic Integration Training logic (CADPOTS-style, pure Dart).
///
/// A target digit is presented to the WEAK ear (left by default) while a
/// competing digit plays in the other ear. Training begins with a large
/// interaural level difference (the target ear ~10 dB louder) and, as the
/// listener succeeds, that advantage is reduced (10 → 8 → 6 → 4 → 2 → 0 dB) on
/// a 2-down/1-up staircase. The minimum level difference reached is reported —
/// smaller = better dichotic integration in the weak ear (cf. Musiek et al.'s
/// dichotic interaural intensity difference / DIID training).
///
/// SAFETY: the staircase adapts only the interaural LEVEL DIFFERENCE (a
/// relative balance between the two ears), never master volume, and the target
/// is attenuated toward the distractor rather than boosted past it. Verified
/// headlessly.
library;

import 'dart:math';
import 'dart:typed_data';

import '../audio/pcm_synth.dart';
import '../protocol_engine.dart';
import '../speech_in_noise.dart' show ProtocolMode;

/// Ear the target is trained in.
enum TrainedEar { left, right }

extension TrainedEarInfo on TrainedEar {
  String get label => this == TrainedEar.left ? 'LEFT' : 'RIGHT';
  String get id => this == TrainedEar.left ? 'left' : 'right';
}

/// The digits used as dichotic targets/distractors.
const List<String> kDichoticIntegrationDigits = <String>[
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
];

/// Starting interaural level difference (dB): the target ear this much louder.
const double kDiiStartLevelDiffDb = 10;

/// Builds a dichotic stereo stimulus: the [target] digit in the trained ear,
/// louder than the [distractor] digit in the other ear by [levelDiffDb] dB.
///
/// The louder ear is held at unit gain and the *other* ear is attenuated by
/// [levelDiffDb], so reducing the difference raises the competing ear rather
/// than boosting the target past a ceiling. Returns a 16-bit stereo WAV.
Uint8List buildDichoticIntegrationStimulus({
  required List<double> target,
  required List<double> distractor,
  required TrainedEar trainedEar,
  required double levelDiffDb,
  int sampleRate = kSampleRate,
}) {
  final quietGain = pow(10, -levelDiffDb.abs() / 20).toDouble();
  final targetLoud = <double>[for (final x in target) x];
  final distractorQuiet = <double>[for (final x in distractor) x * quietGain];
  if (trainedEar == TrainedEar.left) {
    return encodeWavStereo16(targetLoud, distractorQuiet, sampleRate: sampleRate);
  }
  return encodeWavStereo16(distractorQuiet, targetLoud, sampleRate: sampleRate);
}

/// One training trial: the [targetDigit] (trained ear), the [distractorDigit]
/// (other ear) and the closed-set [choices] (all digits).
class DichoticIntegrationTrial {
  const DichoticIntegrationTrial({
    required this.targetDigit,
    required this.distractorDigit,
  });

  final String targetDigit;
  final String distractorDigit;

  List<String> get choices => kDichoticIntegrationDigits;

  bool isCorrect(String chosen) => chosen == targetDigit;
}

/// Deterministic generator: a target digit and a different distractor digit.
class DichoticIntegrationGenerator {
  DichoticIntegrationGenerator({int seed = 0}) : _rng = Random(seed);

  final Random _rng;

  DichoticIntegrationTrial next() {
    final target = kDichoticIntegrationDigits[
        _rng.nextInt(kDichoticIntegrationDigits.length)];
    String distractor;
    do {
      distractor = kDichoticIntegrationDigits[
          _rng.nextInt(kDichoticIntegrationDigits.length)];
    } while (distractor == target);
    return DichoticIntegrationTrial(
      targetDigit: target,
      distractorDigit: distractor,
    );
  }
}

/// Sequences and scores a dichotic-integration training run. The interaural
/// level difference adapts 2-down/1-up (two correct → reduce the difference by
/// [stepDb]; one wrong → increase it), floored at 0 dB and capped at
/// [startLevelDiffDb].
class DichoticIntegrationSession {
  DichoticIntegrationSession({
    this.moduleId = 'auditory',
    this.groupId = 'dichotic_integration',
    this.trainedEar = TrainedEar.left,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
    double startLevelDiffDb = kDiiStartLevelDiffDb,
    double stepDb = 2,
  })  : _track = AdaptiveTrack(
          value: startLevelDiffDb,
          min: 0,
          max: startLevelDiffDb,
          step: stepDb,
        ),
        _minLevelDiff = startLevelDiffDb;

  final String moduleId;
  final String groupId;
  final TrainedEar trainedEar;
  final int maxTrials;
  final ProtocolMode mode;

  final AdaptiveTrack _track;
  final List<TrialRecord> records = <TrialRecord>[];
  double _minLevelDiff;

  bool get showsFeedback => mode == ProtocolMode.training;
  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;
  bool get isComplete => records.length >= maxTrials;

  /// The interaural level difference (dB) the next trial will use.
  double get currentLevelDiffDb => _track.value;

  /// Smallest level difference (dB) reached — the training outcome.
  double get minLevelDiffDb => _minLevelDiff;

  int get correctCount => records.where((r) => r.correct).length;
  double get accuracy => records.isEmpty ? 0 : correctCount / records.length;

  /// Records a response, advances the staircase and tracks the minimum
  /// difference reached. Returns whether the response was correct.
  bool submit(
    DichoticIntegrationTrial trial,
    String chosen, {
    required int latencyMs,
    int replays = 0,
  }) {
    final correct = trial.isCorrect(chosen);
    final diff = _track.value;
    records.add(TrialRecord(
      target: trial.targetDigit,
      response: chosen,
      correct: correct,
      latencyMs: latencyMs,
      replays: replays,
      parameters: <String, Object?>{
        'trained_ear': trainedEar.id,
        'level_diff_db': diff,
        'distractor': trial.distractorDigit,
      },
    ));
    _track.submit(correct);
    if (_track.value < _minLevelDiff) _minLevelDiff = _track.value;
    return correct;
  }
}
