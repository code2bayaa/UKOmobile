// Port of mobile/components/home/latest.jsx (LATEST): auto-playing carousel
// of movies released in the last 7 days for a platform filter.
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../widgets/picture.dart';
import '../../core/theme.dart';

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

class LatestCarousel extends StatefulWidget {
  const LatestCarousel({super.key, required this.api, required this.wireframe});

  /// Extra TMDB discover query string, e.g. `&with_watch_providers=8&watch_region=US`.
  final String api;

  /// Platform slug used in the hash (`"latest" + wireframe + date ...`).
  final String wireframe;

  @override
  State<LatestCarousel> createState() => _LatestCarouselState();
}

class _LatestCarouselState extends State<LatestCarousel> {
  List<Map<String, dynamic>> _movies = [];

  @override
  void initState() {
    super.initState();
    _init(runContent: const ['latest movie'], adjustable: true);
  }

  static const _temp = {
    'latest movie': {'api': 'discover/movie', 'type': 'movie'},
  };

  Future<void> _init({required List<String> runContent, int? page, bool adjustable = false}) async {
    final currentDate = isoDateToday();
    var hashed = 'latest${widget.wireframe}$currentDate';
    final movieWrap = <Map<String, dynamic>>[];
    for (final actualIndex in runContent) {
      final p = page ?? 1;
      hashed += '$p$actualIndex';
      movieWrap.add({'page': p, 'index': actualIndex, 'date': currentDate, 'type': _temp[actualIndex]!['type']});
    }
    final hashedKey = sha256Hex(hashed);
    if (!adjustable) return;

    Future<void> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final insertContent = (await Future.wait(runContent.map((actualIndex) async {
        final p = page ?? 1;
        final t = _temp[actualIndex]!;
        final formatted = DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String().substring(0, 10);
        final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
        final json = await Http.getJson(
            '${k.movieDb}${t['api']}?api_key=${k.apiKey}&language=en-US&page=$p${widget.api}&sort_by=first_air_date.desc&release_date.gte=$formatted&release_date.lte=$today');
        final results = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
        if (results.isEmpty) return null;
        if (mounted) {
          setState(() {
            final list = [..._movies];
            final i = list.indexWhere((m) => m['index'] == actualIndex);
            if (i > -1) {
              list[i] = {...list[i], 'results': results};
            } else {
              list.add({
                'index': actualIndex,
                'results': results,
                'api': t['api'],
                'page': p,
                'total_pages': json['total_pages'],
                'total_results': json['total_results'],
                'type': t['type'],
              });
            }
            _movies = list;
          });
        }
        return <String, dynamic>{
          'page': p,
          'results': json['results'],
          'total_pages': json['total_pages'],
          'total_results': json['total_results'],
          'index': actualIndex,
          'type': t['type'],
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
      if (mounted) setState(() => _movies = asMapList(mc['data']));
    } else {
      await freshFetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final results = _movies.isNotEmpty ? asMapList(_movies.first['results']) : <Map<String, dynamic>>[];
    if (results.isEmpty) {
      return const SizedBox(
        height: 250,
        width: double.infinity,
        child: Center(child: Text('LOADING...', style: TextStyle(color: Colors.white))),
      );
    }
    return CarouselSlider.builder(
      itemCount: results.length,
      options: CarouselOptions(
        height: 250,
        viewportFraction: 1,
        enableInfiniteScroll: true,
        autoPlay: true,
        autoPlayInterval: const Duration(milliseconds: 3000),
        autoPlayAnimationDuration: const Duration(milliseconds: 800),
      ),
      itemBuilder: (context, i, _) {
        final item = results[i];
        return SizedBox(
          key: ValueKey('latest-item-$i'),
          width: width,
          height: 250,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text('${or([item['title'], item['original_title']]) ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 40, height: 1.1)),
                      ),
                      Text('${item['overview'] ?? ''}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.4,
                        child: SizedBox(
                          height: 40,
                          child: Material(
                            color: UkoColors.yellow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: const BorderSide(color: Colors.black, width: 1),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => Nav.push(context, Routes.moviesId, {'id': item.idInt}),
                              child: const Center(child: Text('watch', style: TextStyle(color: Colors.black))),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: Picture(picture: item['poster_path']?.toString(), fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
