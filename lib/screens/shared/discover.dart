// Port of mobile/app/(tabs)/movies/discover.tsx + mobile/app/(tabs)/tv/discover.tsx
// (identical apart from movie/tv strings, expressed through [MediaKind]).
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/sweet_page.dart';
import 'controllers.dart';

const String _fetchMoviesQuery = r'''
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
                genres {
                    id
                    name
                }
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

const String _insertMoviesMutation = r'''
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

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.kind, this.params = const {}});
  final MediaKind kind;
  final Map<String, dynamic> params;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  /// The single "discover_movie" / "discover_tv" collection (RN kept an array of one).
  Map<String, dynamic>? _collection;
  Map<String, dynamic> _selectedFilters = {};

  /// Latest request id; older responses are ignored (RN could let a slow
  /// earlier response overwrite a newer filter's results).
  int _seq = 0;

  String get _index => 'discover_${widget.kind.api}';

  @override
  void initState() {
    super.initState();
    _intitializeMovies(const DiscoverQuery());
  }

  Future<void> _intitializeMovies(DiscoverQuery q) async {
    final seq = ++_seq;
    final kind = widget.kind;
    final page = q.page;
    final genreId = q.genreId;
    final regionId = q.regionId;
    final languageId = q.languageId;
    final yearId = q.yearId;
    final currentDate = isoDateToday();
    final hashedKey = sha256Hex('$page$_index${js(genreId)}${js(regionId)}${js(languageId)}${js(yearId)}');

    void apply(List<dynamic> results, dynamic totalPages, dynamic totalResults) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _collection = {
          'index': _index,
          'actual': kind.api,
          'api': 'discover/${kind.api}',
          'type': kind.api,
          'results': asMapList(results),
          'page': page,
          'total_pages': toNum(totalPages).toInt(),
          'total_results': toNum(totalResults).toInt(),
        };
      });
    }

    Future<void> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      var url = '${k.movieDb}discover/${kind.api}?api_key=${k.apiKey}&language=en-US&page=$page'
          '&with_genres=$genreId&with_origin_country=$regionId&sort_by=popularity.desc'
          '&with_original_language=$languageId&primary_release_year=$yearId';
      // TMDB ignores primary_release_year on discover/tv; the TV year filter needs first_air_date_year.
      if (kind.isTv && yearId != 0) url += '&first_air_date_year=$yearId';
      final data = await Http.getJson(url);
      if (data is! Map) return;
      final results = data['results'];
      if (results is! List || results.isEmpty) return;
      apply(results, data['total_pages'], data['total_results']);
      Gql.mutate(_insertMoviesMutation, {
        'page': page,
        'results': results,
        'total_pages': data['total_pages'],
        'total_results': data['total_results'],
        'data': {
          'genre': genreId,
          'region': regionId,
          'language': languageId,
          'year': yearId,
          'index': _index,
          'date': currentDate,
          'type': kind.api,
        },
        'hashedKey': hashedKey,
      }).then((r) {
        final res = r?['addMovies'];
        if (res is Map) {
          debugPrint(res['success'] == true
              ? 'Movies successfully inserted into MySQL: ${res['message']}'
              : 'Failed to insert movies into MySQL: ${res['message']}');
        }
      });
    }

    final fetched = await Gql.query(_fetchMoviesQuery, {
      'page': page,
      'data': {
        'genre': genreId,
        'year': yearId,
        'region': regionId,
        'language': languageId,
        'index': _index,
        'date': currentDate,
        'type': kind.api,
      },
      'hashedKey': hashedKey,
    });
    if (!mounted || seq != _seq) return;
    final movie = fetched?['movie'];
    if (movie is! Map) return freshFetch();
    final results = movie['results'];
    if (movie['success'] == true && results is List && results.length < 20) {
      return freshFetch(); // less items
    } else if (movie['error'] == 'insert movies' || movie['error'] == 'no records found') {
      return freshFetch();
    } else if (results is! List) {
      return freshFetch();
    } else {
      apply(results, movie['total_pages'], movie['total_results']);
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item.idInt;
    Nav.push(context, widget.kind.isTv ? Routes.tvId : Routes.moviesId, {'id': id});
    await RemoteService.instance.route(widget.kind.isTv ? TvPaths.tvId : TvPaths.moviesId, {'id': id});
  }

  void _onPageChange(int newPage) {
    // RN SWEETPAGE reset every filter when paging; keep the active ones instead.
    _intitializeMovies(DiscoverQuery(
      page: newPage,
      genreId: '${_selectedFilters['genreId'] ?? ''}',
      regionId: '${_selectedFilters['regionId'] ?? ''}',
      languageId: '${_selectedFilters['languageId'] ?? ''}',
      yearId: toNum(_selectedFilters['yearId']).toInt(),
    ));
  }

  Widget _card(Map<String, dynamic> item, double width) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaCard(item: item, onTap: () => _open(item)),
          InkWell(
            onTap: () => _open(item),
            child: const SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.movie_outlined, color: Colors.white, size: 20),
                    Text('play', style: TextStyle(color: Colors.white)),
                  ],
                ),
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
    final c = _collection;
    final results = (c?['results'] as List<Map<String, dynamic>>?) ?? const [];
    return SafeArea(
      child: ListView(
        children: [
          Controllers(
            intitializeMovies: _intitializeMovies,
            selectedFilters: _selectedFilters,
            onSelectedFiltersChanged: (m) => setState(() => _selectedFilters = m),
            type: widget.kind.api,
            extra: widget.kind.api,
          ),
          if (c != null) ...[
            const SizedBox(height: 8),
            SectionHeader(_index.replaceFirst('_', ' ')),
            SweetPage(
              page: c['page'] as int,
              totalPages: c['total_pages'] as int,
              onPageChange: _onPageChange,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 8),
              child: Wrap(
                spacing: w * 0.01 + 10,
                runSpacing: 10,
                children: [for (final m in results) _card(m, w * 0.30)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
