import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/picture.dart';
import '../../core/theme.dart';

/// Port of app/(tabs)/search.tsx.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Run {
  const _Run(this.index, this.api, this.select, this.insert, this.type);
  final String index;
  final String api;
  final int page = 1;
  final String select;
  final String insert;
  final String type;
}

class _SearchScreenState extends State<SearchScreen> {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _content = [];
  Timer? _debounce;

  /// Bumped on every new search so late responses of an older query are dropped.
  int _generation = 0;

  static final _sqlMarkers = RegExp(
    r'''(--|/\*|\*/|;|['"]\s*or\s+|'\s*;|\b(union|select|insert|delete|update|drop|alter|truncate|exec)\b)''',
    caseSensitive: false,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// JS getCurrentWeek()
  static int _currentWeek() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final pastDaysOfYear = now.difference(startOfYear).inMilliseconds / 86400000;
    final startDay = startOfYear.weekday % 7; // JS getDay(): Sunday = 0
    return ((pastDaysOfYear + startDay + 1) / 7).ceil();
  }

  /// Normalises + validates the text; returns the plain search value (encoded only
  /// in the TMDB URL, so the server cache sees the same words) or null when blocked.
  String? _sanitize(String value) {
    var normalized = value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length > 100) normalized = normalized.substring(0, 100);
    if (_sqlMarkers.hasMatch(normalized)) return null;
    return normalized;
  }

  /// searchMachine (search button). RN used `type: "movie"` here.
  void _searchMachine() {
    _debounce?.cancel();
    final v = _sanitize(_input.text);
    if (v == null) {
      _input.clear();
      return;
    }
    _initializeSearch(_runContent(), v);
  }

  /// editMachine (every keystroke).
  void _editMachine(String value) {
    _debounce?.cancel();
    final v = _sanitize(value);
    if (v == null) {
      _input.clear();
      return;
    }
    if (v.length < 2) return; // RN would pop the "Input search field" alert on every clear
    _debounce = Timer(const Duration(milliseconds: 400), () => _initializeSearch(_runContent(), v));
  }

  /// Always type "movie": RN sent "movies" from the keystroke search, which cached
  /// TMDB movies under a type nothing else reads.
  List<_Run> _runContent() => [
        _Run('tv', 'search/tv', Api.search, Api.searchInsert, 'tv'),
        _Run('movies', 'search/movie', Api.search, Api.searchInsert, 'movie'),
        _Run('people', 'search/person', Api.searchPerson, Api.searchInsertPerson, 'person'),
      ];

  void _initializeSearch(List<_Run> runContent, String search) {
    if (search.isEmpty) {
      showUkoAlert(context, 'Input search field', 'Please enter a value in the search field.');
      return;
    }
    final gen = ++_generation;
    final currentWeek = _currentWeek();
    _searchEden(search, gen);
    for (final run in runContent) {
      _runOne(run, search, currentWeek, gen);
    }
  }

  /// PRD #20: Eden titles live only in our DB - LIKE-searched by the database service.
  Future<void> _searchEden(String search, int gen) async {
    if (Api.edenSearch.isEmpty) return;
    final data = await Http.postJson(Api.edenSearch, {'search': search});
    if (data is! Map || !mounted || gen != _generation) return;
    for (final row in const [('movies', 'eden movies', 'movie'), ('tv', 'eden series', 'tv')]) {
      _putRow(gen, {
        'index': row.$2,
        'results': asMapList(data[row.$1]),
        'type': row.$3,
        'eden': true,
        'name': search,
      });
    }
  }

  /// Replaces (or drops, when it has no results) one titled row, leaving the others.
  void _putRow(int gen, Map<String, dynamic> row) {
    if (!mounted || gen != _generation) return;
    setState(() {
      final updated = _content.where((s) => s['index'] != row['index']).toList();
      if (asMapList(row['results']).isNotEmpty) updated.add(row);
      _content = updated;
    });
  }

  void _upsert(int gen, _Run run, String search, List<Map<String, dynamic>> results, dynamic page, dynamic totalPages) {
    if (!mounted || gen != _generation) return;
    setState(() {
      final updated = [..._content];
      final existing = updated.indexWhere((s) => s['index'] == run.index);
      if (existing > -1) {
        updated[existing] = {...updated[existing], 'results': results};
      } else {
        updated.add({
          'index': run.index,
          'results': results,
          'page': page,
          'total_pages': totalPages,
          'type': run.type,
          'name': search,
          'api': run.api,
        });
      }
      _content = updated;
    });
  }

  Future<void> _runOne(_Run run, String search, int currentWeek, int gen) async {
    final hashedKey = sha256Hex('${run.page}$search${run.type}');

    Future<void> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final data = await Http.getJson(
          '${k.movieDb}${run.api}?api_key=${k.apiKey}&language=en-US&query=${Uri.encodeQueryComponent(search)}&page=${run.page}');
      if (data is! Map) return;
      final results = asMapList(data['results']);
      if (results.isNotEmpty) {
        _upsert(gen, run, search, results, run.page, data['total_pages']);
      } else {
        _putRow(gen, {'index': run.index, 'results': <Map<String, dynamic>>[], 'name': search});
      }

      final inserted = await Http.postJson(run.insert, {
        'page': run.page,
        'results': data['results'],
        'total_pages': or([data['total_pages'], 0]),
        'total_results': or([data['total_results'], 0]),
        'data': {'index': 'search', 'search': search},
        'date': currentWeek,
        'type': run.type,
        'hashedKey': hashedKey,
      });
      debugPrint(inserted is Map && truthy(inserted['success']) ? 'inserted' : 'error inserting...');
    }

    final selectData = await Http.postJson(run.select, {
      'page': run.page,
      'search': search,
      'index': 'search',
      'type': run.type,
      'date': currentWeek,
      'hashedKey': hashedKey,
    });

    if (selectData is Map && (selectData['error'] == 'insert movies' || selectData['error'] == 'no records found')) {
      await freshFetch();
    } else if (selectData is Map && truthy(selectData['success']) && asMapList(selectData['results']).isNotEmpty) {
      _upsert(gen, run, search, asMapList(selectData['results']), selectData['page'], selectData['total_pages']);
    } else {
      await freshFetch();
    }
  }

  /// navRoute: RN pushed `/${type}/id` (so "/movie/id" and "/person/id",
  /// which don't exist) and emitted screen names as the TV path.
  void _navRoute(Map<String, dynamic> item, String type, {bool eden = false}) {
    final id = item.idInt;
    if (eden) {
      // Eden detail pages are phone-side only (open to guests)
      Nav.push(context, type == 'tv' ? Routes.tvEden : Routes.moviesEden, {'id': id});
      return;
    }
    switch (type) {
      case 'tv':
        Nav.push(context, Routes.tvId, {'id': id});
        RemoteService.instance.route(TvPaths.tvId, {'id': id});
      case 'person':
      case 'people':
        // phone only - the TV app has no People pages to mirror
        Nav.push(context, Routes.peopleId, {'id': id});
      default: // 'movie' | 'movies'
        Nav.push(context, Routes.moviesId, {'id': id});
        RemoteService.instance.route(TvPaths.moviesId, {'id': id});
    }
  }

  Widget _renderMovie(Map<String, dynamic> s, String type, double width, {bool eden = false}) {
    final title = or([s['name'], s['title'], s['original_name'], s['original_title']]) ?? '';
    final rd = s['release_date'], fd = s['first_air_date'];
    final year = (rd is String && rd.isNotEmpty)
        ? rd.split('-').first
        : (fd is String && fd.isNotEmpty)
            ? fd.split('-').first
            : '';
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => _navRoute(s, type, eden: eden),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: eden
                  ? EdenImage(path: or([s['poster_path'], s['backdrop_path']]) as String?)
                  : Picture(picture: or([s['profile_path'], s['poster_path'], s['backdrop_path']]) as String?),
            ),
            SizedBox(
              height: 25,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$title',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: UkoColors.divider, width: 2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_border, size: 18, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(s.ratingText, style: const TextStyle(color: UkoColors.yellow, fontSize: 15)),
                  const SizedBox(width: 6),
                  const Text('|', style: TextStyle(color: Colors.white)),
                  const SizedBox(width: 6),
                  Text(year, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderMovies(Map<String, dynamic> item) {
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    final results = asMapList(item['results']);
    final type = (or([item['type'], 'movies'])).toString();
    final eden = item['eden'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 30, child: SectionHeader('${item['index']}'.replaceFirst('_', ' '))),
          SizedBox(
            height: 250,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: results.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _renderMovie(results[i], type, itemWidth, eden: eden),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                SizedBox(
                  width: (w - 16) * 0.8,
                  child: TextField(
                    controller: _input,
                    onChanged: _editMachine,
                    onSubmitted: (_) => _searchMachine(),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(color: Colors.white),
                      contentPadding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: 8),
                      border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                      enabledBorder:
                          const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                      focusedBorder:
                          const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _searchMachine,
                    child: const Center(child: Icon(Icons.search, size: 20, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_content.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              itemCount: _content.length,
              itemBuilder: (_, i) => _renderMovies(_content[i]),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}
