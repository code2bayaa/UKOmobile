// Port of mobile/app/(tabs)/movies/similar.tsx, movies/recommendation.tsx,
// tv/similar.tsx and tv/recommendation.tsx (one screen, parameterised by
// [MediaKind] + [RelatedMode]).
import 'dart:ui' show ImageFilter;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/picture.dart';

enum RelatedMode { similar, recommendation }

const String _resultsFields = r'''
                page
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
                total_pages
                total_results
                success
                error
                message
''';

/// FETCH_MOVIE_QUERY. Only the operation name differs between the four RN
/// files: SimilarMovies (movie+tv similar), recommendedMovies (movies/
/// recommendation), RecommendedMovies (tv/recommendation).
String _fetchQuery(MediaKind kind, RelatedMode mode) {
  final op = mode == RelatedMode.similar
      ? 'SimilarMovies'
      : (kind.isTv ? 'RecommendedMovies' : 'recommendedMovies');
  final field = mode == RelatedMode.similar ? 'similarMovies' : 'recommendedMovies';
  return '''
        query $op(
            \$id:ID!
            \$page:Int!
            \$type:String!
        ){
            $field(
                id:\$id
                page:\$page
                type:\$type
            ){
$_resultsFields            }
        }
    ''';
}

/// INSERT_MOVIE_MUTATION (addSimilarMovies / addRecommendedMovies).
String _insertMutation(RelatedMode mode) {
  final name = mode == RelatedMode.similar ? 'addSimilarMovies' : 'addRecommendedMovies';
  final input =
      mode == RelatedMode.similar ? 'ADD_SIMILAR_MOVIE_RESULTS_INPUT' : 'ADD_RECOMMENDED_MOVIE_RESULTS_INPUT';
  return '''
        mutation $name(
            \$page:Int!
            \$id:ID!
            \$results:[$input]
            \$total_results:Int!
            \$total_pages:Int!
            \$type:String!
        ){
            $name(
                page:\$page
                id:\$id
                results:\$results
                total_pages:\$total_pages
                total_results:\$total_results
                type:\$type
            ){
                success
                message
                error
            }
        }
    ''';
}

class RelatedScreen extends StatefulWidget {
  const RelatedScreen({super.key, required this.kind, required this.mode, this.params = const {}});
  final MediaKind kind;
  final RelatedMode mode;
  final Map<String, dynamic> params;

  @override
  State<RelatedScreen> createState() => _RelatedScreenState();
}

class _RelatedScreenState extends State<RelatedScreen> {
  /// `similar` / `recommendations` state (the TMDB / GraphQL page object).
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _results = [];

  String get _idStr => P.str(widget.params, 'id') ?? '';
  int get _idInt => P.intOf(widget.params, 'id') ?? -1;
  String get _gqlField => widget.mode == RelatedMode.similar ? 'similarMovies' : 'recommendedMovies';
  String get _mutationField => widget.mode == RelatedMode.similar ? 'addSimilarMovies' : 'addRecommendedMovies';
  String get _tmdbSegment => widget.mode == RelatedMode.similar ? 'similar' : 'recommendations';

  @override
  void initState() {
    super.initState();
    _fetchMain(1);
  }

  void _set(Map<String, dynamic> data) {
    if (!mounted) return;
    // The RN carousel did `results.sort(...)` in place, which also re-ordered
    // the list below it; sort once here for the same visible result.
    final results = asMapList(data['results'])
      ..sort((a, b) => toNum(b['vote_average']).compareTo(toNum(a['vote_average'])));
    setState(() {
      _data = data;
      _results = results;
    });
  }

