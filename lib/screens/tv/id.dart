// Port of mobile/app/(tabs)/tv/id.tsx
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show FetchPolicy;

import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/comments_section.dart';
import '../../widgets/common.dart';
import '../../widgets/picture.dart';
import '../movies/detail_common.dart';

/// Web serie.jsx FETCH_SEASON_ONE_QUERY, trimmed: season 1's episodes with their UKO copy (url).
const String _seasonOneQuery = r'''
  query Season($id: Int!) {
    season(id: $id) {
      episodes { episode_number id name season_number url { fileName week quality } }
      id
      success
    }
  }
''';

/// Web serie.jsx FETCH_COMINED_QUERY: the cached series, its image and its own
/// credits in one call. The RN port read `moviePayload` here (a *movie* row
/// looked up by the TV id) and stored the show through addMovie as a movie.
const String _tvPayloadQuery = r'''
        query TvPayload (
            $image: IMAGE_TV_ARGUMENTS!
            $tv: SINGLE_TV_ARGUMENTS!
            $credit: CREDIT_ITEM_TV_ARGUMENTS!
        ) {
            tvPayload(
                image: $image,
                tv: $tv,
                credit: $credit
            ) {
                image {
                    data { id path logo }
                    success
                    error
                }
                tv {
                    adult
                    backdrop_path
                    created_by { id credit_id name gender profile_path }
                    episode_run_time
                    first_air_date
                    genres { id name }
                    homepage
                    id
                    in_production
                    languages
                    last_air_date
                    last_episode_to_air { name air_date episode_number season_number }
                    name
                    next_episode_to_air { name air_date episode_number season_number }
                    networks { id logo_path name origin_country }
                    number_of_episodes
                    number_of_seasons
                    origin_country
                    original_language
                    original_name
                    overview
                    popularity
                    poster_path
                    production_companies { id logo_path name origin_country }
                    production_countries { iso_3166_1 name }
                    seasons { episode_count id name season_number vote_average }
                    spoken_languages { english_name iso_639_1 name }
                    status
                    tagline
                    type
                    vote_average
                    vote_count
                    message
                    success
                }
                credit {
                    cast {
                        adult gender id known_for_department name original_name
                        popularity profile_path cast_id character credit_id order
                    }
                    crew {
                        adult gender id known_for_department name original_name
                        popularity profile_path credit_id department job
                    }
                    success
                    error
                    message
                }
                success
                error
            }
        }
    ''';

/// Web serie.jsx addTV: stores the whole TMDB /tv/{id} response.
const String _addTvMutation = r'''
        mutation addTV($single:COLLECT_TV_INPUT) {
            addTV(single:$single) {
                success
                message
            }
        }
    ''';

