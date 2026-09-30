// Port of mobile/app/(tabs)/tv/episode.tsx
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/prefs.dart';
import '../../services/profile.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/play_phone_prompt.dart';
import 'season_episode_parts.dart';
import '../../widgets/no_credits.dart';

const String _fetchEpisodeQuery = r'''
        query Episode (
            $id: Int!
        ){
            episode(
                id:$id
            ) {

                    air_date
                    episode_number
                    episode_type
                    id
                    name
                    overview
                    production_code
                    runtime
                    season_number,
                    url {
                        fileName
                        week
                        quality
                    }
                    still_path
                    vote_average
                    vote_count
                    success
            }
        }
''';

const String _insertEpisodeMutation = r'''
        mutation AddEpisode(
            $single:COLLECT_EPISODE_INPUT
        ) {
            addEpisode(
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
                guest_stars {
                    character
                    credit_id
                    order
                    adult
                    gender
                    id
                    known_for_department
                    name
                    original_name
                    popularity
                    profile_path
                }
                success
                error
                message
            }
        }
''';

const String _fetchImdbQuery = r'''
        query IMDB(
            $id: Int!
            $season_number: Int
            $episode_number: Int
        ){
            imdb(
                id:$id
                season_number:$season_number
                episode_number:$episode_number
            ){
                id
                imdb_id
                success
                error
                message
            }
        }
''';

const String _updateImdbMutation = r'''
    mutation UpdateIMDB(
      $id:Int!
      $external_ids:EXTERNAL_INPUT
      $season_number:Int
      $episode_number:Int
    ) {
        updateIMDB(
          id:$id
          external_ids:$external_ids
          season_number:$season_number
          episode_number:$episode_number
        ) {
          success
          message
        }
    }
''';

class EpisodeScreen extends StatefulWidget {
  const EpisodeScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  bool _layouts = false;
  bool _needsPhone = false; // in a play region, but the account's phone isn't (PRD #7)
  Map<String, dynamic>? _checkURL;
  Map<String, dynamic>? _serie;
  String? _images;
  Map<String, dynamic>? _credits;
  Map<String, dynamic>? _imdb;
  // ignore: unused_field
  bool? _playlist; // RN kept this for the (commented-out) playlist button.
  bool _opening = false;
  // from tv/id "start a reaction": open the player with the reaction set-up once this episode can play
  late bool _autoReaction = P.boolOf(widget.params, 'startReaction');

  Map<String, dynamic> get _p => widget.params;
  dynamic get _id => _p['id'];
  dynamic get _name => _p['name'];
  dynamic get _episodeID => _p['episodeID'];
  dynamic get _season => _p['season'];
  dynamic get _episode => _p['episode'];
  dynamic get _background => _p['background'];
  dynamic get _direct => _p['direct'];
  dynamic get _index => _p['index'];
  dynamic get _anime => _p['anime'];

  @override
  void initState() {
    super.initState();
    _runPlayGate();
    _fetchID();
    _graphImages();
    _fetchTV();
    _fetchCredits();
    _checkURLFN();
  }

  // ---------------------------------------------------------------- location
  /// PRD #7 play gate (services/profile.dart): device in Africa / Australia / Brazil and, signed
  /// in, a phone number from one of them. Replaces runLocale().
  Future<void> _runPlayGate() async {
    final gate = await playGate();
    if (!mounted) return;
    setState(() {
      _layouts = gate == PlayGate.allowed;
      _needsPhone = gate == PlayGate.needsPhone;
    });
  }

  // ---------------------------------------------------------------- imdb
  Future<void> _fetchID() async {
    if (_imdb != null) return;
    final keys = KeyService.instance;
    await keys.ready;
    final idInt = parseIntOr(_id, 0);

    Future<Map<String, dynamic>> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/episode/${js(_episode)}/external_ids?api_key=${keys.apiKey}');
      final imdbData = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      // Stored per season/episode on the series row (see updateIMDB), so the
      // series' own IMDb id is left alone. Only the EXTERNAL_INPUT fields are
      // sent: TMDB also returns facebook_id etc., which the input type rejects.
      Gql.mutate(_updateImdbMutation, {
        'external_ids': {
          'id': imdbData['id'],
          'imdb_id': imdbData['imdb_id'],
          'freebase_mid': imdbData['freebase_mid'],
          'freebase_id': imdbData['freebase_id'],
          'tvdb_id': imdbData['tvdb_id'],
          'tvrage_id': imdbData['tvrage_id']?.toString(),
          'wikidata_id': imdbData['wikidata_id'],
        },
        'id': idInt,
        'season_number': parseIntOr(_season, 0),
        'episode_number': parseIntOr(_episode, 0),
      });
      return imdbData;
    }

