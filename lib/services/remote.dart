import 'package:flutter/foundation.dart';

import '../core/env.dart';
import '../core/http.dart';
import 'prefs.dart';
import 'sockets.dart';

/// Every route path the TV app (movies/front-end/tv/uko, lib/main.dart
/// onGenerateRoute) understands. `Route` emits MUST use one of these — the RN
/// app sometimes sent screen names ("MovieDetail", "TvDetail", "PeopleDetail",
/// "Episode", "Season") or a non-existent "/movies/top"; the port never does.
class TvPaths {
  TvPaths._();
  static const movies = '/movies';
  static const moviesId = '/movies/id';
  static const moviesSimilar = '/movies/similar';
  static const moviesRecommended = '/movies/recommended';
  static const moviesDiscover = '/movies/discover';
  static const moviesPopular = '/movies/popular';
  static const moviesTrending = '/movies/trending';
  static const moviesRated = '/movies/rated';
  static const moviesUpcoming = '/movies/upcoming';
  static const moviesPlaying = '/movies/playing';
  static const moviesNetflix = '/movies/netflix';
  static const moviesDisney = '/movies/disney';
  static const moviesAnime = '/movies/anime';
  static const moviesBollywood = '/movies/bollywood';
  static const moviesKorean = '/movies/korean';
  static const moviesChina = '/movies/china';
  static const tv = '/tv';
  static const tvId = '/tv/id';
  static const tvSeason = '/tv/season';
  static const tvEpisode = '/tv/episode';
  static const tvSimilar = '/tv/similar';
  static const tvRecommended = '/tv/recommended';
  static const tvDiscover = '/tv/discover';
  static const tvPopular = '/tv/popular';
  static const tvTrending = '/tv/trending';
  static const tvTop = '/tv/top';
  static const tvOnair = '/tv/onair';
  static const tvAiring = '/tv/airing';
  static const tvNetflix = '/tv/netflix';
  static const tvDisney = '/tv/disney';
  static const tvAnime = '/tv/anime';
  static const tvBollywood = '/tv/bollywood';
  static const tvKorean = '/tv/korean';
  static const tvChina = '/tv/china';
  // no people routes: the TV app has no People pages (web and mobile only)
  static const search = '/search';
  static const following = '/following';
  static const playlist = '/playlist';
  static const videoSpeed = '/video/speed';
  static const videoStream = '/video/stream';

  /// TV-side players opened from video/stream's "Choose player" dialog
  /// (components/home/collection.jsx). They are real TV routes
  /// (`/third` = OpenPlayer/VLC, `/remote` = RemotePlayer) but not part of the
  /// browsing route list above.
  static const third = '/third';
  static const remotePlayer = '/remote';

  /// Watch party handoff (movies PRD #11): state {code} - the TV joins the phone's party as a viewer.
  static const party = '/party';

  static const Set<String> all = {
    movies, moviesId, moviesSimilar, moviesRecommended, moviesDiscover, moviesPopular,
    moviesTrending, moviesRated, moviesUpcoming, moviesPlaying, moviesNetflix, moviesDisney,
    moviesAnime, moviesBollywood, moviesKorean, moviesChina,
    tv, tvId, tvSeason, tvEpisode, tvSimilar, tvRecommended, tvDiscover, tvPopular, tvTrending,
    tvTop, tvOnair, tvAiring, tvNetflix, tvDisney, tvAnime, tvBollywood, tvKorean, tvChina,
    search, following, playlist, videoSpeed, videoStream,
    third, remotePlayer, party,
  };

  /// Platform key (as used by the mobile `/screens/<key>` routes) -> TV path.
  static String platform(String key, {required bool tv}) {
    switch (key) {
      case 'netflix':
        return tv ? tvNetflix : moviesNetflix;
      case 'disney':
        return tv ? tvDisney : moviesDisney;
      case 'anime':
        return tv ? tvAnime : moviesAnime;
      case 'hindu':
      case 'hindi':
      case 'bollywood':
        return tv ? tvBollywood : moviesBollywood;
      case 'korean':
        return tv ? tvKorean : moviesKorean;
      case 'china':
        return tv ? tvChina : moviesChina;
    }
    throw ArgumentError('unknown platform $key');
  }

