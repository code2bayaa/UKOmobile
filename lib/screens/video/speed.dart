// Port of mobile/app/video/speed.tsx (react-native-video -> media_kit).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/prefs.dart';
import '../../services/party.dart';
import '../../services/remote.dart';
import '../../services/sockets.dart';
import '../../widgets/common.dart';
import '../offline/file_system.dart';
import '../offline/player_time.dart';
import 'player_shared.dart' show paidWithOf;
import '../party/party_panel.dart';

const String _insertMovieMutation = r'''
          mutation AddMovie(
              $adult:Boolean!
              $backdrop_path:String
              $id:Int!
              $original_language:String!
              $original_name:String
              $overview:String!
              $popularity:Float!
              $poster_path:String
              $first_air_date:String!
              $name:String!
              $vote_average:Float!
              $vote_count:Float!
              $belongs_to_collection:COLLECTION_INPUT
              $production_companies:[PRODUCTION_COMPANIES_INPUT]
              $production_countries:[PRODUCTION_COUNTRIES_INPUT]
              $spoken_languages:[SPOKEN_LANGUAGES_INPUT]
              $runtime:Int
              $genres:[GENRES_IDS_INPUT]
          ) {
              addMovie(
                  adult:$adult
                  backdrop_path:$backdrop_path
                  genres:$genres
                  id:$id
                  original_language:$original_language
                  original_name:$original_name
                  overview:$overview
                  popularity:$popularity
                  poster_path:$poster_path
                  first_air_date:$first_air_date
                  name:$name
                  vote_average:$vote_average
                  vote_count:$vote_count
                  belongs_to_collection:$belongs_to_collection
                  production_companies:$production_companies
                  production_countries:$production_countries
                  runtime:$runtime
                  spoken_languages:$spoken_languages
              ) {
                  success
                  message
              }
          }
      ''';

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