class TvDetailScreen extends StatefulWidget {
  const TvDetailScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends State<TvDetailScreen> {
  static const _kind = MediaKind.tv;

  Map<String, dynamic>? _movie;
  String? _images;
  Map<String, dynamic>? _credits;
  bool _playlist = false;
  bool _feedbackFor = false;
  // PRD #11: S1E1 when it has its own UKO copy - "start a reaction" shows only then (web serie.jsx reactionReady)
  Map<String, dynamic>? _reactionEpisode;

  String get _idStr => P.str(widget.params, 'id') ?? '';
  int? get _idInt => P.intOf(widget.params, 'id');

  @override
  void initState() {
    super.initState();
    _oneRing();
  }

  // ---------------------------------------------------------------- data

  Future<void> _oneRing() async {
    final k = KeyService.instance;
    await k.ready;
    final data = await Gql.query(_tvPayloadQuery, {
      'tv': {'id': _idStr},
      'image': {'type': _kind.api, 'episode': -1, 'season': -1, 'id': _idInt ?? -1},
      'credit': {'id': _idInt ?? -1, 'season': -1, 'episode': -1},
    });
    final payload = data?['tvPayload'];
    Map<String, dynamic>? part(String key) =>
        payload is Map && payload[key] is Map ? Map<String, dynamic>.from(stripTypename(payload[key]) as Map) : null;

    _movieRing(part('tv'));
    _imageRing(part('image'));
    _creditRing(part('credit'));
  }

  /// Web serie.jsx movieRing: the server answers seasons:null for a show it has
  /// not got in full or that went stale (7 days while airing, 30 once ended).
  Future<void> _movieRing(Map<String, dynamic>? payload) async {
    Map<String, dynamic>? data;
    if (payload != null && truthy(payload['success']) && payload['seasons'] != null) {
      data = payload;
    } else {
      final k = KeyService.instance;
      final json = await Http.getJson('${k.movieDb}tv/$_idStr?api_key=${k.apiKey}');
      if (json is! Map) return;
      data = Map<String, dynamic>.from(json);
      Gql.mutate(_addTvMutation, {'single': data}).then((r) {
        final res = r?['addTV'];
        if (res is! Map || !truthy(res['success'])) debugPrint('Failed to insert tv into MySQL: $res');
      });
    }
    if (!mounted) return;
    setState(() => _movie = data);
    _findReactionEpisode(data);
    if (truthy(data['id']) && !_feedbackFor) {
      _feedbackFor = true;
      isInPlaylist(data['id'], _kind).then((inList) {
        if (inList && mounted) setState(() => _playlist = true);
      });
    }
  }

  Future<void> _imageRing(Map<String, dynamic>? payload) async {
    final k = KeyService.instance;
    String? path;
    if (payload != null && truthy(payload['success']) && payload['data'] is Map) {
      path = (payload['data'] as Map)['path']?.toString();
    } else {
      path = await freshImagePath(
          movieDb: k.movieDb, apiKey: k.apiKey, kind: _kind, idStr: _idStr, idInt: _idInt);
    }
    if (mounted) setState(() => _images = path);
  }

  static Map<String, dynamic> _normalizeCast(Map<String, dynamic> c) => {
        'id': or([c['id'], 0]),
        'name': or([c['name'], c['original_name'], '']),
        'original_name': or([c['original_name'], c['name'], '']),
        'profile_path': or([c['profile_path'], null]),
        'character': or([
          c['character'],
          c['roles'] is Map ? (c['roles'] as Map)['character'] : null,
          '',
        ]),
        'cast_id': or([c['cast_id'], null]),
        'credit_id': or([c['credit_id'], null]),
        'order': c['order'] ?? 0,
        'popularity': toNum(c['popularity']),
        'known_for_department': or([c['known_for_department'], null]),
      };

  Future<void> _creditRing(Map<String, dynamic>? payload) async {
    Map<String, dynamic> credits;
    if (payload != null && truthy(payload['success'])) {
      credits = payload;
    } else {
      final k = KeyService.instance;
      final json = await Http.getJson('${k.movieDb}tv/$_idStr/credits?api_key=${k.apiKey}');
      credits = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      insertCredits(asMapList(credits['cast']).map(_normalizeCast).toList(), _idInt, crew: asMapList(credits['crew']));
    }
    if (mounted) setState(() => _credits = credits);
  }

  // ------------------------------------------------------------- actions

  Future<void> _addToPlayList() async {
    final movie = _movie;
    if (movie == null) return;
    final status = await insertIntoPlaylist(movie['id'], _kind);
    if (status == null || !mounted) return;
    if (status) {
      showUkoAlert(context, 'Success', 'Added to playlist');
    } else {
      showUkoAlert(context, 'Error', 'Already in playlist');
    }
    setState(() => _playlist = true);
  }

  void _navRoute(String route, Map<String, dynamic> state, {String? tvPath}) {
    Nav.push(context, route, state);
    if (tvPath != null) RemoteService.instance.route(tvPath, state);
  }

  Future<void> _findReactionEpisode(Map<String, dynamic> movie) async {
    final seasons = asMapList(movie['seasons']);
    final one = seasons.where((s) => toNum(s['season_number']) == 1).firstOrNull;
    if (one == null || !truthy(one['id'])) return;
    final data = await Gql.query(_seasonOneQuery, {'id': toNum(one['id']).toInt()}, fetchPolicy: FetchPolicy.noCache);
    final season = data?['season'];
    if (season is! Map) return;
    final episode = asMapList(season['episodes']).where((e) => toNum(e['episode_number']) == 1).firstOrNull;
    final url = episode?['url'];
    if (url is Map && truthy(url['fileName']) && mounted) setState(() => _reactionEpisode = episode);
  }

  /// Opens S1E1, which goes straight on to the player with the reaction set-up (episode.dart startReaction)
  void _startReaction(Map<String, dynamic> movie) {
    final e = _reactionEpisode;
    if (e == null) return;
    _navRoute(
      Routes.tvEpisode,
      {
        'stream': 'series',
        'id': movie['id'],
        'episodeID': e['id'],
        'season': 1,
        'episode': 1,
        'name': movie['name'],
        'background': _images,
        'anime': isAnime(movie),
        'startReaction': true,
      },
      tvPath: TvPaths.tvEpisode,
    );
  }

  void _openSeason(Map<String, dynamic> movie, Map<String, dynamic> season) {
    _navRoute(
      Routes.tvSeason,
      {
        'stream': 'series',
        'id': movie['id'],
        'seasonID': season['id'],
        'season': season['season_number'],
        'name': movie['name'],
        'background': _images,
        'anime': isAnime(movie),
      },
      tvPath: TvPaths.tvSeason,
    );
  }

  // ------------------------------------------------------------------ UI

  static const _white = TextStyle(color: Colors.white);

  @override
  Widget build(BuildContext context) {
    final movie = _movie;
    final credits = _credits;
    if (movie == null || credits == null) return const LoadingView();
    final itemW = MediaQuery.of(context).size.width * 0.45;
    final seasons = asMapList(movie['seasons']);
    return ListView(
      key: ValueKey(_idStr),
      padding: const EdgeInsets.only(top: 16, bottom: 128),
      children: [
        _header(movie),
        const SizedBox(height: 16),
        const Text('SEASONS',
            style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
        SizedBox(
          height: 86,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: seasons.length,
            itemBuilder: (context, i) => SizedBox(width: itemW, child: _seasonCard(movie, seasons[i])),
          ),
        ),
        const Text('CAST', style: _white),
        CastRow(
          cast: asMapList(credits['cast']),
          // RN tv/id navRoute had no TV emit for people (only similar /
          // recommendation / season); kept as-is.
          onTap: (item) => _navRoute(Routes.peopleId, {'id': item['id']}),
        ),
        // movies PRD #4: viewers' comments on this TMDB series
        if ((_idInt ?? toNum(movie['id']).toInt()) > 0)
          CommentsSection(type: 'tv', id: _idInt ?? toNum(movie['id']).toInt()),
      ],
    );
  }

  Widget _seasonCard(Map<String, dynamic> movie, Map<String, dynamic> item) {
    final count = item['episode_count'];
    return InkWell(
      onTap: () => _openSeason(movie, item),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.white, width: 2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _white),
            Text(
              'season ${js(item['season_number'])} || (${js(count)} ${toNum(count) > 1 ? 'episodes' : '.episode'})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _white,
            ),
            Row(children: [
              const Icon(Icons.star_border, size: 16, color: UkoColors.yellow),
              Text(' ${toNum(item['vote_average']).toStringAsFixed(1)}',
                  style: const TextStyle(color: UkoColors.yellow)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> movie) {
    final width = MediaQuery.of(context).size.width;
    final genres = asMapList(movie['genres']);
    final last = movie['last_episode_to_air'] is Map
        ? Map<String, dynamic>.from(movie['last_episode_to_air'] as Map)
        : <String, dynamic>{};
    String lv(String k) => last[k] == null ? '' : js(last[k]);
    final runTimes = movie['episode_run_time'] is List ? movie['episode_run_time'] as List : const [];
    final btnW = (width - 8) * 0.49;

    return Column(
      children: [
        Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: BlurredBackdrop(path: movie['backdrop_path']?.toString()),
            ),
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 40, top: 24),
                    child: SizedBox(
                      height: 200,
                      width: width * 0.4,
                      child: Picture(picture: movie['poster_path']?.toString(), fit: BoxFit.contain),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Text('${movie['name'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  // RN: `original_title || title` (movie fields, always empty for a TV show).
                  Text('${or([movie['original_title'], movie['title'], movie['original_name']]) ?? ''}',
                      style: _white),
                  if (truthy(movie['tagline']))
                    SizedBox(
                      width: double.infinity,
                      child: Text('${movie['tagline']}', textAlign: TextAlign.center, style: _white),
                    ),
                  Text('${movie['first_air_date'] ?? ''} | ${movie['last_air_date'] ?? ''}', style: _white),
                  if (toNum(movie['revenue']) > 0) ...[
                    const Text('Revenue', style: _white),
                    Text('\$${js(movie['revenue'])}', style: _white),
                  ],
                  Wrap(children: [
                    for (var i = 0; i < genres.length; i++)
                      Text('${genres[i]['name'] ?? ''} ${i < genres.length - 1 ? ' || ' : ''}',
                          style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
                  ]),
                  Text(truthy(movie['in_production']) ? 'airing' : 'ended', style: _white),
                  const Text('latest episode', style: _white),
                  Text(
                      '${lv('name')} || ${lv('air_date')} || ${lv('season_number')} || ${lv('episode_number')}',
                      style: _white),
                  Text('seasons || ${js(movie['number_of_seasons'])}', style: _white),
                  Text('episodes || ${js(movie['number_of_episodes'])}', style: _white),
                  Row(children: [
                    const Icon(Icons.star_border, size: 16, color: UkoColors.yellow),
                    if (truthy(movie['vote_average']))
                      Text(' ${toNum(movie['vote_average']).toStringAsFixed(1)}',
                          style: const TextStyle(color: UkoColors.yellow)),
                  ]),
                  if (runTimes.isNotEmpty)
                    Text(
                      toNum(runTimes[0]) > 60
                          ? '${toNum(runTimes[0]) ~/ 60}h ${toNum(runTimes[0]) % 60}min'
                          : '${js(runTimes[0])}min',
                      style: _white,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text('${or([movie['overview'], 'waiting for more content'])}',
                        textAlign: TextAlign.justify, style: _white),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            children: [
              SizedBox(
                width: btnW,
                child: PillButton(
                  label: 'trailers',
                  onTap: () => _navRoute(Routes.tvTrailer, {'id': movie['id'], 'title': movie['name'], 'background': _images}),
                ),
              ),
              // PRD #11: a reaction starts on S1E1, and only when it has its own UKO copy
              if (_reactionEpisode != null)
                SizedBox(
                  width: btnW,
                  child: PillButton(
                    label: ' start a reaction',
                    icon: Icons.groups,
                    onTap: () => _startReaction(movie),
                  ),
                ),
              SizedBox(
                width: btnW,
                child: PillButton(
                  label: 'similar',
                  onTap: () => _navRoute(Routes.tvSimilar, {'id': movie['id']}, tvPath: TvPaths.tvSimilar),
                ),
              ),
              SizedBox(
                width: btnW,
                child: PillButton(
                  label: 'recommended',
                  onTap: () =>
                      _navRoute(Routes.tvRecommendation, {'id': movie['id']}, tvPath: TvPaths.tvRecommended),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SizedBox(
            height: 50,
            width: double.infinity,
            child: Material(
              color: UkoColors.yellow,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _addToPlayList,
                child: Center(
                  child: Text(_playlist ? 'Added to Playlist' : 'Add to Playlist',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
