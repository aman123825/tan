import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Bumped whenever the on-device session history changes so live views (the
/// report tab, resume card…) can reload. Presentation-only signal.
final ValueNotifier<int> sessionHistoryRevision = ValueNotifier<int>(0);

/// Default patient identifier for locally-recorded sessions (single-user).
const String kDefaultPatient = 'Current User';

/// A completed session entry stored on-device.
class SessionRecord {
  const SessionRecord({
    required this.timestamp,
    required this.moduleId,
    required this.groupId,
    required this.title,
    required this.accuracy,
    required this.trials,
    this.patient = kDefaultPatient,
    this.synced = false,
    this.metric,
    this.metricValue,
    this.metricUnit,
    this.subScores,
    this.trajectory,
    this.trajectoryCorrect,
    this.chanceLevel,
    this.higherIsBetter,
    this.confidence,
    this.confusions,
    this.label,
  });

  final DateTime timestamp;
  final String moduleId;
  final String groupId;
  final String title;

  /// 0.0–1.0.
  final double accuracy;
  final int trials;

  /// Patient identifier this session belongs to. Defaults to
  /// [kDefaultPatient]; the clinician dashboard groups sessions by this value.
  /// It is the seam for future multi-patient support.
  final String patient;

  /// Whether this session has been successfully uploaded to the clinician
  /// backend. Defaults to false; [CloudSyncService] flips it after a
  /// successful sync so it is not re-sent.
  final bool synced;

  /// Headline result formatted for display (e.g. `'3.2 ms'`, `'−2.0 dB SNR'`,
  /// `'L 78% / R 92%'`). For adaptive tests this is the engine's
  /// reversal-based threshold — NOT the session accuracy, which a staircase
  /// deliberately pins near its target proportion. Null for sessions recorded
  /// before this field existed (falls back to accuracy in the UI).
  final String? metric;

  /// Numeric value behind [metric] (threshold, percent, span…), for trends.
  final double? metricValue;

  /// Unit of [metricValue] (`ms`, `dB`, `dB SNR`, `%`, `st`, `digits`…).
  final String? metricUnit;

  /// Named sub-scores, e.g. `{'left': 78, 'right': 92}` for per-ear tests or
  /// `{'talker': 4.1, 'spatial': 6.0, 'total': 9.2}` for LiSN-S advantages.
  final Map<String, double>? subScores;

  /// The adapted parameter value at each presented trial (staircase
  /// trajectory), for the report's trajectory plot and psychometric fit.
  final List<double>? trajectory;

  /// Per-trial correctness aligned with [trajectory].
  final List<bool>? trajectoryCorrect;

  /// The task's guess rate (1/n for nAFC, 0 for open-set), when known.
  final double? chanceLevel;

  /// Whether a larger [metricValue] means better performance (false for
  /// thresholds/SNR where smaller = finer). Null for legacy records.
  final bool? higherIsBetter;

  /// Optional post-session self-rated confidence (0–10). Informational only —
  /// like the fatigue rating it never affects scoring or adaptation.
  final int? confidence;

  /// Per-trial (target, response) label pairs for identification-style
  /// sessions — the raw material of a REAL confusion matrix (correct answers
  /// included, so the diagonal is preserved). Null for sessions whose
  /// responses aren't meaningful labels (interval choices) or that predate
  /// this field. Capped at persistence time to bound record size.
  final List<List<String>>? confusions;

  /// Optional user-given session name (from the post-session sheet), shown
  /// in the history and A/B comparison lists. Presentation only.
  final String? label;

  SessionRecord copyWith({bool? synced}) => SessionRecord(
        timestamp: timestamp,
        moduleId: moduleId,
        groupId: groupId,
        title: title,
        accuracy: accuracy,
        trials: trials,
        patient: patient,
        synced: synced ?? this.synced,
        metric: metric,
        metricValue: metricValue,
        metricUnit: metricUnit,
        subScores: subScores,
        trajectory: trajectory,
        trajectoryCorrect: trajectoryCorrect,
        chanceLevel: chanceLevel,
        higherIsBetter: higherIsBetter,
        confidence: confidence,
        confusions: confusions,
        label: label,
      );

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'mod': moduleId,
        'grp': groupId,
        'title': title,
        'acc': accuracy,
        'n': trials,
        'pt': patient,
        'synced': synced,
        if (metric != null) 'metric': metric,
        if (metricValue != null) 'mv': metricValue,
        if (metricUnit != null) 'mu': metricUnit,
        if (subScores != null) 'sub': subScores,
        if (trajectory != null)
          'traj': [for (final v in trajectory!) double.parse(v.toStringAsFixed(2))],
        if (trajectoryCorrect != null)
          'trajc': [for (final c in trajectoryCorrect!) c ? 1 : 0],
        if (chanceLevel != null) 'chance': chanceLevel,
        if (higherIsBetter != null) 'hib': higherIsBetter,
        if (confidence != null) 'conf': confidence,
        if (confusions != null) 'cf': confusions,
        if (label != null) 'lbl': label,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
        timestamp: DateTime.parse(j['ts'] as String),
        moduleId: j['mod'] as String,
        groupId: j['grp'] as String,
        title: (j['title'] as String?) ?? j['grp'] as String,
        accuracy: (j['acc'] as num).toDouble(),
        trials: (j['n'] as num).toInt(),
        patient: (j['pt'] as String?) ?? kDefaultPatient,
        synced: (j['synced'] as bool?) ?? false,
        metric: j['metric'] as String?,
        metricValue: (j['mv'] as num?)?.toDouble(),
        metricUnit: j['mu'] as String?,
        subScores: (j['sub'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        trajectory: (j['traj'] as List<dynamic>?)
            ?.map((v) => (v as num).toDouble())
            .toList(),
        trajectoryCorrect: (j['trajc'] as List<dynamic>?)
            ?.map((v) => v == 1 || v == true)
            .toList(),
        chanceLevel: (j['chance'] as num?)?.toDouble(),
        higherIsBetter: j['hib'] as bool?,
        confidence: (j['conf'] as num?)?.toInt(),
        confusions: (j['cf'] as List<dynamic>?)
            ?.map((p) =>
                (p as List<dynamic>).map((s) => s.toString()).toList())
            .toList(),
        label: j['lbl'] as String?,
      );
}

/// On-device session history (SharedPreferences-backed, max 200 entries).
class SessionHistory {
  SessionHistory({this.key = 'hearbloom.session_history.v1'});

  final String key;
  static const int _maxEntries = 200;

  Future<List<SessionRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(SessionRecord.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(SessionRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    existing.insert(0, record);
    if (existing.length > _maxEntries) {
      existing.removeRange(_maxEntries, existing.length);
    }
    await prefs.setString(key, json.encode(existing.map((e) => e.toJson()).toList()));
    sessionHistoryRevision.value++;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    sessionHistoryRevision.value++;
  }

  /// Overwrites the stored history with [records] (most-recent first). Used to
  /// persist mutations such as marking sessions synced. Trims to [_maxEntries].
  Future<void> saveAll(List<SessionRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = records.length > _maxEntries
        ? records.sublist(0, _maxEntries)
        : records;
    await prefs.setString(
        key, json.encode(trimmed.map((e) => e.toJson()).toList()));
    sessionHistoryRevision.value++;
  }
}

/// Persistent calibration flag (SharedPreferences).
class CalibrationStore {
  CalibrationStore({this.key = 'hearbloom.calibrated.v1'});

  final String key;

  Future<bool> isCalibrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<double?> level() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$key.level');
  }

  Future<void> markCalibrated(double comfortableLevel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    await prefs.setDouble('$key.level', comfortableLevel);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove('$key.level');
  }
}