    final fetched = await Gql.query(_fetchImdbQuery, {
      'id': idInt,
      'season_number': parseIntOr(_season, 0),
      'episode_number': parseIntOr(_episode, 0),
    });
    final imdb = fetched?['imdb'];
    Map<String, dynamic> result;
    if (imdb is Map && truthy(imdb['success'])) {
      result = Map<String, dynamic>.from(imdb);
    } else {
      result = await freshFetch();
    }
    if (mounted) setState(() => _imdb = result);
  }

  // ---------------------------------------------------------------- images
  Future<void> _graphImages() async {
    final keys = KeyService.instance;
    await keys.ready;

    Future<String> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/episode/${js(_episode)}/images?api_key=${keys.apiKey}');
      final data = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      String path = '';
      final stills = tallestImage(data['stills']);
      if (stills != null && stills.path != null) path = stills.path!;
      Gql.mutate(kAddImageMutation, {
        'meta_data': {
          'type': 'tv',
          'season': parseIntOr(_season, -1),
          'episode': parseIntOr(_episode, -1),
          'id': parseIntOr(_id, -1),
        },
        'data': {'id': data['id'], 'path': path},
      });
      return path;
    }

    final fetched = await Gql.query(kFetchImageQuery, {
      'type': 'tv',
      'episode': parseIntOr(_episode, -1),
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

  // ---------------------------------------------------------------- episode
  Future<void> _fetchTV() async {
    final keys = KeyService.instance;
    await keys.ready;

    Future<Map<String, dynamic>> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/episode/${js(_episode)}?api_key=${keys.apiKey}');
      if (json is! Map) return <String, dynamic>{};
      final data = Map<String, dynamic>.from(json);
      final newData = Map<String, dynamic>.from(data)
        ..remove('crew')
        ..remove('guest_stars')
        ..remove('cast');
      Gql.mutate(_insertEpisodeMutation, {'single': newData}).then((d) {
        final r = d?['addEpisode'];
        if (r is Map && truthy(r['success'])) {
          if (r['message'] == 'already inserted') debugPrint('episode inserting already started...');
        } else {
          debugPrint('Failed to insert episode into MySQL: ${r is Map ? r['message'] : null}');
        }
      });
      return data;
    }

    /// RN `checkFeedback(id)` — marks the episode as already in the playlist.
    Future<void> checkFeedback(dynamic id) async {
      // POST-only route; the app token names the viewer
      final auth = await Http.postJson(Api.apiUrl, const <String, dynamic>{});
      if (auth is! Map || !truthy(auth['status'])) return;
      final res = await Http.postJson(Api.playlistSelect, {
        'id': id,
        'episodeID': _episodeID,
        'user': auth['user'],
        'season': _season,
        'episode': _episode,
        'type': 'episode',
      });
      if (res is Map && truthy(res['status']) && mounted) setState(() => _playlist = true);
    }

    final fetched = await Gql.query(_fetchEpisodeQuery, {'id': parseIntOr(_episodeID, -1)});
    final ep = fetched?['episode'];
    Map<String, dynamic> serie;
    if (ep is Map && ep.containsKey('air_date') && ep['air_date'] == null) {
      // "first time..."
      final tv = await freshFetch();
      serie = {...Map<String, dynamic>.from(ep), ...tv};
      checkFeedback(tv['id']);
    } else if (ep is Map && truthy(ep['success'])) {
      serie = Map<String, dynamic>.from(ep);
      checkFeedback(ep['id']);
    } else {
      serie = await freshFetch();
      checkFeedback(serie['id']);
    }
    if (mounted) setState(() => _serie = serie);
  }

  // ---------------------------------------------------------------- credits
  Future<void> _fetchCredits() async {
    final keys = KeyService.instance;
    await keys.ready;
    final idInt = parseIntOr(_id, 0);

    Future<Map<String, dynamic>> freshFetch() async {
      final json = await Http.getJson(
          '${keys.movieDb}tv/${js(_id)}/season/${js(_season)}/episode/${js(_episode)}/credits?api_key=${keys.apiKey}');
      final creditsData = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};

      Map<String, dynamic> normalizeCast(Map<String, dynamic> c) => {
            'id': or([c['id'], 0]),
            'name': or([c['name'], c['original_name'], '']),
            'original_name': or([c['original_name'], c['name'], '']),
            'profile_path': or([c['profile_path'], null]),
            'character': or([c['character'], c['roles'] is Map ? (c['roles'] as Map)['character'] : null, '']),
            'cast_id': or([c['cast_id'], null]),
            'credit_id': or([c['credit_id'], null]),
            'order': c['order'] ?? 0,
            'popularity': toNum(c['popularity']),
            'known_for_department': or([c['known_for_department'], null]),
          };

      final castAll = asMapList(creditsData['cast']).map(normalizeCast).toList();
      if (castAll.length > 100) {
        final chunks = chunkList(castAll, 100);
        for (var i = 0; i < chunks.length; i++) {
          Gql.mutate(kAddCreditsMutation, {'cast': chunks[i], 'id': idInt, 'season': parseIntOr(_season, -1), 'episode': parseIntOr(_episode, -1), 'chunking': true, 'chunking_index': i});
        }
      } else {
        Gql.mutate(kAddCreditsMutation, {'cast': castAll, 'id': idInt, 'season': parseIntOr(_season, -1), 'episode': parseIntOr(_episode, -1), 'chunking': false, 'chunking_index': 0});
      }
      return creditsData;
    }

    final fetched = await Gql.query(_fetchCreditsQuery, {'id': idInt, 'season': parseIntOr(_season, -1), 'episode': parseIntOr(_episode, -1)});
    final credits = fetched?['credits'];
    Map<String, dynamic> result;
    if (credits is Map && truthy(credits['success'])) {
      result = Map<String, dynamic>.from(credits);
    } else {
      result = await freshFetch();
    }
    if (mounted) setState(() => _credits = result);
  }

  // ---------------------------------------------------------------- fast stream check
  Future<void> _checkURLFN() async {
    final res = await Http.postJson(Api.checkUrl, {'type': 'episode', 'id': _episodeID});
    if (res is Map && truthy(res['status']) && res['data'] is Map && mounted) {
      setState(() => _checkURL = Map<String, dynamic>.from(res['data'] as Map));
    }
    debugPrint('creating fast stream...');
  }

  bool get _hasServerUrl => _serie != null && truthy(_serie!['url']);

  void _maybeAutoReaction() {
    if (!_autoReaction || !_layouts || _serie == null || !(_hasServerUrl || _checkURL != null)) return;
    _autoReaction = false;
    _openPlay(reaction: true);
  }

  // ---------------------------------------------------------------- play
  static int _currentWeek() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final pastDaysOfYear = now.difference(startOfYear).inMilliseconds / 86400000;
    // JS Date.getDay(): 0 = Sunday ... 6 = Saturday.
    return ((pastDaysOfYear + (startOfYear.weekday % 7) + 1) / 7).ceil();
  }

  /// JS `currentWeek > url.week` (undefined/null week -> false).
  static bool _weekPassed(int currentWeek, dynamic week) {
    if (week == null) return false;
    final w = week is num ? week : num.tryParse('$week');
    return w != null && currentWeek > w;
  }

  Map<String, dynamic> _streamState(Map<String, dynamic> serie) => {
        'stream': 'episode',
        'id': _episodeID,
        'serieID': _id,
        'name': _name,
        'season': serie['season_number'],
        'episode': serie['episode_number'],
        'background': _images,
        'date': serie['air_date'],
        'imdbId': _imdb?['imdb_id'],
        'anime': _anime,
      };

  Future<void> _goToSpeed(Map<String, dynamic> serie, {bool reaction = false}) async {
    final currentWeek = _currentWeek();
    final url = serie['url'];
    final check = _checkURL;
    if (url is Map && url['quality'] == 'CAM' && _weekPassed(currentWeek, url['week'])) {
      _navRoute(Routes.videoStream, _streamState(serie));
      return;
    }
    if (check != null && check['quality'] == 'CAM' && _weekPassed(currentWeek, check['week'])) {
      _navRoute(Routes.videoStream, _streamState(serie));
      return;
    }

    var hasCredits = false;
    var hasPaid = false;

    final paid = await Http.postJson(Api.userPaid, {
      'id': _episodeID,
      'email': await Prefs.user,
    });
    if (paid is Map) {
      debugPrint('${paid['message']}');
      if (truthy(paid['status'])) hasPaid = true;
    }

    final credits = await Http.getJson(Api.checkUserCredits);
    final sum = credits is Map ? credits['sum'] : null;
    // affordable for one movie | episode
    if (truthy(sum) && toNum(sum) > 49) hasCredits = true;

    if (!mounted) return;
    if (!hasCredits && !hasPaid) {
      if (await promptGuestSignUp(context) || !mounted) return;
      showUkoAlert(context, 'NO CREDITS', 'add more credits');
      return;
    }
    final dashSource = url is Map ? url : check;
    _navRoute(Routes.videoSpeed, {
      'stream': 'tv',
      'id': _episodeID,
      'name': _name,
      'season': serie['season_number'],
      'episode': serie['episode_number'],
      'background': _images,
      'dash': dashSource != null && dashSource.containsKey('dash'),
      'serieID': _id,
      'serie_name': _name,
      'date': serie['air_date'],
      'imdbId': _imdb?['imdb_id'],
      if (reaction) 'startParty': true,
    });
  }

  /// reaction: "start a reaction" - the player opens with the reaction set-up (speed.dart startParty, PRD #11)
  Future<void> _openPlay({bool reaction = false}) async {
    final serie = _serie;
    if (serie == null || _opening) return;
    if (reaction && !(_hasServerUrl || _checkURL != null)) return showUkoSnack(context, 'error', "Reactions need a UKO copy - this title only plays from an outside stream");
    _opening = true;
    try {
      if (_hasServerUrl || _checkURL != null) {
        await _goToSpeed(serie, reaction: reaction);
      } else if (truthy(_direct)) {
        _navRoute(Routes.videoPlay, {
          'id': _direct,
          'index': _index,
          'background': _background,
          'many': serie['episode_number'],
          'serieID': _id,
          'serie_name': _name,
        });
      } else {
        final airDate = serie['air_date'];
        _navRoute(Routes.videoStream, {
          ..._streamState(serie),
          'year': airDate is String ? (airDate.length >= 4 ? airDate.substring(0, 4) : airDate) : null,
        });
      }
    } finally {
      _opening = false;
    }
  }

  // ---------------------------------------------------------------- navigation
  /// RN `navRoute`: push, then mirror on the TV for speed / similar /
  /// recommendation / people / stream (the urls episode.tsx emitted for).
  void _navRoute(String route, Map<String, dynamic> state) {
    Nav.push(context, route, state);
    switch (route) {
      case Routes.videoSpeed:
        RemoteService.instance.route(TvPaths.videoSpeed, state);
      case Routes.tvSimilar:
        RemoteService.instance.route(TvPaths.tvSimilar, state);
      case Routes.tvRecommendation:
        RemoteService.instance.route(TvPaths.tvRecommended, state);
      case Routes.videoStream:
        RemoteService.instance.route(TvPaths.videoStream, state);
    }
  }

  // ---------------------------------------------------------------- UI
  Widget _header(Map<String, dynamic> serie) {
    final url = serie['url'];
    final check = _checkURL;
    const yellow = TextStyle(color: UkoColors.yellow);
    const white = TextStyle(color: Colors.white);
    return DetailHeader(
      background: serie['still_path'] as String?,
      poster: serie['still_path'] as String?,
      details: [
        Text('${serie['name'] ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('${serie['air_date'] ?? ''}', style: white),
        Text('season ${js(serie['season_number'])} || episode ${js(serie['episode_number'])}', style: white),
        if (url is Map && truthy(url['quality'])) Text('${url['quality']}', style: yellow),
        if (check != null && truthy(check['quality'])) Text('${check['quality']}', style: yellow),
        Text((_hasServerUrl || check != null) ? 'fast stream' : 'slow stream', style: white),
        OverviewText(serie['overview']),
      ],
      buttons: [
        PillButton(
          label: 'trailers',
          onTap: () => _navRoute(Routes.tvTrailer, {
            'id': _id,
            'season': serie['season_number'],
            'episode': serie['episode_number'],
            'background': _background,
          }),
        ),
        if (_layouts)
          PillButton(label: 'play', icon: Icons.play_arrow, filled: true, onTap: _openPlay)
        else if (_needsPhone)
          PlayPhonePrompt(onReturn: _runPlayGate),
        // PRD #11: only an episode with its own UKO copy can host a reaction
        if (_layouts && (_hasServerUrl || _checkURL != null)) PillButton(label: 'start a reaction', icon: Icons.groups, onTap: () => _openPlay(reaction: true)),
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
    if (_autoReaction) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoReaction());

    final guestStars = asMapList(credits['guest_stars']);
    final cast = asMapList(credits['cast']);
    void toPerson(Map<String, dynamic> item) => _navRoute(Routes.peopleId, {'id': item['id']});

    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        _header(serie),
        if (guestStars.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('GUEST STARS',
                style: TextStyle(
                    color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
          ),
          CreditRow(items: guestStars, onTap: toPerson),
          const SizedBox(height: 16),
        ],
        if (cast.isNotEmpty) ...[
          const Text('CAST', style: TextStyle(color: Colors.white)),
          CreditRow(items: cast, onTap: toPerson),
        ],
        const SizedBox(height: 128), // pb-32
      ],
    );
  }
}
