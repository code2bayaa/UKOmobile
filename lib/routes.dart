import 'package:flutter/material.dart';

import 'core/media.dart';

import 'screens/auth/change.dart';
import 'screens/auth/sign_in.dart';
import 'screens/auth/signup.dart';
import 'screens/browse/browse.dart';
import 'screens/eden/eden_list.dart';
import 'screens/eden/movie.dart';
import 'screens/eden/serie.dart';
import 'screens/eden/person.dart';
import 'screens/credits/buy.dart';
import 'screens/credits/earn.dart';
import 'screens/credits/earn_ads.dart';
import 'widgets/credit_gate.dart';
import 'screens/home/home.dart';
import 'screens/movies/id.dart';
import 'screens/not_found.dart';
import 'screens/offline/downloads.dart';
import 'screens/offline/play.dart';
import 'screens/offline/buy.dart';
import 'screens/offline/sales.dart';
import 'screens/offline/sell.dart';
import 'screens/people/id.dart';
import 'screens/people/page.dart';
import 'screens/platform/platform.dart';
import 'screens/shared/discover.dart';
import 'screens/shared/related.dart';
import 'screens/shared/trailer.dart';
import 'screens/tv/episode.dart';
import 'screens/tv/id.dart';
import 'screens/tv/season.dart';
import 'screens/user/following.dart';
import 'screens/user/playlist.dart';
import 'screens/user/profile.dart';
import 'screens/user/search.dart';
import 'screens/remote/remote_pad.dart';
import 'screens/user/tv_login.dart';
import 'screens/video/play.dart';
import 'screens/video/speed.dart';
import 'screens/party/join_party.dart';
import 'screens/party/reactions.dart';
import 'screens/video/stream.dart';
import 'screens/video/vlc.dart';
import 'shell/tab_shell.dart';
import 'widgets/sign_in_required.dart';

/// Route names mirror the expo-router paths of the RN app (app/**) so the
/// port can be compared file by file. NOTE: these are *phone* routes; TV
/// routes for the remote live in services/remote.dart (TvPaths).
class Routes {
  Routes._();
  // stack screens (outside the (tabs) group)
  static const signIn = '/';
  static const signup = '/signup';
  static const change = '/change';
  static const offlineDownloads = '/offline/downloads';
  static const offlinePlay = '/offline/play';
  // selling downloaded videos phone to phone (movies PRD #10)
  static const offlineSell = '/offline/sell';
  static const offlineBuy = '/offline/buy';
  static const offlineSales = '/offline/sales';
  static const videoPlay = '/video/play';
  static const videoSpeed = '/video/speed';
  static const videoStream = '/video/stream';
  static const videoVlc = '/video/vlc';

  // (tabs) group — rendered inside TabShell (header + drawer + bottom tabs)
  static const home = '/home';
  static const moviesPage = '/movies/page';
  static const moviesId = '/movies/id';
  static const moviesSimilar = '/movies/similar';
  static const moviesRecommendation = '/movies/recommendation';
  static const moviesTrailer = '/movies/trailer';
  static const moviesEden = '/eden/movies/id'; // an Eden studio's movie (web /eden/movies/id)
  static const moviesDiscover = '/movies/discover';
  static const tvPage = '/tv/page';
  static const tvId = '/tv/id';
  static const tvSeason = '/tv/season';
  static const tvEpisode = '/tv/episode';
  static const tvSimilar = '/tv/similar';
  static const tvRecommendation = '/tv/recommendation';
  static const tvTrailer = '/tv/trailer';
  static const tvEden = '/eden/series/id'; // an Eden studio's series (web /eden/series/id)
  static const edenMovies = '/eden/movies'; // Eden studios' movies in rows (web /eden/movies)
  static const edenSeries = '/eden/series'; // Eden studios' series in rows (web /eden/series)
  static const edenPeopleId = '/eden/people/id'; // an Eden studio's cast/crew member (web /eden/people/id)
  static const tvDiscover = '/tv/discover';
  static const peoplePage = '/people/page';
  static const peopleId = '/people/id';
  static const search = '/search';
  static const following = '/following';
  static const playlist = '/playlist';
  static const creditsEarn = '/credits/earn';
  static const creditsEarnAds = '/credits/earn/ads'; // watch UKOshop ads for credits (movies PRD #15)
  static const creditsBuy = '/credits/buy';
  static const tvLogin = '/tvLogin';
  static const remotePad = '/remote'; // phone as the TV's D-pad / touchpad (movies PRD #12)
  static const profile = '/profile'; // phone + country/county/ward (movies PRD #6)
  static const party = '/party'; // join a watch party by code (movies PRD #11)
  static const reactions = '/reactions'; // live public reactions (movies PRD #11)

