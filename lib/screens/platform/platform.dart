// One parameterized port of mobile/app/(tabs)/screens/{netflix,disney,anime,
// hindu,korean,china}.tsx. The six RN files are identical apart from the
// values in [_PlatformConfig] (see _configs below).
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/sweet_page.dart';
import 'latest.dart';

/// Per-platform differences between the six RN screens.
class _PlatformConfig {
  const _PlatformConfig({required this.slug, required this.query});

  /// Used for the row indexes (`<slug> movie` / `<slug> tv`), the collection
  /// hash prefix (`"<slug>" + current_date`) and LATEST's `wireframe`.
  /// Note: korean.tsx uses "korea".
  final String slug;

  /// TMDB discover filter appended after `api_key=...` (also LATEST's `api`).
  final String query;
}

const _configs = <String, _PlatformConfig>{
  'netflix': _PlatformConfig(slug: 'netflix', query: '&with_watch_providers=8&watch_region=US'),
  'disney': _PlatformConfig(slug: 'disney', query: '&with_watch_providers=337&watch_region=US'),
  'anime': _PlatformConfig(slug: 'anime', query: '&with_genres=16&with_keywords=210024'),
  'hindu': _PlatformConfig(slug: 'hindu', query: '&with_original_language=hi'),
  'korean': _PlatformConfig(slug: 'korea', query: '&with_original_language=ko'),
  'china': _PlatformConfig(slug: 'china', query: '&with_original_language=zh'),
};

const _fetchMoviesQuery = r'''
        query Movie (
            $page: Int!,
            $data:TRACK_DATA_OUTPUT,
            $hashedKey:String!
        ){
            movie(
                page:$page,
                data:$data,
                hashedKey:$hashedKey
            ) {
                results {
                    adult
                    backdrop_path
                    genre_ids
                    id
                    original_language
                    original_title
                    title
                    name
                    original_name
                    overview
                    popularity
                    poster_path
                    release_date
                    title
                    video
                    vote_average
                    vote_count
                }
                page
                total_pages
                total_results
                success
                error
                message
            }
        }
''';

const _insertMoviesMutation = r'''
    mutation AddMovies(
        $page:Int!,
        $results:[ADD_MOVIE_RESULTS_INPUT],
        $total_pages:Int!,
        $total_results:Int!,
        $data :TRACK_DATA_INPUT,
        $hashedKey:String!,
    ) {
        addMovies(
            page:$page,
            results:$results,
            total_pages:$total_pages,
            total_results:$total_results,
            data:$data,
            hashedKey:$hashedKey,
        ) {
            success
            message
        }
    }
''';

const _fetchMoviesCollectionQuery = r'''
    query MovieCollection (
      $data:[COLLECTION_TRACK_DATA_OUTPUT],
      $hashedKey:String!
    ){
        movieCollection(
            data :$data,
            hashedKey:$hashedKey
        ) {
            data {
                results {
                    adult
                    backdrop_path
                    genre_ids
                    id
                    original_language
                    original_title
                    overview
                    popularity
                    poster_path
                    release_date
                    title
                    video
                    vote_average
                    vote_count
                }
                page
                total_pages
                total_results
                index
            }
            success
            error
            message
        }
    }
''';

const _insertMoviesCollectionMutation = r'''
        mutation AddCollectionMovies(
            $data:[ADD_COLLECTION_MOVIES],
            $date:String!,
            $hashedKey:String!
        ) {
            addCollectionMovies(
                date:$date,
                data:$data,
                hashedKey:$hashedKey
            ) {
                success
                message
            }
        }
''';

class PlatformScreen extends StatefulWidget {
  const PlatformScreen({super.key, required this.platform});
  final String platform;

  static String titleFor(String key) =>
      const {'netflix': 'Netflix', 'disney': 'Disney', 'anime': 'Anime', 'hindu': 'Hindu', 'korean': 'Korean', 'china': 'China'}[key] ?? key;