  /// Legacy screen-name argument sent as the 2nd emit arg (the relay ignores
  /// it; kept for log readability on the relay).
  static String nameFor(String path) {
    const names = {
      movies: 'Movies', moviesId: 'MovieDetail', moviesSimilar: 'MovieSimilar',
      moviesRecommended: 'MovieRecommendation', moviesDiscover: 'MovieDiscover',
      moviesPopular: 'PopularDetail', moviesTrending: 'TrendingDetail', moviesRated: 'TopDetail',
      moviesUpcoming: 'UpcomingDetail', moviesPlaying: 'PlayingDetail', moviesNetflix: 'NetflixDetail',
      moviesDisney: 'DisneyDetail', moviesAnime: 'AnimeDetail', moviesBollywood: 'BollywoodDetail',
      moviesKorean: 'KoreanDetail', moviesChina: 'ChinaDetail',
      tv: 'Tv', tvId: 'TvDetail', tvSeason: 'Season', tvEpisode: 'Episode', tvSimilar: 'TvSimilar',
      tvRecommended: 'TvRecommendation', tvDiscover: 'TvDiscover', tvPopular: 'PopularTvDetail',
      tvTrending: 'TrendingTvDetail', tvTop: 'TopTvDetail', tvOnair: 'LiveDetail', tvAiring: 'AiringDetail',
      tvNetflix: 'NetflixTvDetail', tvDisney: 'DisneyTvDetail', tvAnime: 'AnimeTvDetail',
      tvBollywood: 'BollywoodTvDetail', tvKorean: 'KoreanTvDetail', tvChina: 'ChinaTvDetail',
      search: 'Search', following: 'Following',
      playlist: 'Playlist', videoSpeed: 'Speed', videoStream: 'Stream',
      third: 'VLCPlayer', remotePlayer: 'RemotePlayer', party: 'Party',
    };
    return names[path] ?? path;
  }
}

/// Phone-as-TV-remote. Replaces components/home/remote.tsx (RemoteProvider /
/// useRemote) and every scattered `SOCKETS.socketModule?.emit(...)` call.
///
/// Wire protocol (relay: back-end/sockets/js/index.js). `room` is `remote:<users.id>`, joined with a token
/// the user service signs (POST /user/remote/token/android) so nobody who merely knows the email can drive
/// the TV (movies PRD #12). Until the relay has SOCKETS_API_KEY the token route says no and the old
/// unsigned room (the email) is used instead.
///   emit("remote-join", {room, exp, sig})  joins the signed room; re-sent on every (re)connect
///   emit("remote", email)                   old unsigned room (fallback only)
///   emit("Route", room, routeName, tvPath, state) -> TV gets ("Route", tvPath, state)
///   emit("PLAY", room, bool)      true = TV should play, false = pause
///   emit("SLIDE", room, seconds)
///   emit("SUBTITLE", room, bool)  true = captions on
///   emit("MUTE", room, bool)      true = muted
///   emit("KEY", room, key)        D-pad: up | down | left | right | select | back | home | playpause
///   emit("tv-login", code, email)
class RemoteService extends ChangeNotifier {
  RemoteService._();
  static final RemoteService instance = RemoteService._();

  final SocketsService _sockets = SocketsService.instance;
  bool _connected = false;
  bool _initialised = false;

