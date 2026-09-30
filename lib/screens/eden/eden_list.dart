// /eden/movies and /eden/series - an Eden studio catalogue in rows, the phone twin of
// web eden/movies.jsx and eden/series.jsx (and the TV's eden_list.dart). Each row is
// one index of edenMovieCollection (type movie or tv); scrolling to its end loads the
// next page. A title opens /eden/movies/id or /eden/series/id. Opened from the "eden"
// tile next to Netflix on the Movies and TV Shows pages. Above the rows sits the Eden
// actors carousel, the twin of the Blockbusters Celebraties strip (web eden CELEBRATIES).
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show FetchPolicy;

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';

const String _edenCollectionQuery = r'''
  query EdenMovieCollection($data: [EDEN_COLLECTION_TRACK_DATA_OUTPUT], $hashedKey: String!) {
    edenMovieCollection(data: $data, hashedKey: $hashedKey) {
      data {
        results {
          id original_title original_name title name overview poster_path backdrop_path
          release_date vote_average
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

class _Row {
  _Row(this.index, this.title);
  final String index;
  final String title;
  final List<Map<String, dynamic>> items = [];
  final ScrollController scroll = ScrollController();
  int page = 0;
  int totalPages = 0;
  bool loading = false;
}

class EdenListScreen extends StatefulWidget {
  const EdenListScreen({super.key, required this.kind});
  final MediaKind kind;

  @override
  State<EdenListScreen> createState() => _EdenListScreenState();
}

class _EdenListScreenState extends State<EdenListScreen> {
  late final List<_Row> _rows = [
    _Row('trending', 'trending'),
    _Row('popular', 'popular'),
    _Row('top_rated', 'top rated'),
  ];
  bool _loading = true;

  bool get _tv => widget.kind.isTv;
  String get _type => _tv ? 'tv' : 'movie';

  @override
  void initState() {
    super.initState();
    for (final row in _rows) {
      row.scroll.addListener(() {
        final p = row.scroll.position;
        if (p.pixels >= p.maxScrollExtent - 200) _more(row);
      });
    }
    _loadAll();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.scroll.dispose();
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _query(List<String> indexes, int page) async {
    final today = isoDateToday();
    final data = await Gql.query(
      _edenCollectionQuery,
      {
        'data': [
          for (final index in indexes) {'index': index, 'page': page, 'date': today, 'type': _type},
        ],
        'hashedKey': sha256Hex('eden-mobile$_type$today${indexes.join(',')}$page'),
      },
      fetchPolicy: FetchPolicy.networkOnly,
    );
    final collection = data?['edenMovieCollection'];
    return collection is Map ? asMapList(collection['data']) : const [];
  }

  void _apply(Map<String, dynamic> block) {
    final row = _rows.where((r) => r.index == block['index']).firstOrNull;
    if (row == null) return;
    final seen = row.items.map((m) => m['id']).toSet();
    row.items.addAll(asMapList(block['results']).where((m) => truthy(m['id']) && seen.add(m['id'])));
    row.page = toNum(block['page']).toInt();
    row.totalPages = toNum(block['total_pages']).toInt();
  }

  Future<void> _loadAll() async {
    final blocks = await _query(_rows.map((r) => r.index).toList(), 1);
    if (!mounted) return;
    setState(() {
      blocks.forEach(_apply);
      _loading = false;
    });
  }

  Future<void> _more(_Row row) async {
    if (row.loading || row.page >= row.totalPages) return;
    setState(() => row.loading = true);
    final blocks = await _query([row.index], row.page + 1);
    if (!mounted) return;
    setState(() {
      blocks.forEach(_apply);
      row.loading = false;
    });
  }

  void _open(Map<String, dynamic> item) =>
      Nav.push(context, _tv ? Routes.tvEden : Routes.moviesEden, {'id': item['id']});

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    final filled = _rows.where((r) => r.items.isNotEmpty).toList();
    if (filled.isEmpty) {
      return Center(
        child: Text('No Eden ${_tv ? 'series' : 'movies'} yet.', style: const TextStyle(color: UkoColors.divider)),
      );
    }
    final width = MediaQuery.of(context).size.width;
    final cardW = width * 0.4;
    final cardH = cardW * 1.5;
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 128),
      children: [
        const _EdenCelebraties(),
        for (final row in filled) ...[
          SectionHeader(row.title),
          SizedBox(
            height: cardH + 24,
            child: ListView.separated(
              controller: row.scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: row.items.length + (row.loading ? 1 : 0),
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i >= row.items.length) {
                  return SizedBox(
                    width: cardW / 2,
                    child: const Center(child: CircularProgressIndicator(color: UkoColors.yellow)),
                  );
                }
                return _PosterCard(item: row.items[i], width: cardW, height: cardH, onTap: () => _open(row.items[i]));
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// web eden POSTER: the studio's poster with the title on a blurred band at the bottom
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item, required this.width, required this.height, required this.onTap});
  final Map<String, dynamic> item;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = '${or([item['title'], item['name'], item['original_title'], item['original_name']]) ?? ''}';
    final poster = item['poster_path'];
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: UkoColors.gray800,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                EdenImage(path: poster is String ? poster : null, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.6, 1],
                      colors: [Colors.transparent, Color(0xD9000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eden studios' own cast, most followed first (POST /database/people/eden) - the
/// same auto-playing strip as widgets/celebraties.dart on the Blockbusters pages.
/// Hidden when the studio has no people yet. A card opens /eden/people/id.
class _EdenCelebraties extends StatefulWidget {
  const _EdenCelebraties();

  @override
  State<_EdenCelebraties> createState() => _EdenCelebratiesState();
}

class _EdenCelebratiesState extends State<_EdenCelebraties> {
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Http.postJson(Api.edenPeople, {'page': 1});
    if (!mounted) return;
    setState(() {
      if (res is Map && res['success'] == true) {
        _people = asMapList(res['results'])
            .where((p) => truthy(p['name']) || truthy(p['original_name']))
            .take(20)
            .toList();
      }
      _loading = false;
    });
  }

  void _open(Map<String, dynamic> p) =>
      Nav.push(context, Routes.edenPeopleId, {'id': p['id'], 'person_id': p['person_id'], 'eden': true});

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 250, child: LoadingView());
    if (_people.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.of(context).size.width;
    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: CarouselSlider.builder(
        itemCount: _people.length,
        options: CarouselOptions(
          height: 250,
          viewportFraction: (200 / width).clamp(0.2, 1.0),
          enableInfiniteScroll: _people.length > 1,
          autoPlay: _people.length > 1,
          autoPlayInterval: const Duration(milliseconds: 3000),
          autoPlayAnimationDuration: const Duration(milliseconds: 800),
          padEnds: false,
        ),
        itemBuilder: (context, i, _) {
          final p = _people[i];
          final photo = p['profile_path'];
          return GestureDetector(
            onTap: () => _open(p),
            child: SizedBox(
              width: 200,
              height: 250,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EdenImage(path: truthy(photo) ? '$photo' : null, fit: BoxFit.contain),
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
                          Text('${or([p['name'], p['original_name']]) ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 20, color: Colors.white)),
                          const Padding(
                            padding: EdgeInsets.all(2),
                            child: Text('Read', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
