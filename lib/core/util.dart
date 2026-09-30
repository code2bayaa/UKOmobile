import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SHA256 hex digest — same output as crypto-js `SHA256(str).toString()`.
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// Stringify a value exactly like JavaScript string concatenation does, so the
/// `hashedKey` strings built by the RN code (e.g. `page + "" + genreId + ...`
/// with `genreId === false`) produce identical SHA256 keys in Dart.
///   null -> "null", false -> "false", 3.0 -> "3", [1,2] -> "1,2"
/// Use `'undefined'` literally where the RN code concatenated an undefined.
String js(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is double) {
    if (v.isNaN) return 'NaN';
    if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
    return v.toString();
  }
  if (v is Iterable) return v.map((e) => e == null ? '' : js(e)).join(',');
  if (v is Map) return '[object Object]';
  return v.toString();
}

/// `new Date().toISOString().split("T")[0]` (UTC date, like JS).
String isoDateToday() => DateTime.now().toUtc().toIso8601String().split('T').first;

/// JS truthiness (used when porting `a || b` / `if (x)` chains).
bool truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !(v is double && v.isNaN);
  if (v is String) return v.isNotEmpty;
  return true;
}

/// JS `a || b || c`: first truthy value, else the last one.
dynamic or(List<dynamic> values) {
  for (final v in values) {
    if (truthy(v)) return v;
  }
  return values.isEmpty ? null : values.last;
}

/// `Number(x)` like JS (NaN -> 0 here for convenience).
num toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  if (v is bool) return v ? 1 : 0;
  return 0;
}

/// Route params helpers. expo-router's `useLocalSearchParams` always yields
/// strings; in the port we pass a `Map<String, dynamic>` and parse defensively.
class P {
  P._();
  static int? intOf(Map<String, dynamic>? p, String k) {
    final v = p?[k];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String? str(Map<String, dynamic>? p, String k) {
    final v = p?[k];
    if (v == null) return null;
    final s = v.toString();
    return (s == 'undefined' || s == 'null') ? null : s;
  }

  static bool boolOf(Map<String, dynamic>? p, String k) {
    final v = p?[k];
    if (v is bool) return v;
    return v?.toString() == 'true';
  }

  /// Values that the RN code JSON.stringify'd into params (seasons, episodes...).
  static dynamic json(Map<String, dynamic>? p, String k) {
    final v = p?[k];
    if (v is String) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    return v;
  }
}

/// Media helpers over raw TMDB / GraphQL maps (the RN code works on plain JS
/// objects, so the port keeps `Map<String, dynamic>` rather than strict models).
extension MediaMap on Map<String, dynamic> {
  int get idInt => this['id'] is int ? this['id'] as int : int.tryParse('${this['id']}') ?? 0;

  /// `title || original_title || name || original_name`
  String get displayTitle =>
      (or([this['title'], this['original_title'], this['name'], this['original_name']]) ?? '').toString();

  /// `poster_path || backdrop_path`
  String? get posterOrBackdrop => or([this['poster_path'], this['backdrop_path']]) as String?;

  /// Rating text used by every card:
  /// `Number(vote_average) ? toFixed(1) : Number(popularity) ? toFixed(1) : vote_count`
  String get ratingText {
    final va = toNum(this['vote_average']);
    if (va != 0) return va.toStringAsFixed(1);
    final pop = toNum(this['popularity']);
    if (pop != 0) return pop.toStringAsFixed(1);
    return '${this['vote_count'] ?? ''}';
  }

  /// Year from release_date or first_air_date.
  String get year {
    final d = or([this['release_date'], this['first_air_date']]);
    if (d is String && d.isNotEmpty) return d.split('-').first;
    return '';
  }
}

/// Casts a decoded JSON list into `List<Map<String, dynamic>>`, dropping non-maps.
List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Recursively removes graphql_flutter's injected `__typename` so query
/// results can be passed back into mutation inputs.
dynamic stripTypename(dynamic v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key != '__typename') e.key.toString(): stripTypename(e.value),
    };
  }
  if (v is List) return v.map(stripTypename).toList();
  return v;
}

/// Normalisation the RN movies page applies before `addMovies` mutations.
Map<String, dynamic> normalizeMovieResult(Map<String, dynamic> m) => {
      'id': or([m['id'], 0]),
      'title': or([m['title'], m['name'], m['original_title'], '']),
      'name': or([m['title'], m['name'], m['original_title'], '']),
      'first_air_date': or([m['first_air_date'], m['release_date'], '']),
      'release_date': or([m['release_date'], m['first_air_date'], '']),
      'poster_path': or([m['poster_path'], m['backdrop_path'], null]),
      'backdrop_path': or([m['backdrop_path'], m['poster_path'], null]),
      'adult': m['adult'] is bool ? m['adult'] : false,
      'overview': or([m['overview'], '']),
      'popularity': toNum(m['popularity']),
      'vote_average': toNum(m['vote_average']),
      'vote_count': toNum(m['vote_count']),
      'genre_ids': m['genre_ids'] ??
          (m['genres'] is List ? (m['genres'] as List).map((g) => g['id']).toList() : <dynamic>[]),
    };
