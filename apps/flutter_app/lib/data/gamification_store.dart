import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/gamification.dart';

/// SharedPreferences-backed persistence for [GamificationState], plus a
/// [ValueListenable] so widgets (e.g. the home-screen overlay) can rebuild when
/// progress changes.
///
/// The state is JSON-encoded under a single key. Records are applied through
/// the pure [applySession] rules in `core/gamification.dart`.
class GamificationStore {
  GamificationStore({this.key = 'hearbloom.gamification.v1'});

  final String key;

  /// Broadcasts the latest known state to listeners (initially empty until a
  /// [load] or [recordSession] populates it).
  static final ValueNotifier<GamificationState> listenable =
      ValueNotifier<GamificationState>(GamificationState.initial());

  /// Loads the persisted state (empty if none) and publishes it to [listenable].
  Future<GamificationState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? '';
    final state = GamificationState.decode(raw);
    listenable.value = state;
    return state;
  }

  /// Persists [state] and publishes it to [listenable].
  Future<void> save(GamificationState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, state.encode());
    listenable.value = state;
  }

  /// Applies a completed session, persists the result and returns any newly
  /// earned badges (for a celebration). Never throws for scoring purposes —
  /// failures to persist are swallowed so training is never blocked.
  Future<List<GamificationBadge>> recordSession({
    required int trials,
    required int correct,
    required String testId,
    DateTime? now,
  }) async {
    final current = await load();
    final outcome = applySession(
      current,
      trials: trials,
      correct: correct,
      testId: testId,
      now: now,
    );
    await save(outcome.state);
    return outcome.newBadges;
  }

  /// Clears all gamification progress.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    listenable.value = GamificationState.initial();
  }
}
