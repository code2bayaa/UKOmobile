// Port of mobile/app/(tabs)/movies/id.tsx
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/prefs.dart';
import '../../services/profile.dart';
import '../../services/remote.dart';
import '../../widgets/comments_section.dart';
import '../../widgets/common.dart';
import '../../widgets/picture.dart';
import '../../widgets/play_phone_prompt.dart';
import 'detail_common.dart';
import '../../widgets/no_credits.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  static const _kind = MediaKind.movie;

  Map<String, dynamic>? _movie;
  String? _images;
  Map<String, dynamic>? _credits;
  bool _playlist = false;
  List<Map<String, dynamic>> _generateGenre = [];
  bool _layouts = false;
  bool _needsPhone = false; // in a play region, but the account's phone isn't (PRD #7)
  bool _feedbackFor = false;

  String get _idStr => P.str(widget.params, 'id') ?? '';
  int? get _idInt => P.intOf(widget.params, 'id');

  @override
  void initState() {
    super.initState();
    _oneRing();
    _runPlayGate();
  }

  // ---------------------------------------------------------------- data

  Future<void> _oneRing() async {
    final k = KeyService.instance;
    await k.ready;
    final data = await Gql.query(kMoviePayloadQuery, {
      'movie': {'id': _idStr},
      'image': {
        // RN queried type "tv" here but inserted "movie" (cache never hit) — fixed.
        'type': _kind.api,
        'episode': -1,
        'season': -1,
        'id': _idInt ?? -1,
      },
      'credit': {'id': _idInt ?? 0, 'season': -1, 'episode': -1},
    });
    final payload = data?['moviePayload'];
    Map<String, dynamic>? part(String key) =>
        payload is Map && payload[key] is Map ? Map<String, dynamic>.from(stripTypename(payload[key]) as Map) : null;

    _movieRing(part('movie'));
    _imageRing(part('image'));
    _creditRing(part('credit'));
  }

  Future<Map<String, dynamic>?> _freshMovie() async {
    final k = KeyService.instance;
    final json = await Http.getJson('${k.movieDb}movie/$_idStr?api_key=${k.apiKey}');
    if (json is! Map) return null;
    final data = Map<String, dynamic>.from(json);
    Gql.mutate(kAddMovieMutation, {...data}).then((r) {
      final res = r?['addMovie'];
      if (res is Map && truthy(res['success'])) {
        if (res['message'] == 'already inserted') debugPrint('movie inserting already started...');
        debugPrint('Movie successfully inserted into MySQL: ${res['message']}');
      } else {
        debugPrint('Failed to insert movies into MySQL: $res');
      }
    });
    return data;
  }

  Future<void> _movieRing(Map<String, dynamic>? payload) async {
    Map<String, dynamic>? movie;
    // the server answers runtime:null for a movie it has not got in full or that went stale;
    // 0 is a real runtime (shorts, unknown) and must not refetch on every visit
    if (payload != null && payload['runtime'] == null) {
      debugPrint('first time...');
      final fresh = await _freshMovie();
      movie = {...payload, ...?fresh};
    } else if (payload != null && truthy(payload['success'])) {
      movie = payload;
    } else {
      // RN threw a TypeError here when payload was null (endless spinner).
      movie = await _freshMovie();
    }
    if (!mounted || movie == null) return;
    setState(() => _movie = movie);
    _afterMovie(movie);
  }

  /// useEffect([movie]): checkFeedback + setGenreIDS.
  void _afterMovie(Map<String, dynamic> movie) {
    if (truthy(movie['id']) && !_feedbackFor) {
      _feedbackFor = true;
      isInPlaylist(movie['id'], _kind).then((inList) {
        if (inList && mounted) setState(() => _playlist = true);
      });
    }
    if (movie['genre_ids'] is List) _setGenreIds(movie['genre_ids'] as List);
  }

  Future<void> _setGenreIds(List genre) async {
    final data = await Gql.query(kGenreQuery, {});
    final g = data?['genre'];
    List<Map<String, dynamic>> out = [];
    if (g is Map && truthy(g['success'])) {
      final ids = genre.map(toNum).toSet();
      out = asMapList(g['data']).where((e) => ids.contains(toNum(e['id'])) && e['mode'] == 'movie').toList();
    }
    if (mounted) setState(() => _generateGenre = out);
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

  Future<void> _creditRing(Map<String, dynamic>? payload) async {
    Map<String, dynamic> credits;
    if (payload != null && truthy(payload['success'])) {
      credits = payload;
    } else {
      final k = KeyService.instance;
      final json = await Http.getJson('${k.movieDb}movie/$_idStr/credits?api_key=${k.apiKey}');
      credits = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      insertCredits(asMapList(credits['cast']), _idInt, crew: asMapList(credits['crew']));
    }
    if (mounted) setState(() => _credits = credits);
  }

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

  /// navRoute(): push the phone route and mirror it on the TV.
  void _navRoute(String route, Map<String, dynamic> state, {String? tvPath}) {
    Nav.push(context, route, state);
    if (tvPath != null) RemoteService.instance.route(tvPath, state);
  }

  Map<String, dynamic> _playState({bool? dash}) {
    final m = _movie!;
    final release = '${m['release_date'] ?? ''}';
    return {
      'stream': 'movie',
      'id': m['id'],
      'name': or([m['title'], m['original_title']]),
      'background': _images,
      if (dash != null) 'dash': dash,
      'anime': isAnime(m),
      'date': m['release_date'],
      'year': release.length >= 4 ? release.substring(0, 4) : release,
      'imdbId': m['imdb_id'],
    };
  }

  static int _currentWeek() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year);
    final pastDaysOfYear = now.difference(startOfYear).inMilliseconds / 86400000;
    return ((pastDaysOfYear + (startOfYear.weekday % 7) + 1) / 7).ceil();
  }

  /// reaction: "start a reaction" - the player opens with the reaction set-up (speed.dart startParty, PRD #11)
  Future<void> _openPlay({bool reaction = false}) async {
    final movie = _movie;
    if (movie == null) return;
    if (reaction && !truthy(movie['url'])) return showUkoSnack(context, 'error', "Reactions need a UKO copy - this title only plays from an outside stream");
    if (truthy(movie['url'])) {
      await _goToSpeed(movie, reaction: reaction);
    } else {
      _navRoute(Routes.videoStream, _playState(), tvPath: TvPaths.videoStream);
    }
  }

  Future<void> _goToSpeed(Map<String, dynamic> movie, {bool reaction = false}) async {
    final url = movie['url'] is Map ? movie['url'] as Map : const {};
    if (url['quality'] == 'CAM' && _currentWeek() > toNum(url['week'])) {
      _navRoute(Routes.videoStream, _playState(), tvPath: TvPaths.videoStream);
      return;
    }
    var hasCredits = false;
    var hasPaid = false;
    final email = await Prefs.user;

    // RN used NEXT_PUBLIC_* env vars (undefined in Expo) + cookie auth here;
    // ported with the EXPO_PUBLIC endpoints/bodies used by collection.jsx.
    final paid = await Http.postJson(Api.userPaid, {'id': _idStr, 'email': email});
    if (!mounted) return;
    if (paid is Map) {
      debugPrint('${paid['message']}');
      if (truthy(paid['status'])) {
        hasPaid = true;
        showUkoSnack(context, 'success', 'rent paid ${paid['message']}');
      } else if (paid['message'] == 'day for movie credits ended') {
        showUkoSnack(context, 'error', 'rent elapsed ${paid['message']}');
      }
    }

    final credits = await Http.postJson(Api.checkUserCredits, {'username': email});
    if (!mounted) return;
    if (credits is Map) {
      debugPrint('${credits['message']}');
      if (toNum(credits['sum']) > 49) hasCredits = true;
    }

    if (!hasCredits && !hasPaid) {
      if (await promptGuestSignUp(context) || !mounted) return;
      showUkoSnack(context, 'error', 'NO CREDITS add more credits');
      return;
    }
    _navRoute(Routes.videoSpeed, {..._playState(dash: url.containsKey('dash')), if (reaction) 'startParty': true},
        tvPath: TvPaths.videoSpeed);
  }

  // ------------------------------------------------------------------ UI

  static const _white = TextStyle(color: Colors.white);

  @override
  Widget build(BuildContext context) {
    final movie = _movie;
    final credits = _credits;
    if (movie == null || credits == null) return const LoadingView();
    return ListView(
      key: ValueKey(_idStr),
      padding: const EdgeInsets.only(top: 16, bottom: 128),
      children: [
        _header(movie),
        const SizedBox(height: 16),
        const Text('Details', style: _white),
        CastRow(
          cast: asMapList(credits['cast']),
          onTap: (item) => _navRoute(Routes.peopleId, {'id': item['id']}),
        ),
        // movies PRD #4: viewers' comments on this TMDB movie
        if ((_idInt ?? toNum(movie['id']).toInt()) > 0)
          CommentsSection(type: 'movie', id: _idInt ?? toNum(movie['id']).toInt()),
      ],
    );
  }

  Widget _header(Map<String, dynamic> movie) {
    final width = MediaQuery.of(context).size.width;
    final genres = _generateGenre.isNotEmpty ? _generateGenre : asMapList(movie['genres']);
    final runtime = movie['runtime'];
    final rt = toNum(runtime);
    final runtimeText = rt > 60 ? '${rt ~/ 60} h ${rt % 60} min' : '${js(runtime)} min';
    final origin = movie['origin_country'];
    final firstCountry = origin is List && origin.isNotEmpty ? origin.first : null;
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
                    child: Text('${movie['title'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                  ),
                  Text('${or([movie['original_title'], movie['title']]) ?? ''}', style: _white),
                  if (truthy(movie['tagline']))
                    SizedBox(
                      width: double.infinity,
                      child: Text('${movie['tagline']}', textAlign: TextAlign.center, style: _white),
                    ),
                  Text('${movie['release_date'] ?? ''}', style: _white),
                  if (toNum(movie['revenue']) > 0) ...[
                    const Text('Revenue', style: _white),
                    Text('\$${js(movie['revenue'])}', style: _white),
                  ],
                  if (toNum(movie['budget']) > 0) ...[
                    const Text('Budget', style: _white),
                    Text('\$${js(movie['budget'])}', style: _white),
                  ],
                  Text('${movie['status'] ?? ''}', style: _white),
                  Text.rich(TextSpan(style: const TextStyle(color: UkoColors.yellow), children: [
                    const TextSpan(text: '★', style: TextStyle(fontSize: 30)),
                    TextSpan(text: ' ${toNum(movie['vote_average']).toStringAsFixed(1)}/10'),
                  ])),
                  Text(runtimeText, style: _white),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < genres.length; i++)
                            Text('${genres[i]['name'] ?? ''}${i < genres.length - 1 ? ' || ' : ''}',
                                style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text('${or([movie['overview'], 'waiting for more content'])}',
                        textAlign: TextAlign.justify, style: _white),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${firstCountry ?? ''} || ${movie['original_language'] ?? ''}', style: _white),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in asMapList(movie['production_companies']))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('${c['name'] ?? ''}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
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
                  // RN navRoute had no TV emit for "/movies/trailer".
                  onTap: () => _navRoute(Routes.moviesTrailer, {'id': movie['id'], 'title': movie['title'], 'background': _images}),
                ),
              ),
              if (_layouts)
                SizedBox(
                  width: btnW,
                  child: PillButton(label: ' play', filled: true, icon: Icons.play_arrow, onTap: _openPlay),
                )
              else if (_needsPhone)
                PlayPhonePrompt(width: btnW, onReturn: _runPlayGate),
              // PRD #11: reactions only on titles with their own UKO copy (movie.url), as web movie.jsx
              if (_layouts && truthy(movie['url']))
                SizedBox(
                  width: btnW,
                  child: PillButton(label: ' start a reaction', icon: Icons.groups, onTap: () => _openPlay(reaction: true)),
                ),
              SizedBox(
                width: btnW,
                child: PillButton(
                  label: 'similar',
                  onTap: () => _navRoute(Routes.moviesSimilar, {'id': movie['id']}, tvPath: TvPaths.moviesSimilar),
                ),
              ),
              SizedBox(
                width: btnW,
                child: PillButton(
                  label: 'recommended',
                  onTap: () => _navRoute(Routes.moviesRecommendation, {'id': movie['id']},
                      tvPath: TvPaths.moviesRecommended),
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
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('CASTS',
              style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
        ),
      ],
    );
  }
}