  /// `/screens/<platform>` — netflix | disney | anime | hindu | korean | china
  static String platform(String key) => '/screens/$key';
  static const platforms = ['netflix', 'disney', 'anime', 'hindu', 'korean', 'china'];
}

class _TabRoute {
  const _TabRoute(this.title, this.tab, this.builder);
  final String title;
  final UkoTab? tab;
  final Widget Function(Map<String, dynamic> p) builder;
}

final Map<String, _TabRoute> _tabRoutes = {
  Routes.home: _TabRoute('Home', UkoTab.home, (p) => const HomeScreen()),
  Routes.moviesPage: _TabRoute('Movies', UkoTab.movies, (p) => const BrowseScreen(kind: MediaKind.movie)),
  Routes.tvPage: _TabRoute('TV Shows', UkoTab.tv, (p) => const BrowseScreen(kind: MediaKind.tv)),
  Routes.peoplePage: _TabRoute('People', UkoTab.people, (p) => const PeoplePageScreen()),
  Routes.peopleId: _TabRoute('Person', null, (p) => PersonScreen(params: p)),
  Routes.search: _TabRoute('Search', null, (p) => SearchScreen(params: p)),
  Routes.creditsEarn: _TabRoute('Earn', null, (p) => const CreditGate(child: EarnCreditsScreen())),
  Routes.creditsEarnAds: _TabRoute('Watch ads', null, (p) => const CreditGate(child: EarnAdsScreen())),
  Routes.creditsBuy: _TabRoute('Subscribe', null, (p) => const CreditGate(child: BuyCreditsScreen())),
  Routes.following: _TabRoute('Following', null, (p) => FollowingScreen(params: p)),
  Routes.playlist: _TabRoute('Playlist', null, (p) => PlaylistScreen(params: p)),
  Routes.tvLogin: _TabRoute('Tv Login', null, (p) => const TvLoginScreen()),
  Routes.remotePad: _TabRoute('TV Remote', null, (p) => const RemotePadScreen()),
  Routes.profile: _TabRoute('Profile', null, (p) => const ProfileScreen()),
  Routes.party: _TabRoute('Join a reaction', null, (p) => JoinPartyScreen(params: p)),
  Routes.reactions: _TabRoute('Reactions', null, (p) => const ReactionsScreen()),
  Routes.moviesId: _TabRoute('Movie', null, (p) => MovieDetailScreen(params: p)),
  Routes.moviesSimilar: _TabRoute('Similar Movies', null,
      (p) => RelatedScreen(kind: MediaKind.movie, mode: RelatedMode.similar, params: p)),
  Routes.moviesRecommendation: _TabRoute('Recommended Movies', null,
      (p) => RelatedScreen(kind: MediaKind.movie, mode: RelatedMode.recommendation, params: p)),
  Routes.moviesTrailer: _TabRoute('Movie Trailer', null, (p) => TrailerScreen(kind: MediaKind.movie, params: p)),
  Routes.moviesDiscover: _TabRoute('Discover Movie', null, (p) => DiscoverScreen(kind: MediaKind.movie, params: p)),
  Routes.tvDiscover: _TabRoute('Discover TV Shows', null, (p) => DiscoverScreen(kind: MediaKind.tv, params: p)),
  Routes.tvId: _TabRoute('TV', null, (p) => TvDetailScreen(params: p)),
  Routes.moviesEden: _TabRoute('Eden Movie', null, (p) => EdenMovieScreen(params: p)),
  Routes.tvEden: _TabRoute('Eden Series', null, (p) => EdenSerieScreen(params: p)),
  Routes.edenMovies: _TabRoute('Eden Movies', UkoTab.movies, (p) => const EdenListScreen(kind: MediaKind.movie)),
  Routes.edenSeries: _TabRoute('Eden Series', UkoTab.tv, (p) => const EdenListScreen(kind: MediaKind.tv)),
  Routes.edenPeopleId: _TabRoute('Eden Person', null, (p) => EdenPersonScreen(params: p)),
  Routes.tvSeason: _TabRoute('Season', null, (p) => SeasonScreen(params: p)),
  Routes.tvEpisode: _TabRoute('Episode', null, (p) => EpisodeScreen(params: p)),
  Routes.tvSimilar: _TabRoute(
      'Similar TV', null, (p) => RelatedScreen(kind: MediaKind.tv, mode: RelatedMode.similar, params: p)),
  Routes.tvRecommendation: _TabRoute('Recommended TV', null,
      (p) => RelatedScreen(kind: MediaKind.tv, mode: RelatedMode.recommendation, params: p)),
  Routes.tvTrailer: _TabRoute('TV Trailer', null, (p) => TrailerScreen(kind: MediaKind.tv, params: p)),
  for (final k in Routes.platforms)
    Routes.platform(k): _TabRoute(PlatformScreen.titleFor(k), null, (p) => PlatformScreen(platform: k)),
};

