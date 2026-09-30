// Port of mobile/components/home/blockbuster.jsx (BLOCKBUSTER):
// "now_playing" movies (GraphQL cache first, TMDB fallback) fed into CLIPS.
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import 'clips.dart';

const String _fetchMoviesQuery = r'''
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
                    id
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

class Blockbuster extends StatefulWidget {
  const Blockbuster({super.key, required this.setClip, required this.mobileView});

  /// RN prop `setClip`.
  final ValueChanged<String> setClip;

  /// RN prop `mobileView` (receives the validated `{key, name, movieInfo}` clips).
  final ClipValidation mobileView;

  @override
  State<Blockbuster> createState() => _BlockbusterState();
}

class _BlockbusterState extends State<Blockbuster> {
  List<Map<String, dynamic>>? _movies;

  static const _tempMovies = [
    {'index': 'now_playing', 'api': 'movie/now_playing', 'page': 1},
  ];

  @override
  void initState() {
    super.initState();
    _run(runContent: const ['now_playing'], adjustable: true);
  }

  void _run({
    required List<String> runContent,
    int? page,
    bool adjustable = false,
    String genreId = '',
    String regionId = '',
    String languageId = '',
    int yearId = 0,
  }) {
    for (final index in runContent) {
      _fetchMoviesFromApi(index, page, adjustable, genreId, regionId, languageId, yearId);
    }
  }

  void _upsert(String actualIndex, Map<String, dynamic> entry) {
    if (!mounted) return;
    setState(() {
      final updated = [...?_movies];
      final existing = updated.indexWhere((m) => m['index'] == actualIndex);
      if (existing > -1) {
        updated[existing] = {...updated[existing], 'results': entry['results']};
      } else {
        updated.add(entry);
      }
      _movies = updated;
    });
  }

  Future<bool?> _fetchMoviesFromApi(
    String actualIndex,
    int? page,
    bool adjustable,
    String genreId,
    String regionId,
    String languageId,
    int yearId,
  ) async {
    final currentDate = isoDateToday();
    final temp = _tempMovies.firstWhere((t) => t['index'] == actualIndex);
    final api = temp['api'] as String;
    final tPage = page ?? temp['page'] as int;

    // JS: page + genreId + regionId + languageId + yearId + actual_index + "movie"
    final hashedKey =
        sha256Hex('${js(tPage)}${js(genreId)}${js(regionId)}${js(languageId)}${js(yearId)}${actualIndex}movie');

    Future<bool> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final data = await Http.getJson(
        '${k.movieDb}$api?api_key=${k.apiKey}&language=en-US&page=$tPage&with_genres=$genreId'
        '&with_origin_country=$regionId&sort_by=popularity.desc&with_original_language=$languageId'
        '&primary_release_year=$yearId',
      );
      final results = data is Map && data['results'] is List ? data['results'] as List : const [];
      if (results.isEmpty) return false;

      _upsert(actualIndex, {
        'index': actualIndex,
        'results': asMapList(results),
        'api': api,
        'page': tPage,
        'total_pages': data['total_pages'],
        'total_results': data['total_results'],
      });

      Gql.mutate(_insertMoviesMutation, {
        'page': tPage,
        'results': results,
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
          'type': 'movie',
        },
      }).then((res) {
        final r = res?['addMovies'];
        if (r is Map) {
          if (r['success'] == true) {
            debugPrint('Movies successfully inserted into MySQL: ${r['message']}');
          } else {
            debugPrint('Failed to insert movies into MySQL: ${r['message']}');
          }
        }
      });
      return true;
    }

    if (adjustable || genreId.isNotEmpty || regionId.isNotEmpty || languageId.isNotEmpty || yearId != 0) {
      final fetched = await Gql.query(_fetchMoviesQuery, {
        'page': tPage,
        'data': {
          'genre': genreId,
          'year': yearId,
          'region': regionId,
          'language': languageId,
          'index': actualIndex,
          'date': currentDate,
          'type': 'movie',
        },
        'hashedKey': hashedKey,
      });

      final movie = fetched?['movie'];
      if (movie is Map) {
        final results = movie['results'];
        if (truthy(movie['success']) && results is List && results.length < 20) {
          return freshFetch(); // less items
        } else if (movie['error'] == 'insert movies' || movie['error'] == 'no records found') {
          return freshFetch();
        } else {
          // finally using cached data
          _upsert(actualIndex, {
            'index': actualIndex,
            'results': asMapList(stripTypename(results)),
            'page': movie['page'],
            'total_pages': movie['total_pages'],
            'total_results': movie['total_results'],
          });
          return true;
        }
      } else {
        return freshFetch();
      }
    }
    return null;
  }

  void _firstClip(String video) {
    debugPrint('first clip video key $video');
    widget.setClip(video);
  }

  @override
  Widget build(BuildContext context) {
    // RN: <View className="w-[100%] h-[100%] mt-[2%]"><CLIPS .../></View> — CLIPS renders nothing.
    return Clips(
      firstClip: _firstClip,
      updateClip: widget.setClip,
      addValidation: widget.mobileView,
      data: _movies,
      stream: 'movie',
    );
  }
}
