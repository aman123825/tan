import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// The favourited item ids (`module:<id>` / `training:<index>`), shared
/// app-wide so star toggles and the Favorites row stay in sync without
/// plumbing. Populated from disk on first [FavoritesStore.load].
final ValueNotifier<Set<String>> favoriteIds =
    ValueNotifier<Set<String>>(<String>{});

/// Stable favourite id for a catalog module.
String moduleFavoriteId(String moduleId) => 'module:$moduleId';

/// Stable favourite id for a training exercise (index is the launch
/// contract used by `_launchTraining`).
String trainingFavoriteId(int index) => 'training:$index';

/// SharedPreferences-backed persistence for the favourites set.
class FavoritesStore {
  FavoritesStore({this.key = 'hearbloom.favorites.v1'});

  final String key;

  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(key)?.toSet() ?? <String>{};
      favoriteIds.value = stored;
      return stored;
    } catch (_) {
      return favoriteIds.value;
    }
  }

  Future<void> toggle(String id) async {
    final next = Set<String>.of(favoriteIds.value);
    if (!next.remove(id)) next.add(id);
    favoriteIds.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, next.toList()..sort());
    } catch (_) {
      // Persistence failure: the in-memory state still drives this session.
    }
  }
}
