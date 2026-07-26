/// Gamification core (pure Dart): points, streaks, badges and the daily goal.
///
/// This layer is deliberately Flutter-free and side-effect-free so the scoring
/// rules can be unit-tested headlessly. Persistence lives in
/// `data/gamification_store.dart`; the celebratory UI lives in
/// `features/gamification/`.
///
/// SAFETY: gamification is purely motivational. It reads session outcomes and
/// awards points/badges — it never touches scoring, adaptation or master
/// volume, and "fatigue is not failure": missing a day only pauses a streak.
library;

import 'dart:convert';

/// Points awarded per completed trial, per correct trial, and per finished
/// session respectively.
const int kPointsPerTrial = 10;
const int kPointsPerCorrect = 5;
const int kPointsPerSession = 20;

/// Exercises that count toward the daily goal.
const int kDailyGoal = 3;

/// The set of training tests whose completion unlocks the "All Tests Tried"
/// badge. These are the Phase 3 training modules.
const List<String> kGamifiedTestIds = <String>[
  'competing_speakers',
  'speed_training',
  'phonemic_contrast',
  'auditory_closure',
  'continuum',
  'working_memory',
  'following_directions',
];

/// A badge definition (id, display name, emoji glyph and a short description).
class GamificationBadge {
  const GamificationBadge(this.id, this.name, this.emoji, this.description);

  final String id;
  final String name;
  final String emoji;
  final String description;
}

/// Badge ids (kept as constants so callers avoid stringly-typed typos).
class BadgeIds {
  static const String firstSession = 'first_session';
  static const String tenSessions = 'ten_sessions';
  static const String fiftySessions = 'fifty_sessions';
  static const String perfectScore = 'perfect_score';
  static const String sevenDayStreak = 'seven_day_streak';
  static const String thirtyDayStreak = 'thirty_day_streak';
  static const String allTestsTried = 'all_tests_tried';
}

/// All available badges, in display order.
const List<GamificationBadge> kBadges = <GamificationBadge>[
  GamificationBadge(
      BadgeIds.firstSession, 'First Session', '🌱', 'Completed your first session'),
  GamificationBadge(
      BadgeIds.tenSessions, '10 Sessions', '🔟', 'Completed ten sessions'),
  GamificationBadge(
      BadgeIds.fiftySessions, '50 Sessions', '🏅', 'Completed fifty sessions'),
  GamificationBadge(
      BadgeIds.perfectScore, 'Perfect Score', '💯', 'Every answer correct in a session'),
  GamificationBadge(BadgeIds.sevenDayStreak, '7-Day Streak', '🔥',
      'Practised seven days in a row'),
  GamificationBadge(BadgeIds.thirtyDayStreak, '30-Day Streak', '⚡',
      'Practised thirty days in a row'),
  GamificationBadge(BadgeIds.allTestsTried, 'All Tests Tried', '🧭',
      'Tried every training exercise'),
];

/// Looks up a badge definition by id (null if unknown).
GamificationBadge? badgeById(String id) {
  for (final b in kBadges) {
    if (b.id == id) return b;
  }
  return null;
}

/// A `yyyy-mm-dd` key for the local calendar day of [dt].
String dayKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// The mutable-but-value-like gamification progress record.
class GamificationState {
  GamificationState({
    this.points = 0,
    this.sessionsCompleted = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.exercisesToday = 0,
    this.lastActiveDay,
    this.goalDay,
    Set<String>? badges,
    Set<String>? testsTried,
  })  : badges = badges ?? <String>{},
        testsTried = testsTried ?? <String>{};

  int points;
  int sessionsCompleted;
  int currentStreak;
  int longestStreak;

  /// Exercises completed on [goalDay] (toward [kDailyGoal]).
  int exercisesToday;

  /// `yyyy-mm-dd` of the most recent active day (for streak accounting).
  String? lastActiveDay;

  /// `yyyy-mm-dd` the [exercisesToday] counter belongs to.
  String? goalDay;

  final Set<String> badges;
  final Set<String> testsTried;

  /// A fresh, empty state.
  factory GamificationState.initial() => GamificationState();

  /// Progress toward the daily goal, capped at [kDailyGoal].
  int get dailyProgress =>
      exercisesToday > kDailyGoal ? kDailyGoal : exercisesToday;

  bool get dailyGoalMet => exercisesToday >= kDailyGoal;

