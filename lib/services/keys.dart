import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/env.dart';
import '../core/http.dart';

/// Port of components/home/safe.tsx (KeyProvider / useKeys) and the TV app's
/// lib/providers/keys.dart. Loads `{ keys: {...} }` from the KEYS endpoint
/// (KEYS in development, KEYS_LIVE otherwise).
///
/// Unlike the RN version, screens can `await KeyService.instance.ready` before
/// building TMDB urls — the RN screens raced the key fetch and could request
/// `undefined...?api_key=undefined` on a cold start.
class KeyService extends ChangeNotifier {
  KeyService._();
  static final KeyService instance = KeyService._();

  Map<String, dynamic> _safeKeys = {};
  Map<String, dynamic> get safeKeys => _safeKeys;

  Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;
  bool get isLoaded => _safeKeys.isNotEmpty;

  /// TMDB base url, e.g. https://api.themoviedb.org/3/
  String get movieDb => '${_safeKeys['MOVIE_DB'] ?? ''}';

  /// TMDB api key
  String get apiKey => '${_safeKeys['API_KEY'] ?? ''}';

  /// TMDB image base url
  String get imgPoster => '${_safeKeys['IMG_POSTER'] ?? ''}';

  Future<void> loadKeys() async {
    final url = Env.isDev ? Env.keys : Env.keysLive;
    try {
      final data = await Http.getJson(url);
      if (data is Map && data['keys'] is Map) {
        _safeKeys = Map<String, dynamic>.from(data['keys'] as Map);
        notifyListeners();
      } else {
        debugPrint('KeyService: no keys from "$url"');
      }
    } catch (e) {
      debugPrint('KeyService error: $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Retry (e.g. pull-to-refresh after a failed cold start).
  Future<void> reload() async {
    if (_ready.isCompleted) _ready = Completer<void>();
    await loadKeys();
  }
}