const String _fetchCombinedQuery = r'''
            query MoviePayload (
                $image: IMAGE_ARGUMENTS!
                $movie: SINGLE_MOVIE_ARGUMENTS!
                $credit: CREDIT_ITEM_ARGUMENTS!
            ) {
                moviePayload(
                    image: $image,
                    movie: $movie,
                    credit: $credit
                ) {
                    image {
                        data {
                            id
                            path
                        }
                        meta_data {
                            type
                            season
                            episode
                        }
                        success
                        error
                    }
                    movie {
                        adult
                        backdrop_path
                        genre_ids
                        genres {
                            id
                            name
                        }
                        id
                        original_language
                        original_title
                        overview
                        popularity
                        poster_path
                        release_date
                        title
                        video
                        runtime
                        revenue
                        budget
                        status
                        origin_country
                        production_companies {
                            id
                            name
                        }
                        tagline
                        vote_average
                        vote_count
                        url {
                            fileName
                        }
                        success
                        error
                        message
                    }
                    credit {
                        cast {
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
                            order
                        }
                        crew {
                            adult
                            gender
                            id
                            known_for_department
                            name
                            original_name
                            popularity
                            profile_path
                            credit_id
                            department
                            job
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

const String _fetchMovieQuery = r'''
        query Single (
            $id: ID!
        ){
            single(
                id:$id
            ) {
                adult
                backdrop_path
                genre_ids
                genres {
                    id
                    name
                }
                id
                original_language
                original_title
                overview
                popularity
                poster_path
                release_date
                title
                video
                runtime
                vote_average
                vote_count
                url {
                    fileName
                }
                success
            }
        }
    ''';

class SpeedPlayerScreen extends StatefulWidget {
  const SpeedPlayerScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<SpeedPlayerScreen> createState() => _SpeedPlayerScreenState();
}

class _SpeedPlayerScreenState extends State<SpeedPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];
  final List<void Function()> _remoteUnsubs = [];
  Timer? _hideTimer;

  // ---- RN state ----
  List<Map<String, dynamic>> _tv = []; // [{season_number, episodes}]
  // RN `play` is really the paused flag (`paused={play}`), false = playing.
  bool _paused = false;
  double _duration = 0; // seconds
  double _currentTime = 0; // seconds
  bool _caption = true;
  bool _mute = false;
  bool _seeking = false;
  bool _controlsVisible = false;
  bool _liked = false;
  int _views = 1000;
  bool _download = false;
  int _progress = 0;
  int _subtitleProgress = 0;
  List<String> _subFiles = [];
  bool _isLoadingVideo = true;
  bool _opened = false;
  // ---- watch party (movies PRD #11): services/party.dart + screens/party/party_panel.dart ----
  PartyRoom? _party;
  // in a party only the host plays, pauses, seeks or stops (services/party.dart also reverts a guest's player)
  bool get _guestLocked => _party != null && _party!.role != null && !_party!.isHost;
  bool _refuseGuest() {
    if (!_guestLocked) return false;
    showUkoSnack(context, 'Reaction', 'Only the host can play, pause or seek');
    return true;
  }
  bool _partyPanel = true;

  // RN never sets this to true (the subtitle HEAD check is commented out), so
  // offline downloads never include the subtitle. Kept identical.
  final bool _subtitleReady = false;

  // ---- params (expo-router params are strings; keep them as strings so the
  // JSON bodies are byte-identical to RN) ----
  Map<String, dynamic> get _p => widget.params;
  String? get _index => P.str(_p, 'index');
  String? get _id => P.str(_p, 'id');
  String? get _type => P.str(_p, 'type');
  String? get _background => P.str(_p, 'background');
  String? get _serieName => P.str(_p, 'serie_name');
  String? get _serieID => P.str(_p, 'serieID');
  String? get _season => P.str(_p, 'season');
  String? get _episode => P.str(_p, 'episode');
  dynamic get _anime => _p['anime'];
  String? get _date => P.str(_p, 'date');
  String? get _year => P.str(_p, 'year');
  String? get _imdbId => P.str(_p, 'imdbId');

  String get _videoSource => '${Api.speedPlay}/${js(_id)}';
  String get _subtitleUrl => '${Api.speedSubtitles}/${js(_id)}';

  late final List<dynamic>? _seasonsArr = _parseMaybeArray(_p['seasons']);
  late final List<dynamic>? _episodesArr = _parseMaybeArray(_p['episodes']);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SocketsService.instance.socketConnect();

    // TV -> phone player events. RN registered these in the render body (a new
    // listener on every render, never removed); subscribe once here.
    _remoteUnsubs.add(RemoteService.instance.onPlayerEvent('PLAY', (value) {
      if (!mounted || _guestLocked) return;
      final paused = !(value == true || value == 'true');
      setState(() => _paused = paused);
      paused ? _player.pause() : _player.play();
    }));
    _remoteUnsubs.add(RemoteService.instance.onPlayerEvent('SLIDE', (value) {
      if (!mounted || _guestLocked) return;
      final v = toNum(value).toDouble();
      setState(() => _currentTime = v);
      _player.seek(Duration(milliseconds: (v * 1000).round()));
    }));

    final st = _player.stream;
    _subs.addAll([
      st.duration.listen((d) {
        if (mounted) setState(() => _duration = d.inMilliseconds / 1000);
      }),
      st.position.listen((p) {
        if (!_seeking && mounted) setState(() => _currentTime = p.inMilliseconds / 1000);
      }),
      st.buffering.listen((b) {
        // onBuffer: setIsLoadingVideo(isBuffering)
        if (mounted && _opened) setState(() => _isLoadingVideo = b);
      }),
      st.playing.listen((playing) {
        if (playing && _isLoadingVideo && !_player.state.buffering && mounted) {
          setState(() => _isLoadingVideo = false);
        }
      }),
      st.error.listen((e) {
        debugPrint('Video error $e');
        if (mounted) setState(() => _isLoadingVideo = false);
      }),
    ]);

    _openVideo();
    _getSubtitles();
    _processPayment();
    _insertViews();
    if (truthy(_season)) _oneRing();
    // a guest arrives here from screens/party/join_party.dart with the party's code
    final partyCode = P.str(_p, 'party');
    if (partyCode != null && partyCode.isNotEmpty) {
      _startParty(partyCode);
    } else if (P.boolOf(_p, 'startParty')) {
      // opened from a detail screen's "start a reaction": show the set-up straight away
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _party == null) _createParty();
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final u in _remoteUnsubs) {
      u();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _party?.dispose();
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ---------------------------------------------------------------- watch party

  void _startParty(String code) {
    _party?.dispose();
    final room = PartyRoom(code)..attachPlayer(_player);
    setState(() {
      _party = room;
      _partyPanel = true;
    });
    room.start();
  }

  void _leaveParty() {
    final room = _party;
    setState(() => _party = null);
    room?.dispose();
  }

  /// What a guest's app needs to open this same title (the user service whitelists it).
  Map<String, dynamic> get _partyLaunch => {
        for (final k in ['id', 'type', 'stream', 'name', 'serie_name', 'serieID', 'season', 'episode', 'anime', 'date',
          'year', 'imdbId', 'eden', 'eden_series', 'background'])
          if (_p[k] != null && '${_p[k]}' != 'null') k: _p[k],
        'content': truthy(_season) ? 'tv' : 'movie',
        if (truthy(_serieID)) 'series': _serieID,
      };

  Future<void> _createParty() async {
    final feeText = TextEditingController(text: '0');
    var listed = true; // public by default: shown on the Reactions screen
    final choice = await showDialog<({int fee, bool listed})>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Start a reaction'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Up to 10 people watch this in sync, with camera, mic and chat. Everyone pays the normal play charge. '
                  'You can also charge guests a fee - you get 60%, UKO keeps 40%. Fees paid with bought or ad credits reach your profile wallet as money you can withdraw to M-PESA; fees paid with free credits come to you as credits.',
                  style: TextStyle(fontSize: 13)),
              TextField(
                controller: feeText,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fee to join, in credits (0 = free)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: listed,
                onChanged: (v) => setDialog(() => listed = v),
                title: const Text('Public', style: TextStyle(fontSize: 14)),
                subtitle: const Text('List it on Reactions so anyone can find and join', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final v = int.tryParse(feeText.text.trim());
                if (v != null && v >= 0 && v <= 1000) Navigator.pop(c, (fee: v, listed: listed));
              },
              child: const Text('Start reaction'),
            ),
          ],
        ),
      ),
    );
    feeText.dispose();
    if (choice == null || !mounted) return;
    final created = await PartyApi.post('create', {'launch': _partyLaunch, 'fee': choice.fee, 'listed': choice.listed});
    if (!mounted) return;
    if (created['status'] != true) {
      showUkoAlert(context, 'Reaction', '${created['message'] ?? 'Could not start the reaction'}');
      return;
    }
    final code = '${(created['party'] as Map)['code']}';
    _startParty(code);
    showUkoAlert(context, 'Reaction started',
        'Share the code $code${choice.listed ? ' - it is also listed on Reactions' : ''}. Friends join from the menu: reactions.');
  }

  // ---------------------------------------------------------------- player

  Future<void> _openVideo() async {
    try {
      await _player.open(Media(_videoSource), play: !_paused);
      _opened = true;
      await _applySubtitle();
    } catch (e) {
      debugPrint('Video error $e');
      if (mounted) setState(() => _isLoadingVideo = false);
    }
  }

  /// RN: `textTracks` (only while captions are on) from `SPEED_SUBTITLES/<id>/<file>`
  /// and `selectedTextTrack` = first file.
  Future<void> _applySubtitle() async {
    if (!_opened) return;
    try {
      if (_caption && _subFiles.isNotEmpty) {
        final file = _subFiles.first;
        await _player.setSubtitleTrack(
            SubtitleTrack.uri('$_subtitleUrl/$file', title: file.split('.').first, language: 'en'));
      } else {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      }
    } catch (e) {
      debugPrint('subtitle error $e');
    }
  }

  Future<void> _getSubtitles() async {
    final res = await Http.postJson(Api.speedSubtitlesFiles, {'id': _id, 'index': _index});
    if (res is Map && truthy(res['status']) && res['files'] is List) {
      debugPrint('gotten files: ${res['files']}');
      if (!mounted) return;
      setState(() => _subFiles = (res['files'] as List).map((e) => '$e').toList());
      await _applySubtitle();
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _speedPlay() async {
    if (_refuseGuest()) return;
    setState(() => _paused = !_paused);
    _paused ? _player.pause() : _player.play();
    // New state: true = TV should play.
    await RemoteService.instance.play(!_paused);
  }

  Future<void> _changeSubtitle() async {
    setState(() => _caption = !_caption);
    await _applySubtitle();
    await RemoteService.instance.subtitle(_caption);
  }

  Future<void> _changeMute() async {
    setState(() => _mute = !_mute);
    await _player.setVolume(_mute ? 0 : 100);
    await RemoteService.instance.mute(_mute);
  }

  Future<void> _slideSeek(double value) async {
    if (_refuseGuest()) {
      setState(() => _seeking = false);
      return;
    }
    setState(() {
      _currentTime = value;
      _seeking = false;
      _paused = false;
    });
    await _player.seek(Duration(milliseconds: (value * 1000).round()));
    await _player.play();
    await RemoteService.instance.slide(value);
  }

  // ------------------------------------------------------ payment / views

  Future<void> _processPayment() async {
    try {
      var hasPaid = false;
      final email = await Prefs.user;
      final responseData = await Http.postJson(Api.userPaid, {'id': _id, 'email': email});
      debugPrint('$responseData');
      if (responseData is! Map) return; // RN: response.json() threw -> nothing happened

      if (truthy(responseData['status'])) {
        final res = await Http.postJson(Api.updateUserCredits, {'type': _type, 'id': _id, 'email': email});
        if (res is! Map) return;
        debugPrint('${res['message']} ${res['success']}');
        if (truthy(res['success'])) hasPaid = true;
      } else {
        final res = await Http.postJson(Api.payUserCredits, {
          'credit': 50,
          'data': {
            'receipt': 'player',
            'player-type': [_type],
            'title': _id,
            // Eden content - the charge pays the studio (user/credits/earnings.js), as web speed.jsx.
            // Movie or episode, and the Eden series an episode belongs to - producers are paid per series.
            if (truthy(_p['eden'])) ...{
              'eden': true,
              'content': truthy(_p['eden_series']) ? 'tv' : 'movie',
              'series': _p['eden_series'],
            } else ...{
              // movie or episode, like web speed.jsx - the charge is labelled with it (PRD #27)
              'content': truthy(_serieID) ? 'tv' : 'movie',
              'series': _serieID,
            },
          },
          'email': email,
        });
        if (res is! Map) return;
        debugPrint('${res['message']}');
        if (truthy(res['status'])) {
          hasPaid = true;
          final paidWith = paidWithOf(res);
          if (mounted) showUkoAlert(context, 'Payment', paidWith != null ? 'Paid with $paidWith.' : 'Paid with credits successfully.');
        }
      }

      if (!hasPaid && mounted) {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          Nav.replace(context, Routes.signIn);
        }
      }
    } catch (e) {
      debugPrint('$e error');
    }
  }

  Future<void> _insertViews() async {
    final res = await Http.postJson(Api.insertViews, {
      'movies_id': _id,
      'email': await Prefs.user,
      'platform': 'mobile',
      'wireframe': 'speed',
    });
    if (res is Map && truthy(res['status']) && mounted) {
      setState(() => _views = _views + toNum(res['count']).toInt());
    }
  }

  Future<void> _changeLike() async {
    final body = {'movies_id': _id, 'email': await Prefs.user, 'platform': 'mobile'};
    if (_liked) {
      final res = await Http.postJson(Api.removeLikes, body);
      debugPrint('${res is Map ? res['status'] : null} :status remove liked');
    } else {
      final res = await Http.postJson(Api.insertLikes, body);
      debugPrint('${res is Map ? res['status'] : null} :status liked');
    }
    if (mounted) setState(() => _liked = !_liked);
  }

  // ------------------------------------------------------------ seasons

  Future<void> _oneRing() async {
    final serieID = _serieID;
    final parsed = serieID != null ? int.tryParse(serieID) : null;
    final data = await Gql.query(_fetchCombinedQuery, {
      'movie': {'id': serieID},
      'image': {'type': 'tv', 'episode': -1, 'season': -1, 'id': serieID != null ? parsed : -1},
      'credit': {'id': serieID != null ? parsed : 0},
    });
    final payload = data?['moviePayload'] is Map ? (data!['moviePayload'] as Map)['movie'] : null;
    await _tvRing(payload is Map ? Map<String, dynamic>.from(payload) : null);
  }

  Future<void> _tvRing(Map<String, dynamic>? payload) async {
    final k = KeyService.instance;
    await k.ready;

    Future<Map<String, dynamic>?> freshFetch() async {
      final json = await Http.getJson('${k.movieDb}tv/${js(_serieID)}?api_key=${k.apiKey}');
      if (json is! Map) return null;
      final data = Map<String, dynamic>.from(json);
      Gql.mutate(_insertMovieMutation, {...data});
      return data;
    }

    Map<String, dynamic>? movie;
    if (payload != null && !truthy(payload['runtime'])) {
      debugPrint('first time...');
      movie = await freshFetch();
    } else if (payload != null && truthy(payload['success'])) {
      movie = payload;
    } else {
      movie = await freshFetch();
    }
    final seasons = asMapList(movie?['seasons']);
    if (seasons.isEmpty) {
      if (mounted) setState(() => _tv = []);
      return;
    }
    final seasonsWithEpisodes = await Future.wait(seasons.map((season) async {
      final episodes = await _fetchTV(season['season_number'], season['id']);
      return <String, dynamic>{'season_number': season['season_number'], 'episodes': episodes};
    }));
    if (mounted) setState(() => _tv = seasonsWithEpisodes);
  }

  Future<List<Map<String, dynamic>>> _fetchTV(dynamic season, dynamic seasonID) async {
    final k = KeyService.instance;
    await k.ready;

    Future<List<Map<String, dynamic>>> freshFetch() async {
      final json = await Http.getJson('${k.movieDb}tv/${js(_serieID)}/season/${js(season)}?api_key=${k.apiKey}');
      final newData = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      newData['episodes'] = asMapList(newData['episodes'])
          .map((e) => Map<String, dynamic>.from(e)
            ..remove('crew')
            ..remove('guest_stars')
            ..remove('cast'))
          .toList();
      Gql.mutate(_insertSeasonMutation, {'single': {...newData}});
      return asMapList(newData['episodes']);
    }

    final data = await Gql.query(_fetchSeasonQuery, {'id': int.tryParse('${seasonID ?? ''}') ?? -1});
    final s = data?['season'];
    if (s is Map && s['episodes'] == null) {
      debugPrint('first time...');
      return freshFetch();
    } else if (s is Map && truthy(s['success'])) {
      return asMapList(s['episodes']);
    }
    return freshFetch();
  }

  static List<dynamic>? _parseMaybeArray(dynamic val) {
    if (!truthy(val)) return null;
    if (val is List) return val;
    if (val is String) {
      try {
        final parsed = jsonDecode(val);
        return parsed is List ? parsed : null;
      } catch (_) {
        return [val];
      }
    }
    return null;
  }

  // ------------------------------------------------------------ navigation

  Future<void> _navRoute(String url, Map<String, dynamic> state) async {
    Nav.push(context, url, state);
    // RN emitted the screen names "Episode"/"Season" as the TV path.
    if (url == Routes.tvEpisode) {
      await RemoteService.instance.route(TvPaths.tvEpisode, state);
    } else if (url == Routes.tvSeason) {
      await RemoteService.instance.route(TvPaths.tvSeason, state);
    }
  }

  void _moreQuality() {
    _navRoute(Routes.videoStream, {
      'stream': truthy(_season) ? 'tv' : 'movie',
      'id': _id,
      'name': _serieName,
      'background': _background,
      'date': _date,
      'year': _year,
      'imdbId': _imdbId,
      'anime': _anime,
    });
  }

  // -------------------------------------------------------------- download

  // PRD #9: the video is fetched BEFORE the 100 credits are taken, so a failed download costs nothing, and a
  // title already on the phone is opened from Downloads instead of being bought again (web speed.jsx does the same).

  /// Title + poster for the Downloads list. Only blockbuster movies are looked up by id - an episode id or an
  /// Eden id would match some other TMDB movie - the rest use what this screen was opened with.
  Future<({Map<String, dynamic> data, String? posterUrl})> _downloadDetails(String id) async {
    final isEpisode = (_serieID ?? '').isNotEmpty || (_serieName ?? '').isNotEmpty;
    final eden = truthy(_p['eden']);
    var data = <String, dynamic>{
      'id': id,
      'name': isEpisode
          ? '${_serieName ?? ''}${_season != null ? ' S$_season' : ''}${_episode != null ? 'E$_episode' : ''}'.trim()
          : (P.str(_p, 'name') ?? ''),
      'eden': eden,
      'series': _serieID,
    };
    String? posterUrl = (_background ?? '').startsWith('http') ? _background : null;
    if (!eden && !isEpisode) {
      try {
        final fetched = await Gql.query(_fetchMovieQuery, {'id': id});
        final single = fetched?['single'] is Map ? Map<String, dynamic>.from(stripTypename(fetched!['single']) as Map) : null;
        if (single != null) {
          data = {...single, ...data, 'name': single['title'] ?? single['name'] ?? data['name']};
          final poster = single['poster_path'];
          if (poster is String && poster.isNotEmpty) {
            final k = KeyService.instance;
            await k.ready;
            posterUrl = k.imgPoster + poster;
          }
        }
      } catch (e) {
        debugPrint('download details failed $e');
      }
    }
    return (data: data, posterUrl: posterUrl);
  }

  Future<void> _offlineDownload() async {
    final id = _id ?? '';
    if (id.isEmpty || _download) return;
    List<String> keys;
    try {
      keys = await OfflineStore.listVideoKeys();
    } catch (_) {
      keys = [];
    }
    if (!mounted) return;
    if (keys.contains(id)) {
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Already downloaded'),
          content: const Text('This title is already saved on this phone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('OK')),
            TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Open Downloads')),
          ],
        ),
      );
      if (open == true && mounted) Nav.push(context, Routes.offlineDownloads);
      return;
    }
    if (keys.length >= 15) {
      showUkoAlert(context, 'Storage is full', 'You can keep 15 downloads. Delete one in Downloads first.');
      return;
    }
    final email = await Prefs.user;
    final res = await Http.postJson(Api.checkUserCredits, {'username': email});
    if (!mounted) return;
    final sum = res is Map ? res['sum'] : null;
    if (!(truthy(sum) && toNum(sum) > 99)) {
      showUkoAlert(context, 'Error', '100 CREDITS REQUIRED');
      return;
    }

    setState(() {
      _download = true;
      _progress = 0;
      _subtitleProgress = 0;
    });
    String? videoPath;
    var paid = false;
    String? paidWith;
    try {
      // 1. the video - nothing is charged if it doesn't arrive
      final videoUrl = '${Api.downloadTwo}/${js(_id)}/${js(_index)}';
      try {
        videoPath = await OfflineStore.downloadFile('video', videoUrl, id, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        }, format: 'mp4');
      } catch (e) {
        debugPrint('video download failed $e');
      }
      if (!mounted) return;
      if (videoPath == null) {
        showUkoAlert(context, 'Download failed', 'The video could not be downloaded. No credits were taken - try again.');
        return;
      }

      // 2. pay
      final pay = await Http.postJson(Api.payUserCredits, {
        'credit': 100,
        'data': {
          'receipt': 'download',
          'player-type': [_type],
          'title': _id,
          // same Eden fields as the play receipt, so an Eden download pays the studio (PRD #16/#17)
          if (truthy(_p['eden'])) ...{
            'eden': true,
            'content': truthy(_p['eden_series']) ? 'tv' : 'movie',
            'series': _p['eden_series'],
          },
        },
        'email': email,
      });
      if (!mounted) return;
      if (!(pay is Map && truthy(pay['status']))) {
        showUkoAlert(context, 'Payment failed',
            pay is Map && pay['message'] is String ? pay['message'] as String : 'Your credits could not be used. Try again.');
        return;
      }
      paid = true;
      paidWith = paidWithOf(pay);

      // 3. subtitle, title and poster - none of them stops the save
      String? subtitlePath;
      if (_subtitleReady) {
        try {
          subtitlePath = await OfflineStore.downloadFile('subtitle', '${Api.hostSub}/${js(_id)}', id, onProgress: (p) {
            if (mounted) setState(() => _subtitleProgress = p);
          });
        } catch (e) {
          debugPrint('subtitle download failed $e');
        }
      }
      final details = await _downloadDetails(id);
      String? imagePath;
      if (details.posterUrl != null) {
        try {
          imagePath = await OfflineStore.downloadFile('image', details.posterUrl!, id);
        } catch (e) {
          debugPrint('poster download failed $e');
        }
      }

      final result = await OfflineStore.saveVideo(videoPath, subtitlePath, imagePath, details.data, id, 'mp4');
      if (!mounted) return;
      if (result.status) {
        showUkoAlert(context, 'Downloaded',
            'Saved on this phone - it plays without internet from Downloads.${paidWith != null ? ' Paid with $paidWith.' : ''}');
      } else {
        showUkoAlert(context, 'Not saved', result.error ?? 'The video could not be saved on this phone.');
      }
    } catch (e) {
      debugPrint('Download error $e');
      if (mounted) showUkoAlert(context, 'Download failed', paid ? 'Something went wrong while saving.' : 'No credits were taken - try again.');
    } finally {
      // not paid for -> the file must not stay on the phone
      if (!paid && videoPath != null) {
        try {
          final f = File(videoPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _download = false);
    }
  }

  // ------------------------------------------------------------------- UI

  Widget _roundButton({
    required double width,
    required Widget child,
    required VoidCallback? onTap,
    double marginPct = 0.01,
  }) {
    return Container(
      margin: EdgeInsets.all(width * marginPct),
      width: width * 0.06,
      height: 50,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
    );
  }

  String _rating(dynamic v) => (double.tryParse('$v') ?? double.nan).toStringAsFixed(1);

  Widget _tile({required VoidCallback onTap, required List<Widget> lines, required double width}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width * 0.45,
        margin: EdgeInsets.all(width * 0.45 * 0.005),
        padding: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.white, width: 2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
      ),
    );
  }

  Widget _starLine(dynamic vote) => Row(children: [
        const Icon(Icons.star_border, size: 18, color: UkoColors.yellow),
        Text(' ${_rating(vote)}', style: const TextStyle(color: UkoColors.yellow)),
      ]);

  Widget _renderEpisode(Map<String, dynamic> item, double width) {
    return _tile(
      width: width,
      onTap: () => _navRoute(Routes.tvEpisode, {
        'stream': 'series',
        'id': _serieID,
        'episodeID': item['id'],
        'season': item['season_number'],
        'episode': item['episode_number'],
        'name': _serieName,
        'background': item['still_path'],
        'anime': _anime,
        if (_seasonsArr != null) 'moveSeasons': jsonEncode(_seasonsArr),
        if (_episodesArr != null) 'moveEpisodes': jsonEncode(_episodesArr),
      }),
      lines: [
        Text('${item['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
        Text('episode ${item['episode_number']}', style: const TextStyle(color: Colors.white)),
        _starLine(item['vote_average']),
      ],
    );
  }

  Widget _header(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: width * 0.05),
        Text(
          'Playing ${_serieName ?? ''} ${truthy(_season) ? ' || $_season' : ''}${truthy(_episode) ? ' || $_episode' : ''}',
          style: const TextStyle(color: Colors.white),
        ),
        Row(children: [
          Text('$_views ', style: const TextStyle(color: Colors.white)),
          const Icon(Icons.visibility_outlined, color: Colors.white),
        ]),
        SizedBox(
          width: width * 0.4,
          child: InkWell(
            onTap: _moreQuality,
            child: const Text('More Quality',
                style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
          ),
        ),
        SizedBox(height: width * 0.20),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _roundButton(
              width: width,
              onTap: _speedPlay,
              child: Icon(_paused ? Icons.play_circle_outline : Icons.pause_circle_outline, size: 30, color: Colors.black),
            ),
            Container(
              margin: EdgeInsets.only(top: width * 0.01),
              width: width * 0.8,
              height: 50,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                SizedBox(
                  width: 60,
                  child: Text(formatPlayerTime(_currentTime * 1000),
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: _duration > 0 ? _duration : 1,
                    value: _currentTime.clamp(0, _duration > 0 ? _duration : 1).toDouble(),
                    activeColor: const Color(0xFFE50914),
                    inactiveColor: const Color(0xFF555555),
                    thumbColor: const Color(0xFFE50914),
                    onChangeStart: (_) => setState(() => _seeking = true),
                    onChanged: (v) => setState(() => _currentTime = v),
                    onChangeEnd: _slideSeek,
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(formatPlayerTime(_duration * 1000),
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ]),
            ),
            _roundButton(
              width: width,
              onTap: _changeLike,
              child: Icon(Icons.thumb_up_outlined, color: _liked ? UkoColors.yellow : Colors.black),
            ),
            _roundButton(
              width: width,
              onTap: _download ? null : _offlineDownload,
              child: Icon(Icons.arrow_downward, color: _download ? UkoColors.yellow : Colors.black),
            ),
            _roundButton(
              width: width,
              marginPct: 0.005,
              onTap: _changeSubtitle,
              child: Icon(Icons.closed_caption_outlined, color: _caption ? UkoColors.yellow : Colors.black),
            ),
            _roundButton(
              width: width,
              marginPct: 0.005,
              onTap: _changeMute,
              child: Icon(_mute ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                  color: _mute ? UkoColors.yellow : Colors.black),
            ),
          ],
        ),
        Row(children: [
          InkWell(
            onTap: _party == null ? _createParty : () => setState(() => _partyPanel = !_partyPanel),
            child: Container(
              margin: EdgeInsets.all(width * 0.01),
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UkoColors.yellow, width: 2),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.groups, color: UkoColors.yellow, size: 18),
                const SizedBox(width: 6),
                Text(_party == null ? 'Start a reaction' : (_partyPanel ? 'Hide reaction' : 'Show reaction'),
                    style: const TextStyle(color: UkoColors.yellow)),
              ]),
            ),
          ),
          ListenableBuilder(
            listenable: RemoteService.instance,
            builder: (context, _) => InkWell(
              onTap: () => RemoteService.instance.toggle(),
              child: Container(
                margin: EdgeInsets.all(width * 0.01),
                width: width * 0.1,
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: UkoColors.yellow, width: 2),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Remote: ${RemoteService.instance.connected ? 'ON' : 'OFF'}',
                      style: const TextStyle(color: UkoColors.yellow)),
                ),
              ),
            ),
          ),
        ]),
        if (_download)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Video Progress', style: TextStyle(color: Colors.white)),
              _progressBar(_progress),
              Text('$_progress%', style: const TextStyle(color: Colors.white)),
              const Text('Subtitle Progress', style: TextStyle(color: Colors.white)),
              _progressBar(_subtitleProgress),
              Text('$_subtitleProgress%', style: const TextStyle(color: Colors.white)),
            ],
          ),
      ],
    );
  }

  Widget _progressBar(int percent) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 256,
      height: 16,
      decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: (percent.clamp(0, 100)) / 100,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Widget _seasonRow(Map<String, dynamic> item, double width) {
    final episodes = asMapList(item['episodes']);
    return Container(
      margin: const EdgeInsets.only(top: 5),
      height: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: width * 0.3,
            color: Colors.white.withValues(alpha: 0.8),
            child: Text('Season ${item['season_number']}',
                style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                itemBuilder: (context, i) => _renderEpisode(episodes[i], width),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showSeasons = truthy(_season) && _tv.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain),
            if (_isLoadingVideo)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: UkoColors.yellow),
                      SizedBox(height: 8),
                      Text('Loading video...', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            if (_controlsVisible)
              Positioned.fill(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 16),
                  itemCount: 1 + (showSeasons ? _tv.length : 0),
                  itemBuilder: (context, i) => i == 0 ? _header(width) : _seasonRow(_tv[i - 1], width),
                ),
              ),
            if (_party != null) Positioned.fill(child: PartyReactionsLayer(room: _party!)),
            if (_party != null && _partyPanel)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: width * 0.34,
                child: SafeArea(
                  left: false,
                  child: PartyPanel(
                    room: _party!,
                    onLeave: _leaveParty,
                    onShowOnTv: () => RemoteService.instance.route(TvPaths.party, {'code': _party!.code}, true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
