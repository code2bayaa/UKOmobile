import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/category_card.dart';
import '../../widgets/celebraties.dart';
import '../../widgets/common.dart';
import '../../widgets/sweet_page.dart';
import '../../widgets/watched_rows.dart';

/// Port of app/(tabs)/movies/page.tsx AND app/(tabs)/tv/page.tsx (the two
/// files are the same screen with different TMDB lists), parameterised by
/// [kind].
///
/// Loading (unchanged from RN):
///  1. `movieCollection(data:[{page,index,date,type}...], hashedKey)` with
///     hashedKey = SHA256("movie" + date + Σ(page + index)). On a miss
///     ("not initialized" / error / no data) every list is fetched from TMDB and
///     written back with `addCollectionMovies`.
///  2. Paging a section (SweetPage) queries `movie(page, data, hashedKey)` with
///     hashedKey = SHA256(page + "" + genre + region + language + year + index + suffix),
///     falling back to TMDB + `addMovies` when the cache is short / missing.
///
/// RN bugs fixed here (see PORTING.md):
///  - tv/page.tsx:284/344/367 hashed + typed TV pages as "movie", so TV
///    "popular"/"trending" page N shared a cache key with the movie lists.
///    TV now uses suffix/type "tv".
///  - movies/page.tsx:691 sent "/movies/top" (no such TV route) -> /movies/rated.
///  - tv/page.tsx:615 sent Disney to "/tv/netflix" -> /tv/disney.
///  - "hindu" studio never reached the TV (compared against "hindi").
///  - tv/page.tsx:744 never passed the studio title, so studio taps on the TV
///    tab were not mirrored; they are now (TV-side platform lists).
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.kind});
  final MediaKind kind;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _ListDef {
  const _ListDef(this.index, this.api, this.tvPath);
  final String index;
  final String api;
  final String tvPath;
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Map<String, dynamic>> _movies = [];
  final Set<int> _outer = {};

  bool get _tv => widget.kind.isTv;

  static const _movieLists = [
    _ListDef('discover', 'discover/movie', TvPaths.moviesDiscover),
    _ListDef('popular', 'movie/popular', TvPaths.moviesPopular),
    _ListDef('trending', 'trending/movie/day', TvPaths.moviesTrending),
    _ListDef('top_rated', 'movie/top_rated', TvPaths.moviesRated),
    _ListDef('upcoming', 'movie/upcoming', TvPaths.moviesUpcoming),
    _ListDef('now_playing', 'movie/now_playing', TvPaths.moviesPlaying),
  ];
  static const _tvLists = [
    _ListDef('airing', 'tv/airing_today', TvPaths.tvAiring),
    _ListDef('trending', 'trending/tv/day', TvPaths.tvTrending),
    _ListDef('popular', 'tv/popular', TvPaths.tvPopular),
    _ListDef('top rated', 'tv/top_rated', TvPaths.tvTop),
    _ListDef('on air', 'tv/on_the_air', TvPaths.tvOnair),
  ];

  List<_ListDef> get _lists => _tv ? _tvLists : _movieLists;
  List<String> get _runContent => _tv
      ? const ['airing', 'trending', 'popular', 'top rated', 'on air']
      : const ['popular', 'trending', 'top_rated', 'upcoming', 'now_playing'];

  // eden opens the Eden studios' own catalogue (/eden/movies or /eden/series), as the web's first tile
  static const _studios = ['eden', 'netflix', 'disney', 'anime', 'hindu', 'korean', 'china'];

  // ---- GraphQL documents (verbatim from the RN screens) --------------------
  static const _fetchMoviesQueryMovie = r'''
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

  static const _fetchMoviesQueryTv = r'''
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
                        original_name
                        overview
                        popularity
                        poster_path
                        release_date
                        first_air_date
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

  static const _insertMoviesMutation = r'''
        mutation AddCollectionMovies(
            $data:[ADD_COLLECTION_MOVIES],
            $hashedKey:String!,
            $date:String!,
        ) {
            addCollectionMovies(
                hashedKey:$hashedKey,
                date:$date,
                data:$data
            ) {
                success
                message
            }
        }
    ''';

  static const _fetchSetQuery = r'''
        query Movie (
            $page: Int!,
            $data:TRACK_DATA_OUTPUT,
            $hashedKey:String!
        ){
            movie(
                page:$page,
                data :$data,
                hashedKey:$hashedKey
            ) {
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
                success
                error
                message
            }
        }
    ''';

  static const _insertSetMutation = r'''
        mutation AddMovies(
            $page:Int!,
            $results:[ADD_MOVIE_RESULTS_INPUT],
            $total_pages:Int!,
            $total_results:Int!,
            $data :TRACK_DATA_INPUT,
            $hashedKey:String!
        ) {
            addMovies(
                page:$page,
                results:$results,
                total_pages:$total_pages,
                total_results:$total_results,
                data:$data,
                hashedKey:$hashedKey
            ) {
                success
                message
            }
        }
    ''';

  @override
  void initState() {
    super.initState();
    _initializeMoviesInit(runContent: _runContent, page: 1);
  }

  _ListDef _def(String index) => _lists.firstWhere((d) => d.index == index);

  /// `new Date().getFullYear() - new Date().getDate()` (RN's "rotating year").
  int _rotatingYear() {
    final now = DateTime.now();
    return now.year - now.day;
  }

  String _baseUrl(_ListDef d, int page) {
    final k = KeyService.instance;
    return '${k.movieDb}${d.api}?api_key=${k.apiKey}&language=en-US&page=$page';
  }

  void _upsert(String index, List<Map<String, dynamic>> results, int page, dynamic totalPages, dynamic totalResults,
      {required bool append}) {
    if (!mounted) return;
    setState(() {
      final i = _movies.indexWhere((m) => m['index'] == index);
      if (i > -1) {
        final existing = _movies[i];
        _movies[i] = {
          ...existing,
          'results': append ? [...asMapList(existing['results']), ...results] : results,
          'page': page,
          'total_pages': totalPages ?? existing['total_pages'],
          'total_results': totalResults ?? existing['total_results'],
        };
      } else {
        _movies.add({
          'index': index,
          'results': results,
          'page': page,
          'total_pages': totalPages,
          'total_results': totalResults,
        });
        // keep the section order stable (RN pushed in completion order)
        _movies.sort((a, b) => _runContent.indexOf('${a['index']}').compareTo(_runContent.indexOf('${b['index']}')));
      }
    });
  }

  // ---- initial load: intitializeMoviesInit ---------------------------------
  Future<void> _initializeMoviesInit({required List<String> runContent, int page = 1}) async {
    final currentDate = isoDateToday();
    final type = widget.kind.api;
    var hashed = 'movie$currentDate';
    final movieWrap = <Map<String, dynamic>>[];
    for (final index in runContent) {
      hashed += '$page$index';
      movieWrap.add({'page': page, 'index': index, 'date': currentDate, 'type': type});
    }
    final hashedKey = sha256Hex(hashed);

    Future<void> freshFetch() async {
      await KeyService.instance.ready;
      final insertContent = (await Future.wait(runContent.map((index) async {
        final d = _def(index);
        var apiUrl = _baseUrl(d, page);
        if (!_tv && index == 'top_rated') {
          final k = KeyService.instance;
          apiUrl = '${k.movieDb}discover/movie?api_key=${k.apiKey}&primary_release_year=${_rotatingYear()}'
              '&sort_by=vote_average.desc&vote_count.gte=300&include_adult=false&language=en-US&page=$page';
        } else if (_tv && index == 'trending') {
          apiUrl = '$apiUrl&primary_release_year=${_rotatingYear()}';
        }
        final data = await Http.getJson(apiUrl);
        final results = asMapList(data is Map ? data['results'] : null);
        if (results.isEmpty) return null;
        _upsert(index, results, page, data['total_pages'], data['total_results'], append: !_tv);
        return <String, dynamic>{
          'page': page,
          'results': results,
          'total_pages': data['total_pages'],
          'total_results': data['total_results'],
          'index': index,
          'type': type,
        };
      })))
          .whereType<Map<String, dynamic>>()
          .toList();

      Gql.mutate(_insertMoviesMutation, {'data': insertContent, 'date': currentDate, 'hashedKey': hashedKey});
    }

    final fetched = await Gql.query(_tv ? _fetchMoviesQueryTv : _fetchMoviesQueryMovie, {
      'data': movieWrap,
      'hashedKey': hashedKey,
    });
    final collection = fetched?['movieCollection'];
    if (collection is Map) {
      if (collection['message'] == 'not initialized' || truthy(collection['error'])) {
        await freshFetch();
      } else {
        final data = asMapList(collection['data']);
        if (mounted) setState(() => _movies = data);
      }
    } else {
      await freshFetch();
    }
  }

  // ---- paging: intitializeMovies -------------------------------------------
  Future<void> _initializeMovies({
    required List<String> runContent,
    int? page,
    bool adjustable = false,
    dynamic genreId = false,
    dynamic regionId = false,
    dynamic languageId = false,
    dynamic yearId = 0,
  }) async {
    for (final actualIndex in runContent) {
      _fetchMoviesFromApi(actualIndex, page, adjustable, genreId, regionId, languageId, yearId);
    }
  }

  Future<bool> _fetchMoviesFromApi(String actualIndex, int? pageArg, bool adjustable, dynamic genreId,
      dynamic regionId, dynamic languageId, dynamic yearId) async {
    await KeyService.instance.ready;
    final currentDate = isoDateToday();
    final d = _def(actualIndex);
    final page = pageArg ?? 1;
    // tv/page.tsx used the "movie" suffix too (cache collision bug) — fixed.
    final suffix = widget.kind.api;
    // the date keeps a page from being served from the server's memory past its day
    final hashedKey =
        sha256Hex('$page${js(genreId)}${js(regionId)}${js(languageId)}${js(yearId)}$actualIndex$suffix$currentDate');
    final k = KeyService.instance;

    var apiUrl = '${k.movieDb}${d.api}?api_key=${k.apiKey}&language=en-US&page=$page'
        '&with_genres=${js(genreId)}&with_origin_country=${js(regionId)}&sort_by=popularity.desc'
        '&with_original_language=${js(languageId)}&primary_release_year=${js(yearId)}';
    if (!_tv && actualIndex == 'top_rated') {
      yearId = _rotatingYear();
      apiUrl = '${k.movieDb}discover/movie?api_key=${k.apiKey}&primary_release_year=$yearId'
          '&sort_by=vote_average.desc&vote_count.gte=300&include_adult=false&language=en-US&page=$page';
    } else if (_tv && actualIndex == 'trending') {
      yearId = _rotatingYear();
      apiUrl = '${k.movieDb}${d.api}?api_key=${k.apiKey}&language=en-US&page=$page'
          '&with_genres=${js(genreId)}&with_origin_country=${js(regionId)}&sort_by=popularity.desc'
          '&with_original_language=${js(languageId)}&primary_release_year=$yearId';
    }

    Future<bool> freshFetch() async {
      final data = await Http.getJson(apiUrl);
      final results = asMapList(data is Map ? data['results'] : null);
      if (results.isEmpty) return false;
      _upsert(actualIndex, results, page, data['total_pages'], data['total_results'], append: !_tv);
      Gql.mutate(_insertSetMutation, {
        'page': page,
        'results': results.map(normalizeMovieResult).toList(),
        'total_pages': data['total_pages'],
        'total_results': data['total_results'],
        'hashedKey': hashedKey,
        'data': {
          'genre': genreId,
          'region': regionId,
          'language': languageId,
          'year': yearId,
          'index': actualIndex,
          'date': currentDate,
          'type': suffix,
        },
      });
      return true;
    }

    if (adjustable || truthy(genreId) || truthy(regionId) || truthy(languageId) || truthy(yearId)) {
      final fetched = await Gql.query(_fetchSetQuery, {
        'page': page,
        'data': {
          'genre': genreId,
          'year': yearId,
          'region': regionId,
          'language': languageId,
          'index': actualIndex,
          'date': currentDate,
          'type': suffix,
        },
        'hashedKey': hashedKey,
      });
      final movie = fetched?['movie'];
      if (movie is Map) {
        final results = asMapList(movie['results']);
        if (movie['success'] == true && movie['results'] != null && results.length < 20) {
          return freshFetch();
        } else if (movie['error'] == 'insert movies' || movie['error'] == 'no records found') {
          return freshFetch();
        } else {
          _upsert(actualIndex, results, page, movie['total_pages'], movie['total_results'], append: false);
          return true;
        }
      }
      return freshFetch();
    }
    return false;
  }

  // ---- navigation -----------------------------------------------------------
  void _openItem(Map<String, dynamic> item) {
    final state = {'id': item.idInt};
    Nav.push(context, _tv ? Routes.tvId : Routes.moviesId, state);
    RemoteService.instance.route(_tv ? TvPaths.tvId : TvPaths.moviesId, state);
  }

  void _openStudio(String key) {
    if (key == 'eden') {
      Nav.push(context, _tv ? Routes.edenSeries : Routes.edenMovies);
      return;
    }
    Nav.push(context, Routes.platform(key));
    RemoteService.instance.route(TvPaths.platform(key, tv: _tv));
  }

  void _clickTv(int i, String index) {
    setState(() => _outer.contains(i) ? _outer.remove(i) : _outer.add(i));
    final d = _lists.where((l) => l.index == index);
    if (d.isNotEmpty) RemoteService.instance.route(d.first.tvPath);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final itemWidth = width * 0.45;
    return ListenableBuilder(
      listenable: RemoteService.instance,
      builder: (context, _) {
        final connected = RemoteService.instance.connected;
        return ListView.builder(
          padding: const EdgeInsets.only(top: 16),
          itemCount: _movies.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                children: [
                  Celebraties(actedMovies: _movies, mode: widget.kind.api),
                  SizedBox(
                    height: 100 + 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      itemCount: _studios.length,
                      itemBuilder: (context, s) => Padding(
                        padding: EdgeInsets.only(left: width * 0.01),
                        child: CategoryCard(
                          item: _studios[s],
                          title: _studios[s],
                          width: itemWidth,
                          height: 100,
                          onTap: () => _openStudio(_studios[s]),
                        ),
                      ),
                    ),
                  ),
                  WatchedRows(tv: _tv),
                ],
              );
            }
            final idx = i - 1;
            final item = _movies[idx];
            final index = '${item['index']}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  index.replaceFirst('_', ' '),
                  trailing: connected
                      ? ClickTvButton(disabled: _outer.contains(idx), onPressed: () => _clickTv(idx, index))
                      : null,
                ),
                SweetPage(
                  page: toNum(item['page']).toInt(),
                  totalPages: toNum(item['total_pages']).toInt(),
                  onPageChange: (p) => _initializeMovies(
                    runContent: [index],
                    adjustable: true,
                    page: p,
                    genreId: '',
                    regionId: '',
                    languageId: '',
                    yearId: 0,
                  ),
                ),
                MediaRow(items: asMapList(item['results']), tv: _tv, onTap: _openItem),
              ],
            );
          },
        );
      },
    );
  }
}
