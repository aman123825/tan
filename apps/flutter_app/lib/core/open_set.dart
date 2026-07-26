/// Typed open-set recognition protocol logic (pure Dart).
///
/// The listener types what they heard; scoring normalizes case/whitespace/
/// punctuation and compares either as a whole word or by word accuracy (for
/// phrases). No response ever changes master volume.
library;

import 'dart:math';

import 'protocol_engine.dart';
import 'speech_in_noise.dart' show ProtocolMode;

/// Normalizes a typed response: lowercase, trim, collapse whitespace, and drop
/// punctuation (keeps letters, digits and single spaces).
String normalizeResponse(String s) {
  final lowered = s.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    final c = String.fromCharCode(rune);
    if (RegExp(r'[a-z0-9]').hasMatch(c)) {
      buffer.write(c);
    } else if (c == ' ' || c == '\t' || c == '\n') {
      buffer.write(' ');
    }
    // other punctuation is dropped
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

enum OpenSetScoreMode { wholeWord, wordAccuracy }

/// Scores [response] against [target] in [mode], returning a value in [0, 1].
double scoreResponse(String target, String response, OpenSetScoreMode mode) {
  final t = normalizeResponse(target);
  final r = normalizeResponse(response);
  if (mode == OpenSetScoreMode.wholeWord) {
    return t == r ? 1.0 : 0.0;
  }
  final targetWords = t.split(' ').where((w) => w.isNotEmpty).toList();
  final responseWords = r.split(' ').where((w) => w.isNotEmpty).toList();
  if (targetWords.isEmpty) return 0;
  var matched = 0;
  for (final w in targetWords) {
    final i = responseWords.indexOf(w);
    if (i >= 0) {
      responseWords.removeAt(i); // consume so duplicates count once
      matched++;
    }
  }
  return matched / targetWords.length;
}

/// Deterministic generator drawing target items from a pool.
class OpenSetGenerator {
  OpenSetGenerator(this.pool, {int seed = 0}) : _rng = Random(seed);

  final List<String> pool;
  final Random _rng;

  String next() => pool[_rng.nextInt(pool.length)];
}

/// Sequences and scores a typed open-set recognition run.
class OpenSetSession {
  OpenSetSession({
    this.moduleId = 'openset',
    this.groupId = 'open_word',
    this.scoreMode = OpenSetScoreMode.wholeWord,
    this.snrDb,
    this.maxTrials = 20,
    this.mode = ProtocolMode.training,
  });

  final String moduleId;
  final String groupId;
  final OpenSetScoreMode scoreMode;

  /// SNR (dB) if presented in noise; null means quiet.
  final double? snrDb;
  final int maxTrials;
  final ProtocolMode mode;

  final List<TrialRecord> records = <TrialRecord>[];
  double _scoreSum = 0;

  int get trialNumber => records.length + 1;
  int get completedTrials => records.length;

  bool get showsFeedback => mode == ProtocolMode.training;
  bool get isComplete => records.length >= maxTrials;

  /// Mean score across trials (whole-word: fraction correct).
  double get accuracy => records.isEmpty ? 0 : _scoreSum / records.length;

  /// Records a typed response, returns whether it fully matched the target.
  bool submit(String target, String response, {required int latencyMs}) {
    final score = scoreResponse(target, response, scoreMode);
    final correct = score >= 1.0;
    _scoreSum += score;
    records.add(
      TrialRecord(
        target: target,
        response: response,
        correct: correct,
        latencyMs: latencyMs,
        parameters: <String, Object?>{
          'score': score,
          if (snrDb != null) 'snr_db': snrDb,
        },
      ),
    );
    return correct;
  }
}

/// A concrete open-set trial item: the [text] to score against and the ordered
/// [assetPaths] whose audio is decoded and concatenated for presentation
/// (multiple paths → a runtime-concatenated sentence, e.g. matrix sentences).
class OpenSetItem {
  const OpenSetItem(this.text, this.assetPaths);

  final String text;
  final List<String> assetPaths;
}