  Future<void> _fetchMain(int page) async {
    final k = KeyService.instance;
    await k.ready;
    final type = widget.kind.api;
    final api = '${k.movieDb}$type/$_idStr/$_tmdbSegment?api_key=${k.apiKey}&page=$page';

    Future<void> freshFetch() async {
      final json = await Http.getJson(api);
      if (json is! Map) return;
      final data = Map<String, dynamic>.from(json);
      _set(data);
      if (toNum(data['total_results']) < 2) {
        Gql.mutate(_insertMutation(widget.mode), {...data, 'type': type, 'page': page, 'id': _idInt}).then((r) {
          final res = r?[_mutationField];
          if (res is Map && truthy(res['success'])) {
            debugPrint('Movie successfully inserted into MySQL: ${res['message']}');
          } else {
            debugPrint('Failed to insert movies into MySQL: $res');
          }
        });
      }
    }

    if (_data == null) {
      final fetched = await Gql.query(_fetchQuery(widget.kind, widget.mode), {
        'page': page,
        'type': type,
        'id': _idInt,
      });
      final cached = fetched?[_gqlField];
      if (cached is Map && truthy(cached['success'])) {
        _set(Map<String, dynamic>.from(stripTypename(cached) as Map));
      } else {
        await freshFetch();
      }
    }
  }

  void _open(Map<String, dynamic> item) {
    // tv/recommendation.tsx pushed "/movies/id" for TV results (and its emit
    // regex /tv/ then never matched) — fixed to the TV detail screen.
    final tv = widget.kind.isTv;
    Nav.push(context, tv ? Routes.tvId : Routes.moviesId, {'id': item['id']});
    RemoteService.instance.route(tv ? TvPaths.tvId : TvPaths.moviesId, {'id': item['id']});
  }

  @override
  Widget build(BuildContext context) {
    // RN only rendered when results.length > 2 and otherwise spun forever;
    // the port shows whatever came back once loaded.
    if (_data == null) return const LoadingView();
    if (_results.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(color: Colors.white)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _carousel(context);
        return _row(context, _results[i - 1]);
      },
    );
  }

  Widget _carousel(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return CarouselSlider.builder(
      itemCount: _results.length,
      options: CarouselOptions(
        height: 250,
        viewportFraction: ((width / 2) / width).clamp(0.2, 1.0),
        enableInfiniteScroll: true,
        autoPlay: true,
        autoPlayInterval: const Duration(milliseconds: 3000),
        autoPlayAnimationDuration: const Duration(milliseconds: 800),
        padEnds: false,
      ),
      itemBuilder: (context, index, _) {
        final item = _results[index];
        return Container(
          width: width / 2,
          margin: const EdgeInsets.only(right: 4),
          decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)]),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Picture(picture: or([item['poster_path'], item['profile_path']])?.toString()),
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${or([item['title'], item['original_title'], item['name'], item['original_name']]) ?? ''}',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_border, size: 16, color: UkoColors.yellow),
                      Text(' ${toNum(item['vote_average']).toStringAsFixed(1)}',
                          style: const TextStyle(color: UkoColors.yellow)),
                    ]),
                    InkWell(
                      onTap: () => _open(item),
                      child: const SizedBox(
                        height: 60,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.visibility_outlined, size: 18, color: Colors.white),
                          Text(' watch', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> item) {
    final width = MediaQuery.of(context).size.width;
    final overview = '${item['overview'] ?? ''}';
    return Padding(
      padding: EdgeInsets.only(top: width * 0.02),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // RN: uri = IMG_POSTER + backdrop_path (no null check).
            Picture(picture: item['backdrop_path']?.toString()),
            Row(
              children: [
                SizedBox(
                  width: width * 0.4,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        alignment: Alignment.center,
                        child: FractionallySizedBox(
                          heightFactor: 0.85,
                          widthFactor: 1,
                          child: Picture(picture: item['poster_path']?.toString(), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black.withValues(alpha: 0.65),
                          Colors.black.withValues(alpha: 0.80),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${overview.length > 200 ? overview.substring(0, 200) : overview}...',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${or([item['name'], item['title']]) ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 30, color: UkoColors.yellow, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _open(item),
                          child: const Text('👁 watch', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
