// Port of mobile/app/(tabs)/tv/season.tsx
import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import 'season_episode_parts.dart';

const String _fetchSeasonQuery = r'''
        query Season (
            $id: Int!
        ){
            season(
                id:$id
            ) {

                adult
                episodes {
                    air_date
                    episode_number
                    episode_type
                    id
                    name
                    overview
                    production_code
                    runtime
                    season_number,
                    show_id
                    still_path
                    vote_average
                    vote_count

                }
                air_date
                id
                name
                overview
                popularity
                poster_path
                vote_average
                vote_count
                season_number
                success
            }
        }
''';

const String _insertSeasonMutation = r'''
        mutation AddSeason(
            $single:COLLECT_SEASON_INPUT
        ) {
            addSeason(
                single:$single
            ) {
                success
                message
            }
        }
''';

const String _fetchCreditsQuery = r'''
        query Credits (
            $id: Int!
            $season: Int
            $episode: Int
        ){
            credits(
                id:$id
                season:$season
                episode:$episode
            ) {
                cast {
                    roles {
                        credit_id
                        character
                        episode_count
                    }
                    adult
                    gender
                    id
                    known_for_department
                    name
                    original_name
                    popularity
                    profile_path
                    cast_id
                    character
                    credit_id
                    total_episode_count
                    order
                }
                crew {
                    jobs {
                        credit_id
                        job
                        episode_count
                    }
                    adult
                    gender
                    id
                    known_for_department
                    name
                    original_name
                    popularity
                    profile_path
                    cast_id
                    character
                    credit_id
                    total_episode_count
                    order
                    department
                }
                success
                error
                message
            }
        }
''';

