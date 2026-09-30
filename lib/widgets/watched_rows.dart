import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/http.dart';
import '../core/theme.dart';
import '../routes.dart';
import '../services/prefs.dart';
import 'common.dart';
import 'picture.dart';

/// "watched recently" and "what neighbors are watching" rows at the top of the
/// movies / TV lists (web-app components/watched.jsx). [tv] picks which half of
/// the response is shown. A row that comes back empty (or fails) is hidden.
///
/// - recently: POST Api.recent (…/user/recent/android, runs on the app token)
/// - neighbors: POST Api.neighbors with the stored reverse-geocode mapped to
///   the web's `{city, region, country}` keys; skipped when no location is stored
///   yet (the detail screens ask for it, this list does not).
class WatchedRows extends StatefulWidget {
  const WatchedRows({super.key, required this.tv});
  final bool tv;

  @override
  State<WatchedRows> createState() => _WatchedRowsState();
}

class _Row {
  const _Row(this.title, this.items);
  final String title;
  final List<Map<String, dynamic>> items;
}

class _WatchedRowsState extends State<WatchedRows> {
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await Future.wait([
      _recent().then((items) => _Row('watched recently', items)),
      _neighbors().then((items) => _Row('what neighbors are watching', items)),
    ]);
    if (!mounted) return;
    setState(() => _rows = loaded.where((r) => r.items.isNotEmpty).toList());
  }

  Future<List<Map<String, dynamic>>> _recent() async {
    final res = await Http.postJson(Api.recent, {'email': await Prefs.user});
    return _items(res);
  }

  Future<List<Map<String, dynamic>>> _neighbors() async {
    final location = await _location();
    if (location.isEmpty) return const [];
    // -1: the route excludes the caller's own views with user_id != session
    final res = await Http.postJson(Api.neighbors, {'location': location, 'session': -1});
    return _items(res);
  }

  /// The "location" pref holds expo-style placemarks; the web stores views with
  /// ipinfo keys (country = ISO code), which is what /neighbors matches on.
  Future<Map<String, String>> _location() async {
    try {
      final raw = await Prefs.getItem(PrefKeys.location);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      final p = decoded is List && decoded.isNotEmpty ? decoded.first : decoded;
      if (p is! Map) return const {};
      final out = <String, String>{};
      void put(String key, dynamic value) {
        if (value is String && value.isNotEmpty) out[key] = value;
      }
      put('city', p['city']);
      put('region', p['region']);
      put('country', p['isoCountryCode'] ?? p['country']);
      return out;
    } catch (e) {
      debugPrint('watched rows location: $e');
      return const {};
    }
  }

  /// One card per title: a series watched episode by episode shows once, on
  /// its latest episode.
  List<Map<String, dynamic>> _items(dynamic res) {
    if (res is! Map || res['status'] != true) return const [];
    final rows = res[widget.tv ? 'tv' : 'movies'];
    if (rows is! List) return const [];
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        final type = row['movie_type'];
        final item = type is String ? jsonDecode(type) : type;
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final key = '${widget.tv ? (map['serieID'] ?? map['id']) : map['id']}';
        if (!seen.add(key)) continue;
        items.add(map);
      } catch (_) {
        continue;
      }
    }
    return items;
  }

  void _open(Map<String, dynamic> item) {
    final season = item['season'];
    if (season != null && '$season'.isNotEmpty) {
      Nav.push(context, Routes.tvEpisode, {
        'id': item['serieID'],
        'stream': 'series',
        'episodeID': item['id'],
        'season': season,
        'episode': item['episode'],
        'name': item['name'],
        'background': item['background'],
        'anime': item['anime'],
      });
    } else {
      Nav.push(context, widget.tv ? Routes.tvId : Routes.moviesId, {'id': item['serieID'] ?? item['id']});
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in _rows) ...[
          SectionHeader(row.title),
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: row.items.length,
              itemBuilder: (context, i) {
                final item = row.items[i];
                final season = item['season'];
                return Padding(
                  padding: EdgeInsets.only(right: itemWidth * 0.011 + 2),
                  child: SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      onTap: () => _open(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // the poster takes what the name and season lines leave, so an episode's extra line never overflows
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: Picture(picture: item['background'] as String?),
                            ),
                          ),
                          SizedBox(
                            height: 22,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('${item['name'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                          if (season != null && '$season'.isNotEmpty)
                            Text('season $season | episode ${item['episode'] ?? ''}',
                                maxLines: 1, style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
