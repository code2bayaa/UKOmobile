// Port of mobile/components/home/box.jsx (BOX):
// "airing" tv shows (GraphQL cache first, TMDB fallback) fed into CLIPS.
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import 'clips.dart';

const String _fetchTvQuery = r'''
        query Tv(
            $page: Int!,
            $genre : String!,
            $year : Int!,
            $region : String!,
            $language : String!,
            $index : String!,
            $date:String!,
            $hashedKey:String!
        ){
            tv(
                page:$page,
                genre:$genre,
                year:$year,
                region:$region,
                language:$language,
                index:$index,
                date:$date,
                hashedKey:$hashedKey
            ) {
                results {
                    adult
                    backdrop_path
                    genre_ids
                    id
                    origin_country
                    original_language
                    original_name
                    first_air_date
                    overview
                    popularity
                    poster_path
                    name
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

const String _insertTvsMutation = r'''
        mutation AddTVS(
            $page:Int!,
            $results:[ADD_TV_RESULTS_INPUT],
            $total_pages:Int!,
            $total_results:Int!,
            $data :TRACK_TV_DATA_INPUT,
            $type:String!,
            $hashedKey:String!
        ) {
            addTVS(
                page:$page,
                results:$results,
                total_pages:$total_pages,
                total_results:$total_results,
                data:$data,
                type:$type,
                hashedKey:$hashedKey
            ) {
                success
                message
            }
        }
    ''';

class Box extends StatefulWidget {
  const Box({super.key, required this.setClip, required this.mobileView});

  /// RN prop `setClip`.
  final ValueChanged<String> setClip;

  /// RN prop `mobileView` (receives the validated `{key, name, movieInfo}` clips).
  final ClipValidation mobileView;

  @override
  State<Box> createState() => _BoxState();
}

class _BoxState extends State<Box> {
  List<Map<String, dynamic>>? _movies;

  static const _tempMovies = [
    {'index': 'airing', 'api': 'tv/airing_today', 'page': 1},
  ];

  @override
  void initState() {
    super.initState();
    _run(runContent: const ['airing'], adjustable: true);
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

    // JS: page + genreId + regionId + languageId + yearId + actual_index + "tv"
    final hashedKey =
        sha256Hex('${js(tPage)}${js(genreId)}${js(regionId)}${js(languageId)}${js(yearId)}${actualIndex}tv');

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

      Gql.mutate(_insertTvsMutation, {
        'page': tPage,
        'results': results,
        'total_pages': data['total_pages'],
        'total_results': data['total_results'],
        'data': {
          'genre': genreId,
          'region': regionId,
          'language': languageId,
          'year': yearId,
          'index': actualIndex,
          'date': currentDate,
        },
        'hashedKey': hashedKey,
        'type': 'tv',
      }).then((res) {
        final r = res?['addTVS'];
        if (r is Map && r['success'] != true) debugPrint('Failed to insert tv into MySQL: ${r['message']}');
      });
      return true;
    }

    if (adjustable || genreId.isNotEmpty || regionId.isNotEmpty || languageId.isNotEmpty || yearId != 0) {
      final fetched = await Gql.query(_fetchTvQuery, {
        'page': tPage,
        'genre': genreId,
        'region': regionId,
        'language': languageId,
        'year': yearId,
        'index': actualIndex,
        'date': currentDate,
        'hashedKey': hashedKey,
      });

      final tv = fetched?['tv'];
      if (tv is Map) {
        final results = tv['results'];
        if (truthy(tv['success']) && results is List && results.length < 20) {
          return freshFetch(); // less items
        } else if (tv['error'] == 'insert tv' || tv['error'] == 'no records found') {
          return freshFetch();
        } else {
          // finally using cached data
          _upsert(actualIndex, {
            'index': actualIndex,
            'results': asMapList(stripTypename(results)),
            'page': tv['page'],
            'total_pages': tv['total_pages'],
            'total_results': tv['total_results'],
          });
          return true;
        }
      } else {
        return freshFetch();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // RN: <View className="w-[100%] h-[100%] mt-[0.5%]"><CLIPS .../></View> — CLIPS renders nothing.
    return Clips(
      updateClip: widget.setClip,
      addValidation: widget.mobileView,
      data: _movies,
      stream: 'tv',
    );
  }
}