/// Movies PRD #5: blockbuster movies / series lists, movie, serie, season and episode screens,
/// and the players for non-Eden content need an account. Eden screens (edenMovies, edenSeries, moviesEden, tvEden,
/// edenPeopleId) and players opened with `eden: true` stay open to guests.
const _signInRoutes = <String>{
  Routes.moviesPage,
  Routes.moviesId,
  Routes.tvPage,
  Routes.tvId,
  Routes.tvSeason,
  Routes.tvEpisode,
  Routes.profile,
  // PRD #11: a party seat is an account's
  Routes.party,
  Routes.reactions,
  // PRD #10: buying and selling run on the account (M-PESA, sales balance)
  Routes.offlineSell,
  Routes.offlineBuy,
  Routes.offlineSales,
};
const _playerRoutes = <String>{Routes.videoSpeed, Routes.videoPlay, Routes.videoStream, Routes.videoVlc};

bool _needsSignIn(String name, Map<String, dynamic> p) {
  if (_signInRoutes.contains(name)) return true;
  final eden = p['eden'];
  return _playerRoutes.contains(name) && !(eden == true || eden == 'true' || eden == 1);
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? Routes.signIn;
  final args = settings.arguments;
  final Map<String, dynamic> p = args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{};
  Widget guard(Widget page) => _needsSignIn(name, p) ? SignInRequired(route: name, params: p, child: page) : page;

  final tabRoute = _tabRoutes[name];
  if (tabRoute != null) {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) =>
          TabShell(title: tabRoute.title, currentTab: tabRoute.tab, child: guard(tabRoute.builder(p))),
    );
  }

  Widget page;
  switch (name) {
    case Routes.signIn:
      page = SignInScreen(params: p);
    case Routes.signup:
      page = const SignUpScreen();
    case Routes.change:
      page = ChangePasswordScreen(params: p);
    case Routes.offlineDownloads:
      page = const OfflineDownloadsScreen();
    case Routes.offlineSell:
      page = SellVideoScreen(params: p);
    case Routes.offlineBuy:
      page = const BuyVideoScreen();
    case Routes.offlineSales:
      page = const SellerSalesScreen();
    case Routes.offlinePlay:
      page = OfflinePlayScreen(params: p);
    case Routes.videoPlay:
      page = VideoPlayScreen(params: p);
    case Routes.videoSpeed:
      page = SpeedPlayerScreen(params: p);
    case Routes.videoStream:
      page = StreamScreen(params: p);
    case Routes.videoVlc:
      page = VlcPlayerScreen(params: p);
    default:
      page = const NotFoundScreen();
  }
  final guarded = guard(page);
  return MaterialPageRoute(settings: settings, builder: (_) => guarded);
}

/// expo-router `router` replacement.
class Nav {
  Nav._();

  /// `router.push({pathname, params})`
  static Future<T?> push<T>(BuildContext context, String route, [Map<String, dynamic>? params]) =>
      Navigator.of(context).pushNamed<T>(route, arguments: params ?? const <String, dynamic>{});

  /// `router.replace({pathname, params})`
  static Future<T?> replace<T>(BuildContext context, String route, [Map<String, dynamic>? params]) =>
      Navigator.of(context).pushReplacementNamed<T, dynamic>(route, arguments: params ?? const <String, dynamic>{});

  /// Tab-bar switch: keep `/home` at the root so Android back returns home
  /// (expo-router Tabs' default "firstRoute" back behaviour).
  static void switchTab(BuildContext context, String route) {
    final nav = Navigator.of(context);
    if (route == Routes.home) {
      nav.pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } else {
      nav.pushNamedAndRemoveUntil(route, ModalRoute.withName(Routes.home));
    }
  }

  /// After sign-in / sign-out: `router.replace("/home")` / `router.replace("/")`.
  static void resetTo(BuildContext context, String route, [Map<String, dynamic>? params]) {
    Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false, arguments: params);
  }
}