  @override
  State<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends State<PlatformScreen> {
  List<Map<String, dynamic>> _movies = [];

  _PlatformConfig get _cfg => _configs[widget.platform] ?? _configs['netflix']!;
  String get _movieIndex => '${_cfg.slug} movie';
  String get _tvIndex => '${_cfg.slug} tv';

  /// `temp_movies` entry for an index: TMDB api + RN `type`.
  ({String api, String type}) _temp(String index) =>
      index == _tvIndex ? (api: 'discover/tv', type: 'tv') : (api: 'discover/movie', type: 'movies');

  bool _isTvIndex(String index) => index == _tvIndex;

  @override
  void initState() {
    super.initState();
    _initMoviesInit(runContent: [_movieIndex, _tvIndex], page: 1, adjustable: true);
  }

  void _upsert(String index, Map<String, dynamic> fields) {
    if (!mounted) return;
    setState(() {
      final list = [..._movies];
      final i = list.indexWhere((m) => m['index'] == index);
      if (i > -1) {
        list[i] = {...list[i], ...fields};
      } else {
        list.add({'index': index, ...fields});
      }
      // Keep "<slug> movie" above "<slug> tv" regardless of which fetch wins.
      int rank(Map<String, dynamic> m) => m['index'] == _movieIndex ? 0 : (m['index'] == _tvIndex ? 1 : 2);
      list.sort((a, b) => rank(a).compareTo(rank(b)));
      _movies = list;
    });
  }

  String _url(String index, int page) {
    final k = KeyService.instance;
    return '${k.movieDb}${_temp(index).api}?api_key=${k.apiKey}${_cfg.query}&page=$page';
  }

  /// RN `intitializeMoviesInit`: first load through the collection cache.
  Future<void> _initMoviesInit({required List<String> runContent, int? page, bool adjustable = false}) async {
    final currentDate = isoDateToday();
    var hashed = '${_cfg.slug}$currentDate';
    final movieWrap = <Map<String, dynamic>>[];
    for (final actualIndex in runContent) {
      final p = page ?? 1;
      hashed += '$p$actualIndex';
      movieWrap.add({'page': p, 'index': actualIndex, 'date': currentDate, 'type': _temp(actualIndex).type});
    }
    final hashedKey = sha256Hex(hashed);
    if (!adjustable) return;

    Future<void> freshFetch() async {
      await KeyService.instance.ready;
      final insertContent = (await Future.wait(runContent.map((actualIndex) async {
        final p = page ?? 1;
        final json = await Http.getJson(_url(actualIndex, p));
        final themeResults = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
        if (themeResults.isEmpty) return null;
        final normalized = themeResults.map(normalizeMovieResult).toList();
        _upsert(actualIndex, {
          'results': normalized,
          'page': p,
          'total_pages': json['total_pages'],
          'total_results': json['total_results'],
          'type': _temp(actualIndex).type,
        });
        return <String, dynamic>{
          'page': p,
          'results': json['results'],
          'total_pages': json['total_pages'],
          'total_results': json['total_results'],
          'index': actualIndex,
          'type': _temp(actualIndex).type,
        };
      })))
          .whereType<Map<String, dynamic>>()
          .toList();

      Gql.mutate(_insertMoviesCollectionMutation, {
        'data': insertContent,
        'date': currentDate,
        'hashedKey': hashedKey,
      });
    }

    final data = await Gql.query(_fetchMoviesCollectionQuery, {'data': movieWrap, 'hashedKey': hashedKey});
    final mc = data?['movieCollection'];
    if (mc is Map && mc['message'] != 'not initialized' && !truthy(mc['error']) && mc['data'] is List) {
      if (!mounted) return;
      setState(() => _movies = asMapList(mc['data']));
    } else {
      await freshFetch();
    }
  }

  /// RN `intitializeMovies` (SWEETPAGE page change).
  Future<void> _initializeMovies({
    required List<String> runContent,
    int? page,
    bool adjustable = false,
    String genreId = '',
    String regionId = '',
    String languageId = '',
    int yearId = 0,
  }) async {
    for (final actualIndex in runContent) {
      _fetchMoviesFromApi(actualIndex,
          page: page, adjustable: adjustable, genreId: genreId, regionId: regionId, languageId: languageId, yearId: yearId);
    }
  }

  Future<void> _fetchMoviesFromApi(
    String actualIndex, {
    int? page,
    required bool adjustable,
    required String genreId,
    required String regionId,
    required String languageId,
    required int yearId,
  }) async {
    final currentDate = isoDateToday();
    final p = page ?? 1;
    final type = _temp(actualIndex).type;
    final hashedKey = sha256Hex('$p$actualIndex');

    Future<void> freshFetch() async {
      await KeyService.instance.ready;
      final json = await Http.getJson(_url(actualIndex, p));
      final results = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
      if (results.isEmpty) return;
      final normalized = results.map(normalizeMovieResult).toList();
      _upsert(actualIndex, {
        'results': normalized,
        'page': p,
        'type': type,
        if (json['total_pages'] != null) 'total_pages': json['total_pages'],
        if (json['total_results'] != null) 'total_results': json['total_results'],
      });
      Gql.mutate(_insertMoviesMutation, {
        'page': p,
        'results': normalized,
        'total_pages': json['total_pages'],
        'total_results': json['total_results'],
        'data': {
          'genre': genreId,
          'region': regionId,
          'language': languageId,
          'year': yearId,
          'index': actualIndex,
          'date': currentDate,
          'type': type,
        },
        'hashedKey': hashedKey,
      });
    }

    if (!adjustable) return;
    final data = await Gql.query(_fetchMoviesQuery, {
      'page': p,
      'data': {
        'genre': genreId,
        'year': yearId,
        'region': regionId,
        'language': languageId,
        'index': actualIndex,
        'date': currentDate,
        'type': type,
      },
      'hashedKey': hashedKey,
    });
    final movie = data?['movie'];
    if (movie is! Map) return freshFetch();
    final cached = asMapList(movie['results']);
    if (truthy(movie['success']) && movie['results'] is List && cached.length < 20) {
      return freshFetch();
    } else if (movie['error'] == 'insert movies' || movie['error'] == 'no records found') {
      return freshFetch();
    }
    _upsert(actualIndex, {
      'results': cached,
      'page': movie['page'] ?? p,
      if (movie['total_pages'] != null) 'total_pages': movie['total_pages'],
      if (movie['total_results'] != null) 'total_results': movie['total_results'],
      'type': type,
    });
  }

  void _open(Map<String, dynamic> item, bool isTv) {
    final id = item.idInt;
    Nav.push(context, isTv ? Routes.tvId : Routes.moviesId, {'id': id});
    RemoteService.instance.route(isTv ? TvPaths.tvId : TvPaths.moviesId, {'id': id});
  }

  @override
  Widget build(BuildContext context) {
    if (_movies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text('Loading...', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: _movies.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return LatestCarousel(key: ValueKey('latest-${widget.platform}'), api: _cfg.query, wireframe: _cfg.slug);
        }
        final item = _movies[i - 1];
        final index = '${item['index'] ?? ''}';
        final isTv = _isTvIndex(index);
        final page = toNum(item['page']).toInt();
        return Column(
          key: ValueKey('${widget.platform}-$index'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(index.replaceFirst('_', ' ')),
            SweetPage(
              key: ValueKey('${widget.platform}-page-$index'),
              page: page == 0 ? 1 : page,
              totalPages: toNum(item['total_pages']).toInt(),
              onPageChange: (newPage) => _initializeMovies(
                runContent: [index],
                adjustable: true,
                page: newPage,
                genreId: '',
                regionId: '',
                languageId: '',
                yearId: 0,
              ),
            ),
            MediaRow(items: asMapList(item['results']), onTap: (m) => _open(m, isTv)),
          ],
        );
      },
    );
  }
}
