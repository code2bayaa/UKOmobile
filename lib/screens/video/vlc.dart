import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';
import 'player_shared.dart';

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

/// `formatTime(ms)` from vlc.tsx:861 (kept byte-for-byte in behaviour).
String formatVlcTime(num ms) {
  int? hour;
  int minutes;
  int seconds;
  if (ms > 3600000) {
    final wholeHour = ms / 3600000;
    hour = wholeHour.floor();
    final rawMinutes = wholeHour - hour;
    final wholeMinutes = rawMinutes * 60;
    minutes = wholeMinutes.floor();
    final rawSeconds = wholeMinutes - minutes;
    seconds = (rawSeconds * 60).floor();
  } else {
    final wholeMinutes = ms / 60000;
    minutes = wholeMinutes.floor();
    final rawSeconds = wholeMinutes - minutes;
    seconds = (rawSeconds * 60).floor();
  }
  final h = (hour != null && hour != 0) ? '$hour' : '00';
  final m = minutes != 0 && minutes < 10 ? '0$minutes' : (minutes != 0 ? '$minutes' : '00');
  final s = seconds != 0 && seconds < 10 ? '0$seconds' : (seconds != 0 ? '$seconds' : '00');
  return '$h:$m:$s';
}

/// Port of app/video/vlc.tsx: embedded VLC player (react-native-vlc-media-player
/// -> flutter_vlc_player) for the HOST_PLAY stream prepared by video/stream,
/// with the tap-to-toggle overlay (subtitle files, play/seek/like/captions/
/// mute, remote on/off, and for series every season's episodes).
class VlcPlayerScreen extends StatefulWidget {
  const VlcPlayerScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<VlcPlayerScreen> createState() => _VlcPlayerScreenState();
}

class _VlcPlayerScreenState extends State<VlcPlayerScreen> {
  Map<String, dynamic> get p => widget.params;
  dynamic get _index => p['index'];
  dynamic get _id => p['id'];
  dynamic get _type => p['type'];
  dynamic get _serieName => p['serie_name'];
  dynamic get _serieID => p['serieID'];
  dynamic get _season => p['season'];
  dynamic get _episode => p['episode'];
  dynamic get _anime => p['anime'];

  /// `tv` state: [{season_number, episodes}]
  List<Map<String, dynamic>> _tv = [];

  /// RN `play` state — NOTE it means *paused* (`paused={play}`).
  bool _paused = false;
  int _duration = 0; // ms
  int _currentTime = 0; // ms
  bool _seeking = false;
  bool _controlsVisible = false;
  bool _liked = false;
  bool _caption = true;
  int _views = 1000;
  bool _mute = false;
  bool _isLoadingVideo = true;
  List<String> _subFiles = [];
  String? _subtitleUri;

  late final VlcPlayerController _controller;
  bool _subtitleAttached = false;
  int? _subtitleSpuId;

  String get _videoSource {
    // `${HOST_PLAY}/${id}/${index}/${serie_name.replace(/\s+/, '.').trim()}`
    // (no /g flag: only the first whitespace run is replaced).
    final name = js(_serieName).replaceFirst(RegExp(r'\s+'), '.').trim();
    return '${Api.hostPlay}/${js(_id)}/${js(_index)}/$name';
  }