  /// `useRemote().connected` — shared_preferences "remote" == "on".
  bool get connected => _connected;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    _connected = (await Prefs.getItem(PrefKeys.remote)) == 'on';
    _sockets.connect();
    _sockets.addConnectListener(joinRoom);
    _sockets.socketConnect();
    notifyListeners();
  }

  /// The room remote events go to: the signed `remote:<id>` once joined, else the old email room.
  String? _room;
  Map<String, dynamic>? _token;
  String? _tokenUser;

  /// True when the phone is in the signed room - the only room the relay takes D-pad keys in.
  bool get signedRoom => _room != null && _room!.startsWith('remote:');

  /// Joins the user's remote room. Call after sign-in; it is also re-sent automatically on every
  /// socket (re)connect (the relay forgets rooms on disconnect).
  Future<void> joinRoom() async {
    final userId = await Prefs.user;
    if (userId == null || userId.isEmpty) {
      _room = null;
      return;
    }
    final token = await _roomToken(userId);
    if (token != null) {
      _room = token['room'] as String;
      _sockets.socket?.emit('remote-join', token);
    } else {
      _room = userId;
      _sockets.socket?.emit('remote', userId);
    }
    notifyListeners();
  }

  /// A still-valid signed token (reused until 10 minutes before it expires), or null to use the old room.
  Future<Map<String, dynamic>?> _roomToken(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cached = _token;
    if (cached != null && _tokenUser == userId && (cached['exp'] as int) - 600 > now) return cached;
    final res = await Http.postJson(Api.remoteToken, const {});
    if (res is Map && res['status'] == true && res['room'] is String && res['exp'] is num && res['sig'] is String) {
      _tokenUser = userId;
      return _token = {'room': res['room'], 'exp': (res['exp'] as num).toInt(), 'sig': res['sig']};
    }
    _token = null;
    return null;
  }

  /// Sign-out: forget the room and its token.
  void leaveRoom() {
    _room = null;
    _token = null;
    _tokenUser = null;
  }

  Future<String?> _currentRoom() async {
    if (_room == null) await joinRoom();
    return _room;
  }

  /// `toggleConnected()` from the tab bar's centre "remote" button.
  Future<void> toggle() async {
    _connected = !_connected;
    notifyListeners();
    await Prefs.setItem(PrefKeys.remote, _connected ? 'on' : 'off');
    if (_connected) {
      _sockets.socketConnect();
      await joinRoom();
    }
  }

  /// Re-reads the persisted flag (the RN tab buttons read AsyncStorage on
  /// every press rather than trusting context state).
  Future<bool> isOn() async {
    final on = (await Prefs.getItem(PrefKeys.remote)) == 'on';
    if (on != _connected) {
      _connected = on;
      notifyListeners();
    }
    return on;
  }

  /// Mirror a navigation on the TV. No-op unless remote mode is on (pass
  /// [force] for the explicit "play on TV" actions that are only reachable
  /// while connected anyway). [state] should carry `id` as an int.
  Future<void> route(String tvPath, [Map<String, dynamic> state = const {}, bool force = false]) async {
    if (!TvPaths.all.contains(tvPath)) {
      assert(false, 'Not a TV route path: $tvPath');
      debugPrint('RemoteService.route: refusing non-TV path "$tvPath"');
      return;
    }
    if (!force && !await isOn()) return;
    final room = await _currentRoom();
    if (room == null) return;
    final payload = Map<String, dynamic>.from(state);
    if (payload.containsKey('id')) {
      final raw = payload['id'];
      payload['id'] = raw is int ? raw : int.tryParse('$raw') ?? raw;
    }
    _sockets.emitArgs('Route', [room, TvPaths.nameFor(tvPath), tvPath, payload]);
  }

  Future<void> _player(String event, dynamic value) async {
    if (!await isOn()) return;
    final room = await _currentRoom();
    if (room == null) return;
    _lastEmit[event] = _Emit(value, DateTime.now());
    _sockets.emitArgs(event, [room, value]);
  }

  static const keys = {'up', 'down', 'left', 'right', 'select', 'back', 'home', 'playpause'};

  /// One D-pad / touchpad press for the TV (screens/remote/remote_pad.dart). Returns false when it
  /// could not be sent: remote off, not signed in, or only the old unsigned room (which takes no keys).
  Future<bool> key(String key) async {
    if (!keys.contains(key) || !await isOn()) return false;
    await _currentRoom();
    if (!signedRoom) return false;
    _sockets.emitArgs('KEY', [_room, key]);
    return true;
  }

  Future<void> play(bool playing) => _player('PLAY', playing);
  Future<void> slide(num seconds) => _player('SLIDE', seconds);
  Future<void> subtitle(dynamic value) => _player('SUBTITLE', value);
  Future<void> mute(bool muted) => _player('MUTE', muted);

  /// tvLogin screen: `emit("tv-login", code, userEmail)`.
  Future<void> tvLogin(String code, String email) async {
    _sockets.emitArgs('tv-login', [code, email]);
  }

  // ---- incoming player events -------------------------------------------
  // Because the phone now joins the user's room ("remote"), the relay also
  // echoes the phone's own PLAY/SLIDE back to it. Echoes of a value we emitted
  // in the last 1.5s are dropped so the local player doesn't fight itself.
  final Map<String, _Emit> _lastEmit = {};

  bool _isEcho(String event, dynamic value) {
    final last = _lastEmit[event];
    if (last == null) return false;
    return last.value == value && DateTime.now().difference(last.at) < const Duration(milliseconds: 1500);
  }

  /// Subscribe to a TV->phone player event ("PLAY", "SLIDE", ...). Returns an
  /// unsubscribe callback — call it from `dispose()`.
  void Function() onPlayerEvent(String event, void Function(dynamic value) handler) {
    dynamic wrapped(dynamic data) {
      if (_isEcho(event, data)) return null;
      handler(data);
      return null;
    }

    _sockets.on(event, wrapped);
    return () => _sockets.off(event, wrapped);
  }
}

class _Emit {
  _Emit(this.value, this.at);
  final dynamic value;
  final DateTime at;
}
