// An Eden studio's series. The web's eden/serie.jsx is still a copy of the TMDB
// page; this reads Eden's own data: edenTvPayload for the series and its seasons,
// POST /database/eden/episodes for the episodes. Episodes play in the speed player
// with eden: true and the series id, so the charge pays the studio per series.
import 'package:flutter/material.dart';

import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/profile.dart';
import '../../widgets/comments_section.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/play_phone_prompt.dart';
import '../movies/detail_common.dart';
import 'eden_common.dart';

class EdenSerieScreen extends StatefulWidget {
  const EdenSerieScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<EdenSerieScreen> createState() => _EdenSerieScreenState();
}

class _EdenSerieScreenState extends State<EdenSerieScreen> {
  static const _kind = MediaKind.tv;
  static const _white = TextStyle(color: Colors.white);

  Map<String, dynamic>? _serie;
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _genres = [];
  List<Map<String, dynamic>> _episodes = [];
  int? _season;
  bool _loading = true;
  bool _playlist = false;
  bool _layouts = false;
  bool _needsPhone = false; // in a play region, but the account's phone isn't (PRD #7)
  dynamic _starting; // id of the episode whose credit check is running

  int? get _id => P.intOf(widget.params, 'id');

  @override
  void initState() {
    super.initState();
    _load();
    _runPlayGate();
  }