  String get _subtitleUrl => '${Api.hostSub}/${js(_id)}';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _controller = VlcPlayerController.network(
      _videoSource,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        http: VlcHttpOptions([VlcHttpOptions.httpReconnect(true)]),
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(3000)]),
        subtitle: VlcSubtitleOptions([
          VlcSubtitleOptions.boldStyle(true),
          VlcSubtitleOptions.color(VlcSubtitleColor.white),
        ]),
      ),
    );
    _controller.addListener(_onPlayer);
    if (truthy(_season)) _oneRing();
    _insertViews();
    _getSubtitles();
    _processPayment();
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayer);
    _controller.stop().catchError((_) {}).whenComplete(() => _controller.dispose());
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted) return;
    final v = _controller.value;
    var changed = false;
    // onLoad / onPlaying -> hide the spinner, remember the duration.
    if (_isLoadingVideo && (v.isPlaying || v.duration > Duration.zero)) {
      _isLoadingVideo = false;
      changed = true;
    }
    final d = v.duration.inMilliseconds;
    if (d > 0 && d != _duration) {
      _duration = d;
      changed = true;
    }
    // onProgress
    if (!_seeking) {
      final c = v.position.inMilliseconds;
      if (c != _currentTime) {
        _currentTime = c;
        changed = true;
      }
    }
    if (v.isInitialized && !_subtitleAttached && _caption && _subtitleUri != null) {
      _attachSubtitle(_subtitleUri!);
    }
    if (changed) setState(() {});
  }

  Future<void> _guard(Future<void> Function() op) async {
    if (!_controller.value.isInitialized) return;
    try {
      await op();
    } catch (e) {
      debugPrint('VLC op failed: $e');
    }
  }

  // ---- data ---------------------------------------------------------------

  Future<void> _insertViews() async {
    final res = await Http.postJson(Api.insertViews, {
      'movies_id': _id,
      'email': await Prefs.user,
      'platform': 'mobile',
      'wireframe': 'vlc',
    });
    if (!mounted || res is! Map) return;
    if (truthy(res['status'])) setState(() => _views = _views + toNum(res['count']).toInt());
  }

  Future<void> _getSubtitles() async {
    final res = await Http.postJson(Api.speedSubtitlesFiles, {'id': _id, 'index': _index});
    if (!mounted || res is! Map) return;
    if (truthy(res['status']) && res['files'] is List) {
      setState(() => _subFiles = [for (final f in res['files'] as List) '$f']);
    }
  }

  Future<void> _processPayment() async {
    final (result, paidWith) = await processPlayerPayment(id: _id, type: _type);
    if (!mounted) return;
    switch (result) {
      case PlayerPayment.paidWithCredits:
        showAwesomeAlert(context, 'success', paidWith != null ? 'Paid with $paidWith' : 'paid with credits');
      case PlayerPayment.notPaid:
        Navigator.of(context).maybePop();
      case PlayerPayment.paid:
      case PlayerPayment.error:
        break;
    }
  }

  Future<void> _oneRing() async {
    final serieInt = parseIntOr(_serieID, -1);
    final data = await Gql.query(_fetchCombinedQuery, {
      'movie': {'id': _serieID},
      'image': {'type': 'tv', 'episode': -1, 'season': -1, 'id': serieInt},
      'credit': {'id': truthy(_serieID) ? serieInt : 0},
    });
    final payload = data?['moviePayload']?['movie'];
    // RN: `payload.success` on a null payload threw -> caught -> nothing.
    if (payload is! Map) return;
    await _tvRing(Map<String, dynamic>.from(payload));
  }

  Future<void> _tvRing(Map<String, dynamic> payload) async {
    final k = KeyService.instance;
    await k.ready;

    Future<Map<String, dynamic>?> freshFetch() async {
      final data = await Http.getJson('${k.movieDb}tv/${js(_serieID)}?api_key=${k.apiKey}');
      if (data is! Map) return null;
      final m = Map<String, dynamic>.from(data);
      Gql.mutate(_insertMovieMutation, m);
      return m;
    }

    Map<String, dynamic>? movie;
    if (!truthy(payload['runtime'])) {
      movie = await freshFetch();
    } else if (truthy(payload['success'])) {
      movie = payload;
    } else {
      movie = await freshFetch();
    }
    if (!mounted) return;
    final seasons = asMapList(movie?['seasons']);
    if (seasons.isEmpty) {
      setState(() => _tv = []);
      return;
    }
    final withEpisodes = await Future.wait(seasons.map((s) async {
      final episodes = await _fetchTV(s['season_number'], s['id']);
      return <String, dynamic>{'season_number': s['season_number'], 'episodes': episodes};
    }));
    if (mounted) setState(() => _tv = withEpisodes);
  }

  Future<List<Map<String, dynamic>>> _fetchTV(dynamic season, dynamic seasonID) async {
    final k = KeyService.instance;
    await k.ready;

    Future<List<Map<String, dynamic>>> freshFetch() async {
      final data = await Http.getJson('${k.movieDb}tv/${js(_serieID)}/season/${js(season)}?api_key=${k.apiKey}');
      if (data is! Map) return [];
      final newData = Map<String, dynamic>.from(data);
      newData['episodes'] = asMapList(newData['episodes']).map((e) {
        final rest = Map<String, dynamic>.from(e)
          ..remove('crew')
          ..remove('guest_stars')
          ..remove('cast');
        return rest;
      }).toList();
      Gql.mutate(_insertSeasonMutation, {'single': newData});
      return List<Map<String, dynamic>>.from(newData['episodes'] as List);
    }

    final data = await Gql.query(_fetchSeasonQuery, {'id': parseIntOr(seasonID, -1)});
    final s = data?['season'];
    if (s is Map && s['episodes'] == null) {
      return freshFetch();
    } else if (s is Map && truthy(s['success'])) {
      return asMapList(stripTypename(s['episodes']));
    } else {
      return freshFetch();
    }
  }

  // ---- controls -----------------------------------------------------------

  Future<void> _vlcPlay() async {
    final paused = !_paused;
    setState(() => _paused = paused);
    await _guard(() => paused ? _controller.pause() : _controller.play());
    // RN emitted the stale `play` flag; send the new "is playing" state.
    RemoteService.instance.play(!paused);
  }

  Future<void> _changeSubtitle() async {
    final caption = !_caption;
    setState(() => _caption = caption);
    if (caption) {
      if (_subtitleSpuId != null) {
        final id = _subtitleSpuId!;
        await _guard(() => _controller.setSpuTrack(id));
      } else if (_subtitleUri != null) {
        await _attachSubtitle(_subtitleUri!);
      }
    } else {
      await _guard(() => _controller.setSpuTrack(-1));
    }
    RemoteService.instance.subtitle(caption);
  }

  Future<void> _changeMute() async {
    final mute = !_mute;
    setState(() => _mute = mute);
    await _guard(() => _controller.setVolume(mute ? 0 : 100));
    RemoteService.instance.mute(mute);
  }

  Future<void> _slideSeek(double value) async {
    setState(() {
      _currentTime = value.round();
      _seeking = false;
    });
    await _guard(() => _controller.seekTo(Duration(milliseconds: value.round())));
    RemoteService.instance.slide(value / 1000);
  }

  /// setSubtitle(uri): `${HOST_SUB}/${id}/${file}` loaded into the player.
  Future<void> _setSubtitle(String file) async {
    final uri = '$_subtitleUrl/$file';
    setState(() => _subtitleUri = uri);
    _subtitleAttached = false;
    if (_caption) await _attachSubtitle(uri);
  }

  Future<void> _attachSubtitle(String uri) async {
    if (!_controller.value.isInitialized) return;
    _subtitleAttached = true;
    Map<int, String> before = const {};
    try {
      before = await _controller.getSpuTracks();
    } catch (_) {}
    await _guard(() => _controller.addSubtitleFromNetwork(uri, isSelected: true));
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    try {
      final after = await _controller.getSpuTracks();
      final added = after.keys.where((k) => k >= 0 && !before.containsKey(k));
      if (added.isNotEmpty) _subtitleSpuId = added.last;
    } catch (_) {}
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

  void _navEpisode(Map<String, dynamic> item) {
    final state = <String, dynamic>{
      'stream': 'series',
      'id': _serieID,
      'episodeID': item['id'],
      'season': item['season_number'],
      'episode': item['episode_number'],
      'name': _serieName,
      'background': item['still_path'],
      'anime': _anime,
    };
    Nav.push(context, Routes.tvEpisode, state);
    // RN emitted the screen name "Episode" as the TV path; use /tv/episode.
    RemoteService.instance.route(TvPaths.tvEpisode, state);
  }

  // ---- UI -----------------------------------------------------------------

  Widget _roundButton({required Widget child, required VoidCallback onTap, required double width}) {
    return Container(
      width: width,
      height: 50,
      margin: EdgeInsets.all(MediaQuery.of(context).size.width * 0.005),
      child: Material(
        color: const Color.fromRGBO(255, 255, 255, 0.5),
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
      ),
    );
  }

  Widget _header(double w) {
    final title = StringBuffer('Playing ${_serieName ?? ''} ');
    if (truthy(_season)) title.write(' || $_season');
    if (truthy(_episode)) title.write(' || $_episode');
    const timeStyle = TextStyle(color: Colors.black);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toString(), style: const TextStyle(color: Colors.white)),
        Row(children: [
          Text('$_views ', style: const TextStyle(color: Colors.white)),
          const Icon(Icons.remove_red_eye_outlined, color: Colors.white),
        ]),
        if (_subFiles.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final sub in _subFiles)
                  GestureDetector(
                    onTap: () => _setSubtitle(sub),
                    child: Container(
                      width: 90,
                      constraints: const BoxConstraints(minHeight: 40),
                      margin: EdgeInsets.all(w * 0.01),
                      color: const Color.fromRGBO(255, 255, 255, 0.6),
                      alignment: Alignment.center,
                      child: Text(sub.split('.').first,
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.black)),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: w * 0.02),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              _roundButton(
                width: w * 0.06,
                onTap: _vlcPlay,
                child: Icon(_paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
                    size: 30, color: Colors.black),
              ),
              Container(
                width: w * 0.65,
                height: 50,
                margin: EdgeInsets.only(top: w * 0.01),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    SizedBox(
                        width: 60,
                        child: Text(formatVlcTime(_currentTime), textAlign: TextAlign.center, style: timeStyle)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: UkoColors.red,
                          inactiveTrackColor: UkoColors.border,
                          thumbColor: UkoColors.red,
                        ),
                        child: Slider(
                          min: 0,
                          max: _duration > 0 ? _duration.toDouble() : 1,
                          value: _duration > 0 ? _currentTime.clamp(0, _duration).toDouble() : 0,
                          onChangeStart: (_) => setState(() => _seeking = true),
                          onChanged: (v) => setState(() => _currentTime = v.round()),
                          onChangeEnd: _slideSeek,
                        ),
                      ),
                    ),
                    SizedBox(
                        width: 60,
                        child: Text(formatVlcTime(_duration), textAlign: TextAlign.center, style: timeStyle)),
                  ],
                ),
              ),
              _roundButton(
                width: w * 0.06,
                onTap: _changeLike,
                child: Icon(Icons.thumb_up_outlined, color: _liked ? UkoColors.yellow : Colors.black),
              ),
              _roundButton(
                width: w * 0.06,
                onTap: _changeSubtitle,
                child: Icon(Icons.closed_caption_outlined, color: _caption ? UkoColors.yellow : Colors.black),
              ),
              _roundButton(
                width: w * 0.06,
                onTap: _changeMute,
                child: Icon(Icons.speaker_outlined, color: _mute ? UkoColors.yellow : Colors.black),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: RemoteService.instance,
          builder: (context, _) => Container(
            width: w * 0.1,
            height: 50,
            margin: EdgeInsets.all(w * 0.01),
            child: Material(
              color: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: UkoColors.yellow, width: 2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => RemoteService.instance.toggle(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: FittedBox(
                    child: Text('Remote: ${RemoteService.instance.connected ? "ON" : "OFF"}',
                        style: const TextStyle(color: UkoColors.yellow)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _episodeTile(Map<String, dynamic> item, double itemWidth) {
    return SizedBox(
      width: itemWidth,
      height: 150,
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onTap: () => _navEpisode(item),
          child: Container(
            constraints: BoxConstraints(minWidth: itemWidth * 0.6),
            height: 50,
            margin: EdgeInsets.all(itemWidth * 0.005),
            padding: const EdgeInsets.only(left: 4),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.white, width: 2))),
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                  Text('episode ${item['episode_number']}', style: const TextStyle(color: Colors.white)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_border, size: 14, color: UkoColors.yellow),
                    Text(' ${toFixed1(item['vote_average'])}', style: const TextStyle(color: UkoColors.yellow)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(double w) {
    final itemWidth = w * 0.45;
    final showSeasons = truthy(_season) && _tv.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        _header(w),
        if (showSeasons)
          for (final item in _tv)
            SizedBox(
              height: 150 + 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 5),
                  Container(
                    height: 40,
                    width: w * 0.3,
                    color: const Color.fromRGBO(255, 255, 255, 0.8),
                    child: Text('Season ${item['season_number']}',
                        style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: asMapList(item['episodes']).length,
                      itemBuilder: (_, i) => _episodeTile(asMapList(item['episodes'])[i], itemWidth),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: VlcPlayer(
                  controller: _controller,
                  aspectRatio: 16 / 9,
                  placeholder: const SizedBox.shrink(),
                ),
              ),
              if (_isLoadingVideo)
                const IgnorePointer(
                  child: ColoredBox(
                    color: Color.fromRGBO(0, 0, 0, 0.5),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: UkoColors.yellow),
                          SizedBox(height: 8),
                          Text('Loading video...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_controlsVisible) Positioned.fill(child: _overlay(w)),
            ],
          ),
        ),
      ),
    );
  }
}