class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  Map<String, dynamic>? _serie;
  String? _images;
  Map<String, dynamic>? _credits;

  Map<String, dynamic> get _p => widget.params;
  dynamic get _id => _p['id'];
  dynamic get _serieName => _p['name'];
  dynamic get _seasonID => _p['seasonID'];
  dynamic get _season => _p['season'];
  String? get _background => P.str(_p, 'background');
  dynamic get _anime => _p['anime'];

  @override
  void initState() {
    super.initState();
    _graphImages();
    _fetchTV();
    _fetchCredits();
  }

  // ---------------------------------------------------------------- images
  Future<void> _graphImages() async {
    final keys = KeyService.instance;
    await keys.ready;

    Future<String> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/images?api_key=${keys.apiKey}');
      final data = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      num value = 0;
      String path = '';
      final backdrops = tallestImage(data['backdrops']);
      if (backdrops != null) {
        value = backdrops.height;
        if (backdrops.path != null) path = backdrops.path!;
      }
      final posters = tallestImage(data['posters']);
      if (posters != null && posters.height > value) {
        if (posters.path != null) path = posters.path!;
        value = posters.height;
      }
      final logos = tallestImage(data['logos']);
      if (logos != null && logos.height > value) {
        if (logos.path != null) path = logos.path!;
      }
      Gql.mutate(kAddImageMutation, {
        'meta_data': {
          'type': 'tv',
          'season': parseIntOr(_season, -1),
          'episode': -1,
          'id': parseIntOr(_id, -1),
        },
        'data': {'id': data['id'], 'path': path},
      });
      return path;
    }

    final fetched = await Gql.query(kFetchImageQuery, {
      'type': 'tv',
      'episode': -1,
      'season': parseIntOr(_season, -1),
      'id': parseIntOr(_id, -1),
    });
    final image = fetched?['image'];
    String? path;
    if (image is Map && truthy(image['success']) && image['data'] is Map) {
      path = (image['data'] as Map)['path'] as String?;
    } else {
      path = await freshFetch();
    }
    if (mounted) setState(() => _images = path);
  }

  // ---------------------------------------------------------------- season
  Future<void> _fetchTV() async {
    final keys = KeyService.instance;
    await keys.ready;

    Future<Map<String, dynamic>> freshFetch() async {
      final json =
          await Http.getJson('${keys.movieDb}tv/${js(_id)}/season/${js(_season)}?api_key=${keys.apiKey}');
      if (json is! Map) return <String, dynamic>{};
      final data = Map<String, dynamic>.from(json);
      final newData = Map<String, dynamic>.from(data);
      newData['episodes'] = asMapList(data['episodes'])
          .map((e) => Map<String, dynamic>.from(e)
            ..remove('crew')
            ..remove('guest_stars')
            ..remove('cast'))
          .toList();
      Gql.mutate(_insertSeasonMutation, {'single': newData}).then((d) {
        final r = d?['addSeason'];
        if (r is Map && truthy(r['success'])) {
          if (r['message'] == 'already inserted') debugPrint('season inserting already started...');
        } else {
          debugPrint('Failed to insert season into MySQL: ${r is Map ? r['message'] : null}');
        }
      });
      return data;
    }

    final fetched = await Gql.query(_fetchSeasonQuery, {'id': parseIntOr(_seasonID, -1)});
    final season = fetched?['season'];
    Map<String, dynamic> tv;
    if (season is Map && season['episodes'] == null) {
      // "first time..."
      tv = await freshFetch();
    } else if (season is Map && truthy(season['success'])) {
      tv = Map<String, dynamic>.from(season);
    } else {
      tv = await freshFetch();
    }
    if (mounted) setState(() => _serie = tv);
  }

  // ---------------------------------------------------------------- credits
  Future<void> _fetchCredits() async {
    final keys = KeyService.instance;
    await keys.ready;
    final idInt = parseIntOr(_id, 0);

    Future<Map<String, dynamic>> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/aggregate_credits?api_key=${keys.apiKey}');
      final creditsData = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};

      Map<String, dynamic> normalizeCast(Map<String, dynamic> c) => {
            'id': or([c['id'], 0]),
            'name': or([c['name'], c['original_name'], '']),
            'original_name': or([c['original_name'], c['name'], '']),
            'profile_path': or([c['profile_path'], null]),
            'character': or([c['character'], '']),
            'cast_id': or([c['cast_id'], null]),
            'credit_id': or([c['credit_id'], null]),
            'order': c['order'] ?? 0,
            'popularity': toNum(c['popularity']),
            'known_for_department': or([c['known_for_department'], null]),
          };

      Map<String, dynamic> normalizeCrew(Map<String, dynamic> c) => {
            'id': or([c['id'], 0]),
            'name': or([c['name'], c['original_name'], '']),
            'job': or([c['job'], c['jobs'] is Map ? (c['jobs'] as Map)['job'] : null, '']),
            'department': or([c['department'], null]),
            'profile_path': or([c['profile_path'], null]),
            'credit_id': or([c['credit_id'], null]),
            'order': c['order'] ?? 0,
            'popularity': toNum(c['popularity']),
          };

      void insert(String field, List<Map<String, dynamic>> all) {
        if (all.length > 100) {
          final chunks = chunkList(all, 100);
          for (var i = 0; i < chunks.length; i++) {
            Gql.mutate(kAddCreditsMutation, {field: chunks[i], 'id': idInt, 'season': parseIntOr(_season, -1), 'episode': -1, 'chunking': true, 'chunking_index': i});
          }
        } else {
          Gql.mutate(kAddCreditsMutation, {field: all, 'id': idInt, 'season': parseIntOr(_season, -1), 'episode': -1, 'chunking': false, 'chunking_index': 0});
        }
      }

      insert('cast', asMapList(creditsData['cast']).map(normalizeCast).toList());
      insert('crew', asMapList(creditsData['crew']).map(normalizeCrew).toList());
      return creditsData;
    }

    final fetched = await Gql.query(_fetchCreditsQuery, {'id': idInt, 'season': parseIntOr(_season, -1), 'episode': -1});
    final credits = fetched?['credits'];
    Map<String, dynamic> result;
    if (credits is Map && truthy(credits['success'])) {
      result = Map<String, dynamic>.from(credits);
    } else {
      result = await freshFetch();
    }
    if (mounted) setState(() => _credits = result);
  }

  // ---------------------------------------------------------------- navigation
  /// RN `navRoute`: push, and mirror on the TV for episode / similar /
  /// recommendation (the only urls season.tsx emitted for).
  void _navRoute(String route, Map<String, dynamic> state) {
    Nav.push(context, route, state);
    switch (route) {
      case Routes.tvEpisode:
        RemoteService.instance.route(TvPaths.tvEpisode, state);
      case Routes.tvSimilar:
        RemoteService.instance.route(TvPaths.tvSimilar, state);
      case Routes.tvRecommendation:
        RemoteService.instance.route(TvPaths.tvRecommended, state);
    }
  }

  // ---------------------------------------------------------------- UI
  Widget _episodeCard(Map<String, dynamic> item, double itemWidth) {
    return SizedBox(
      width: itemWidth,
      height: 80,
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => _navRoute(Routes.tvEpisode, {
            'stream': 'series',
            'id': _id,
            'episodeID': item['id'],
            'season': item['season_number'],
            'episode': item['episode_number'],
            'name': _serieName,
            'background': _images,
            'anime': _anime,
          }),
          child: Container(
            constraints: BoxConstraints(minWidth: itemWidth * 0.6, minHeight: 80),
            margin: EdgeInsets.all(itemWidth * 0.005),
            padding: const EdgeInsets.only(left: 4),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Colors.white, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${item['name'] ?? ''}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                Text('episode ${js(item['episode_number'])}', style: const TextStyle(color: Colors.white)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_border, size: 16, color: UkoColors.yellow),
                    Text(' ${toNum(item['vote_average']).toStringAsFixed(1)}',
                        style: const TextStyle(color: UkoColors.yellow)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> serie) {
    return DetailHeader(
      background: _background,
      poster: serie['poster_path'] as String?,
      details: [
        Text('${serie['name'] ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('${serie['air_date'] ?? ''}', style: const TextStyle(color: Colors.white)),
        OverviewText(serie['overview']),
      ],
      buttons: [
        PillButton(
          label: 'trailers',
          onTap: () => _navRoute(Routes.tvTrailer, {
            'id': _id,
            'season': serie['season_number'],
            'background': _images,
          }),
        ),
        PillButton(
          label: 'similar',
          onTap: () => _navRoute(Routes.tvSimilar, {'stream': 'series', 'id': _id, 'background': _images}),
        ),
        PillButton(
          label: 'recommended',
          onTap: () => _navRoute(Routes.tvRecommendation, {'stream': 'series', 'id': _id, 'background': _images}),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final serie = _serie;
    final credits = _credits;
    if (serie == null || credits == null) return const LoadingView();

    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    final episodes = asMapList(serie['episodes']);
    final cast = asMapList(credits['cast']);

    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        _header(serie),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('EPISODES',
              style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
        ),
        SizedBox(
          height: 80 + 16 + 8,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            itemCount: episodes.length,
            itemBuilder: (context, i) => _episodeCard(episodes[i], itemWidth),
          ),
        ),
        const Text('CAST', style: TextStyle(color: Colors.white)),
        CreditRow(
          items: cast,
          onTap: (item) => _navRoute(Routes.peopleId, {'id': item['id']}),
        ),
        const SizedBox(height: 128), // pb-32
      ],
    );
  }
}
