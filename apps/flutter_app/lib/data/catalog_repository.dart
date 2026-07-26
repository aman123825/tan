import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/catalog.dart';

/// Loads the protocol [Catalog] from the bundled asset.
///
/// The JSON parsing/validation itself lives in the pure-Dart [Catalog] models
/// (see `models/catalog.dart`), which are exercised headlessly by
/// `tool/verify/catalog_harness.dart`. This repository only owns asset IO and
/// a small in-memory cache.
class CatalogRepository {
  CatalogRepository({this.assetPath = defaultAssetPath});

  static const String defaultAssetPath = 'assets/protocols/catalog.json';

  final String assetPath;

  Catalog? _cached;

  /// Loads and caches the catalog. Subsequent calls return the cached value
  /// unless [forceReload] is set.
  Future<Catalog> load({bool forceReload = false}) async {
    final cached = _cached;
    if (cached != null && !forceReload) return cached;
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final catalog = Catalog.fromJson(json);
    _cached = catalog;
    return catalog;
  }
}