  GamificationState copy() => GamificationState(
        points: points,
        sessionsCompleted: sessionsCompleted,
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        exercisesToday: exercisesToday,
        lastActiveDay: lastActiveDay,
        goalDay: goalDay,
        badges: <String>{...badges},
        testsTried: <String>{...testsTried},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'points': points,
        'sessions': sessionsCompleted,
        'streak': currentStreak,
        'longest': longestStreak,
        'today': exercisesToday,
        'lastDay': lastActiveDay,
        'goalDay': goalDay,
        'badges': badges.toList(),
        'tests': testsTried.toList(),
      };

  factory GamificationState.fromJson(Map<String, dynamic> j) =>
      GamificationState(
        points: (j['points'] as num?)?.toInt() ?? 0,
        sessionsCompleted: (j['sessions'] as num?)?.toInt() ?? 0,
        currentStreak: (j['streak'] as num?)?.toInt() ?? 0,
        longestStreak: (j['longest'] as num?)?.toInt() ?? 0,
        exercisesToday: (j['today'] as num?)?.toInt() ?? 0,
        lastActiveDay: j['lastDay'] as String?,
        goalDay: j['goalDay'] as String?,
        badges: ((j['badges'] as List?)?.cast<String>() ?? const <String>[])
            .toSet(),
        testsTried:
            ((j['tests'] as List?)?.cast<String>() ?? const <String>[]).toSet(),
      );

  String encode() => json.encode(toJson());

  factory GamificationState.decode(String raw) {
    if (raw.isEmpty) return GamificationState.initial();
    try {
      return GamificationState.fromJson(
          json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GamificationState.initial();
    }
  }
}

/// The result of applying a session: the updated [state] and any [newBadges]
/// earned by this session (for a celebration).
class SessionOutcome {
  const SessionOutcome(this.state, this.newBadges);

  final GamificationState state;
  final List<GamificationBadge> newBadges;
}

/// Points earned for a session of [trials] trials, [correct] of them correct.
int pointsForSession(int trials, int correct) =>
    trials * kPointsPerTrial + correct * kPointsPerCorrect + kPointsPerSession;

/// Applies a completed session to [prev] and returns the new state plus any
/// newly-earned badges. Pure: [prev] is not mutated.
///
/// [trials]/[correct] drive points and the "Perfect Score" badge; [testId]
/// records which exercise was tried (for "All Tests Tried"); [now] fixes the
/// calendar day for streaks and the daily goal; [requiredTests] overrides the
/// set needed for "All Tests Tried" (defaults to [kGamifiedTestIds]).
SessionOutcome applySession(
  GamificationState prev, {
  required int trials,
  required int correct,
  required String testId,
  DateTime? now,
  List<String>? requiredTests,
}) {
  final state = prev.copy();
  final at = now ?? DateTime.now();
  final today = dayKey(DateTime(at.year, at.month, at.day));
  final yesterday = dayKey(DateTime(at.year, at.month, at.day)
      .subtract(const Duration(days: 1)));

  state.points += pointsForSession(trials, correct);
  state.sessionsCompleted += 1;
  state.testsTried.add(testId);

  // Streak: extend if today follows yesterday, keep if already active today,
  // otherwise (re)start at 1.
  if (state.lastActiveDay == today) {
    // already counted today — streak unchanged
    if (state.currentStreak == 0) state.currentStreak = 1;
  } else if (state.lastActiveDay == yesterday) {
    state.currentStreak += 1;
  } else {
    state.currentStreak = 1;
  }
  state.lastActiveDay = today;
  if (state.currentStreak > state.longestStreak) {
    state.longestStreak = state.currentStreak;
  }

  // Daily goal: reset the counter on a new day.
  if (state.goalDay == today) {
    state.exercisesToday += 1;
  } else {
    state.goalDay = today;
    state.exercisesToday = 1;
  }

  // Badge evaluation.
  final required = (requiredTests ?? kGamifiedTestIds).toSet();
  final earned = <String>{
    if (state.sessionsCompleted >= 1) BadgeIds.firstSession,
    if (state.sessionsCompleted >= 10) BadgeIds.tenSessions,
    if (state.sessionsCompleted >= 50) BadgeIds.fiftySessions,
    if (trials > 0 && correct >= trials) BadgeIds.perfectScore,
    if (state.currentStreak >= 7) BadgeIds.sevenDayStreak,
    if (state.currentStreak >= 30) BadgeIds.thirtyDayStreak,
    if (required.isNotEmpty && state.testsTried.containsAll(required))
      BadgeIds.allTestsTried,
  };
  final newBadgeIds = earned.difference(state.badges);
  state.badges.addAll(earned);
  final newBadges = <GamificationBadge>[
    for (final b in kBadges)
      if (newBadgeIds.contains(b.id)) b,
  ];
  return SessionOutcome(state, newBadges);
}