  /// PRD #7 (services/profile.dart): device in Africa / Australia / Brazil and, when signed in,
  /// a phone number from one of them; guests are checked on location only.
  Future<void> _runPlayGate() async {
    final gate = await playGate();
    if (!mounted) return;
    setState(() {
      _layouts = gate == PlayGate.allowed;
      _needsPhone = gate == PlayGate.needsPhone;
    });
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      Gql.query(kEdenTvPayloadQuery, {
        'tv': {'id': '$id'},
        'image': {'type': 'tv', 'episode': -1, 'season': -1, 'id': id},
        'credit': {'id': id, 'season': -1, 'episode': -1},
      }),
      fetchEdenEpisodes(id),
    ]);
    final data = results[0] as Map<String, dynamic>?;
    final episodes = results[1] as List<Map<String, dynamic>>;
    final payload = data?['edenTvPayload'];
    Map<String, dynamic>? part(String key) =>
        payload is Map && payload[key] is Map ? Map<String, dynamic>.from(stripTypename(payload[key]) as Map) : null;

    final serie = part('tv');
    final credit = part('credit');
    if (!mounted) return;
    setState(() {
      _serie = serie != null && truthy(serie['success']) ? serie : null;
      _people = [...asMapList(credit?['cast']), ...asMapList(credit?['crew'])];
      _episodes = episodes;
      final numbers = _seasonNumbers;
      _season = numbers.isEmpty ? null : numbers.first;
      _loading = false;
    });
    final s = _serie;
    if (s == null) return;
    isInPlaylist(s['id'], _kind).then((inList) {
      if (inList && mounted) setState(() => _playlist = true);
    });
    _setGenres(s);
  }

  Future<void> _setGenres(Map<String, dynamic> s) async {
    final named = asMapList(s['genres']);
    if (named.isNotEmpty) {
      setState(() => _genres = named);
      return;
    }
    if (s['genre_ids'] is! List) return;
    final ids = (s['genre_ids'] as List).map(toNum).toSet();
    final data = await Gql.query(kGenreQuery, {});
    final g = data?['genre'];
    if (g is! Map || !truthy(g['success']) || !mounted) return;
    setState(() =>
        _genres = asMapList(g['data']).where((e) => ids.contains(toNum(e['id'])) && e['mode'] == 'tv').toList());
  }

  /// Seasons the studio made plus any an episode is filed under, in order.
  List<int> get _seasonNumbers {
    final set = <int>{
      for (final s in asMapList(_serie?['seasons'])) toNum(s['season_number']).toInt(),
      for (final e in _episodes) toNum(e['season_number']).toInt(),
    }..removeWhere((n) => n <= 0);
    return set.toList()..sort();
  }

  Map<String, dynamic>? _seasonInfo(int number) {
    for (final s in asMapList(_serie?['seasons'])) {
      if (toNum(s['season_number']).toInt() == number) return s;
    }
    return null;
  }

  Future<void> _addToPlayList() async {
    final s = _serie;
    if (s == null) return;
    final status = await insertIntoPlaylist(s['id'], _kind);
    if (status == null || !mounted) return;
    showUkoAlert(context, status ? 'Success' : 'Error', status ? 'Added to playlist' : 'Already in playlist');
    setState(() => _playlist = true);
  }

  /// reaction: "start a reaction" - the player opens with the reaction set-up (speed.dart startParty, PRD #11)
  Future<void> _playEpisode(Map<String, dynamic> e, {bool reaction = false}) async {
    final s = _serie;
    if (s == null || _starting != null) return;
    if (!truthy(e['playable'])) {
      showUkoSnack(context, 'error', 'This episode is not uploaded yet');
      return;
    }
    setState(() => _starting = e['id']);
    final ok = await canPlayWithCredits(context, e['id']);
    if (mounted) setState(() => _starting = null);
    if (!ok || !mounted) return;
    // no season/serieID here: those send the speed player to TMDB for the next episode
    Nav.push(context, Routes.videoSpeed, {
      'eden': true, // the credit charge pays the studio (user/credits/earnings.js)
      'eden_series': s['id'], // producers are paid per series
      'stream': 'tv',
      'type': 'episode',
      'id': e['id'],
      'name': e['name'],
      'serie_name': or([s['name'], s['original_name']]),
      'background': or([e['backdrop_path'], s['backdrop_path']]),
      'anime': isAnime(s),
      'date': e['date'],
      if (reaction) 'startParty': true,
    });
  }

  Map<String, dynamic>? get _firstPlayable {
    final list = _episodes.where((e) => truthy(e['playable'])).toList()
      ..sort((a, b) {
        final bySeason = toNum(a['season_number']).compareTo(toNum(b['season_number']));
        return bySeason != 0 ? bySeason : toNum(a['episode_number']).compareTo(toNum(b['episode_number']));
      });
    return list.isEmpty ? null : list.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    final s = _serie;
    if (s == null) {
      return const Center(child: Text('This Eden series could not be found.', style: TextStyle(color: UkoColors.divider)));
    }
    final width = MediaQuery.of(context).size.width;
    final btnW = (width - 24) / 2;
    final title = '${or([s['name'], s['original_name']]) ?? ''}';
    final seasons = _seasonNumbers;
    final season = _season;
    final seasonInfo = season == null ? null : _seasonInfo(season);
    final shown = season == null
        ? const <Map<String, dynamic>>[]
        : _episodes.where((e) => toNum(e['season_number']).toInt() == season).toList();

    return ListView(
      key: ValueKey(_id),
      padding: const EdgeInsets.only(bottom: 128),
      children: [
        Stack(
          children: [
            EdenBackdrop(path: s['backdrop_path']?.toString(), height: 260),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  EdenImage(
                    path: s['poster_path']?.toString(),
                    width: width * 0.36,
                    height: width * 0.54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EdenTag(),
                        const SizedBox(height: 8),
                        Text(title,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        if (truthy(s['original_name']) && s['original_name'] != s['name'])
                          Text('${s['original_name']}', style: const TextStyle(color: UkoColors.gray400)),
                        const SizedBox(height: 4),
                        Text('${s['first_air_date'] ?? ''}', style: _white),
                        Text(
                          '${seasons.length} season${seasons.length == 1 ? '' : 's'} · '
                          '${_episodes.length} episode${_episodes.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: UkoColors.gray400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (truthy(s['tagline']))
                Text('"${s['tagline']}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: UkoColors.yellow, fontStyle: FontStyle.italic)),
              GenreLine(genres: _genres),
              const SizedBox(height: 10),
              Text('${or([s['overview'], 'waiting for more content'])}', textAlign: TextAlign.justify, style: _white),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: btnW,
                    child: PillButton(
                      label: 'trailers',
                      onTap: () => Nav.push(context, Routes.tvTrailer, {
                        'id': s['id'],
                        'eden': true,
                        'title': title,
                        'background': s['backdrop_path'],
                      }),
                    ),
                  ),
                  SizedBox(
                    width: btnW,
                    child: Material(
                      color: UkoColors.yellow,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: _addToPlayList,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Center(
                            child: Text(_playlist ? 'Added to Playlist' : 'Add to Playlist',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_layouts && _firstPlayable != null)
                    SizedBox(
                      width: btnW,
                      child: PillButton(
                          label: ' start a reaction', icon: Icons.groups, onTap: () => _playEpisode(_firstPlayable!, reaction: true)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (seasons.isEmpty)
                const Text('No episodes uploaded yet.', style: TextStyle(color: UkoColors.divider))
              else ...[
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: seasons.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final n = seasons[i];
                      final active = n == season;
                      return OutlinedButton(
                        onPressed: () => setState(() => _season = n),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: active ? UkoColors.yellow : UkoColors.divider,
                          side: BorderSide(color: active ? UkoColors.yellow : UkoColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        child: Text('Season $n'),
                      );
                    },
                  ),
                ),
                if (seasonInfo != null) ...[
                  const SizedBox(height: 8),
                  Text('${seasonInfo['name'] ?? ''}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (truthy(seasonInfo['overview']))
                    Text('${seasonInfo['overview']}', style: const TextStyle(color: UkoColors.gray400)),
                ],
                const SizedBox(height: 8),
                if (_needsPhone && shown.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PlayPhonePrompt(width: double.infinity, onReturn: _runPlayGate),
                  ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No episodes uploaded for this season yet.', style: TextStyle(color: UkoColors.divider)),
                  ),
                for (final e in shown)
                  _EpisodeTile(
                    episode: e,
                    fallbackImage: s['backdrop_path']?.toString(),
                    canPlay: _layouts,
                    starting: _starting == e['id'],
                    onPlay: () => _playEpisode(e),
                  ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('CASTS',
                    style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
              ),
              EdenCastRow(people: _people),
            ],
          ),
        ),
        // movies PRD #4: viewers' comments on this Eden series
        if ((_id ?? toNum(s['id']).toInt()) > 0)
          CommentsSection(type: 'tv', id: _id ?? toNum(s['id']).toInt(), eden: true),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.fallbackImage,
    required this.canPlay,
    required this.starting,
    required this.onPlay,
  });
  final Map<String, dynamic> episode;
  final String? fallbackImage;
  final bool canPlay;
  final bool starting;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final playable = truthy(e['playable']);
    final runtime = toNum(e['runtime']);
    final image = '${or([e['backdrop_path'], e['poster_path'], fallbackImage]) ?? ''}';
    final thumbW = MediaQuery.of(context).size.width * 0.38;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: UkoColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: UkoColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canPlay ? onPlay : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: thumbW,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      EdenImage(path: image.isEmpty ? null : image),
                      if (canPlay)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.3),
                          child: Center(
                            child: starting
                                ? const SizedBox(
                                    width: 26, height: 26, child: CircularProgressIndicator(color: UkoColors.yellow))
                                : Icon(playable ? Icons.play_arrow : Icons.hourglass_empty,
                                    color: playable ? UkoColors.yellow : UkoColors.divider, size: 32),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('E${js(e['episode_number'])} · ${e['name'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(
                        [
                          if (runtime > 0) '${js(runtime)} min',
                          if (truthy(e['episode_type'])) '${e['episode_type']}',
                          if (!playable) 'coming soon',
                        ].join(' · '),
                        style: const TextStyle(color: UkoColors.divider, fontSize: 12),
                      ),
                      if (truthy(e['overview']))
                        Text('${e['overview']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: UkoColors.gray400, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
