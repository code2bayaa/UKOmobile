import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show FetchPolicy;

import '../core/http.dart';
import '../core/util.dart';
import '../routes.dart';
import '../services/graphql.dart';
import '../services/keys.dart';
import 'common.dart';
import 'picture.dart';

/// Port of components/home/celebraties.jsx — the auto-playing cast carousel at
/// the top of the Movies and TV tabs.
///
/// Cache scheme (unchanged): query `people` with
/// hashedKey = SHA256(page + "person" + jobId + (page-1) + mode). If that
/// misses (error "insert person"/"no records found" or < 5 results) the top 2
/// billed actors of every title in [actedMovies] are fetched from TMDB
/// credits and written back per collection with `addPerson` using
/// hashedKey = SHA256(page + "person" + jobId + i + mode).
class Celebraties extends StatefulWidget {
  const Celebraties({super.key, required this.actedMovies, required this.mode});

  /// The page's collections: `[{index, results:[{id,...}], ...}]`.
  final List<Map<String, dynamic>> actedMovies;

  /// "movie" | "tv"
  final String mode;

  @override
  State<Celebraties> createState() => _CelebratiesState();
}

class _CelebratiesState extends State<Celebraties> {
  List<Map<String, dynamic>> _themes = [];
  bool _running = false;
  bool _needFresh = false;

  static const fetchPersonQuery = r'''
    query People (
        $page: Int!,
        $genre : String!,
        $year : Int!,
        $region : String!,
        $language : String!,
        $index : String!,
        $date:String!,
        $hashedKey:String!
    ){
        people(
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
                gender
                profile_path
                id
                known_for_department
                name
                original_name
                popularity
                character
            }
            page
            total_pages
            total_results
            success
            error
            message
            people_page
            people_next
        }
    }
  ''';

  static const insertPersonMutation = r'''
    mutation AddPerson(
        $page:Int!,
        $results:[ADD_PERSON_RESULTS_INPUT],
        $total_pages:Int!,
        $total_results:Int!,
        $data :TRACK_PERSON_DATA_INPUT,
        $chunking:Boolean!
        $chunking_index:Int!
        $people_total_pages:Int!
        $type:String!,
        $hashedKey:String!
    ) {
        addPerson(
            page:$page,
            results:$results,
            total_pages:$total_pages,
            total_results:$total_results,
            data:$data,
            chunking:$chunking
            chunking_index:$chunking_index
            people_total_pages:$people_total_pages
            type:$type,
            hashedKey:$hashedKey
        ) {
            success
            message
            index
        }
    }
  ''';

  @override
  void initState() {
    super.initState();
    _initializeCelebrities(page: 1);
  }

  @override
  void didUpdateWidget(covariant Celebraties oldWidget) {
    super.didUpdateWidget(oldWidget);
    // RN re-ran the effect whenever actedMovies changed; here we only retry the
    // TMDB fallback once collections arrive, to avoid re-fetching every credit
    // list on each pagination.
    if (_needFresh && !_running && widget.actedMovies.isNotEmpty) {
      _needFresh = false;
      _freshFetch(page: 1, jobId: 'Actor');
    }
  }

  Future<void> _initializeCelebrities({required int page, String jobId = 'Actor'}) async {
    _running = true;
    try {
      final chunked = page - 1;
      final currentDate = isoDateToday();
      final hashedKey = sha256Hex('${page}person$jobId$chunked${widget.mode}');
      final fetched = await Gql.query(
        fetchPersonQuery,
        {
          'page': page,
          'genre': '',
          'region': '',
          'language': '',
          'year': 0,
          'index': widget.mode,
          'date': currentDate,
          'hashedKey': hashedKey,
        },
        fetchPolicy: FetchPolicy.noCache,
      );
      final people = fetched?['people'];
      if (people is Map) {
        final results = asMapList(people['results']);
        final err = people['error'];
        if (err == 'insert person' || err == 'no records found' || results.length < 5) {
          await _freshFetch(page: page, jobId: jobId);
        } else {
          if (mounted) setState(() => _themes = results.take(20).toList());
        }
      } else {
        await _freshFetch(page: page, jobId: jobId);
      }
    } finally {
      _running = false;
    }
  }

  Future<bool> _freshFetch({required int page, required String jobId}) async {
    final acted = widget.actedMovies;
    if (acted.isEmpty) {
      _needFresh = true;
      return false;
    }
    _running = true;
    try {
      final keys = KeyService.instance;
      await keys.ready;
      final currentDate = isoDateToday();
      final removeDuplicate = <dynamic>{};
      final peopleArray = <List<Map<String, dynamic>>>[];
      for (final collection in acted) {
        final results = asMapList(collection['results']);
        final perMovie = await Future.wait(results.map((r) async {
          final id = r['id'];
          if (removeDuplicate.contains(id)) return <Map<String, dynamic>>[];
          removeDuplicate.add(id);
          final api = widget.mode == 'tv' ? 'tv/$id/credits' : 'movie/$id/credits';
          final data = await Http.getJson('${keys.movieDb}$api?api_key=${keys.apiKey}&language=en-US');
          final cast = asMapList(data is Map ? data['cast'] : null);
          final crew = asMapList(data is Map ? data['crew'] : null);
          if (jobId == 'Actor') {
            cast.sort((a, b) => toNum(a['order']).compareTo(toNum(b['order'])));
            return cast.take(2).toList();
          }
          return crew
              .where((c) => c['job'] == jobId || c['known_for_department'] == jobId || c['department'] == jobId)
              .toList();
        }));
        peopleArray.add(perMovie.expand((e) => e).toList());
      }
      if (peopleArray.isNotEmpty) {
        final first = List<Map<String, dynamic>>.from(peopleArray[0])
          ..sort((a, b) => toNum(b['popularity']).compareTo(toNum(a['popularity'])));
        if (mounted) setState(() => _themes = first.take(20).toList());
        for (var i = 0; i < peopleArray.length; i++) {
          final hashedKey = sha256Hex('${page}person$jobId$i${widget.mode}');
          await Gql.mutate(insertPersonMutation, {
            'page': page,
            'results': peopleArray[i],
            'total_pages': peopleArray.length,
            'total_results': peopleArray[i].length,
            'chunking': true,
            'chunking_index': i,
            'people_total_pages': peopleArray.length,
            'data': {
              'genre': '',
              'region': '',
              'language': '',
              'year': 0,
              'index': widget.mode,
              'date': currentDate,
            },
            'type': 'person',
            'hashedKey': hashedKey,
          });
        }
      }
      return true;
    } finally {
      _running = false;
    }
  }

  void _open(Map<String, dynamic> item) {
    final state = {'id': item.idInt};
    // phone only - the TV app has no People pages to mirror
    Nav.push(context, Routes.peopleId, state);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: _themes.isEmpty
          ? const LoadingView()
          : CarouselSlider.builder(
              itemCount: _themes.length,
              options: CarouselOptions(
                height: 250,
                viewportFraction: (200 / width).clamp(0.2, 1.0),
                enableInfiniteScroll: true,
                autoPlay: true,
                autoPlayInterval: const Duration(milliseconds: 3000),
                autoPlayAnimationDuration: const Duration(milliseconds: 800),
                padEnds: false,
              ),
              itemBuilder: (context, i, _) {
                final item = _themes[i];
                return SizedBox(
                  width: 200,
                  height: 250,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Picture(picture: item['profile_path'] as String?, fit: BoxFit.contain),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${item['name'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 20, color: Colors.white)),
                              InkWell(
                                onTap: () => _open(item),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Text('Read', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
