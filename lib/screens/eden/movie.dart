// Port of web-app/src/components/eden/movie.jsx - an Eden studio's movie.
// Same layout as movies/id.dart; data from edenMoviePayload, images from Eden,
// and play goes straight to the speed player with eden: true so the charge pays the studio.
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

class EdenMovieScreen extends StatefulWidget {
  const EdenMovieScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<EdenMovieScreen> createState() => _EdenMovieScreenState();
}

class _EdenMovieScreenState extends State<EdenMovieScreen> {
  static const _kind = MediaKind.movie;
  static const _white = TextStyle(color: Colors.white);

  Map<String, dynamic>? _movie;
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _genres = [];
  bool _loading = true;
  bool _playlist = false;
  bool _layouts = false;
  bool _needsPhone = false; // in a play region, but the account's phone isn't (PRD #7)
  bool _starting = false;

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
    final data = await Gql.query(kEdenMoviePayloadQuery, {
      'movie': {'id': '$id'},
      'image': {'type': 'movie', 'episode': -1, 'season': -1, 'id': id},
      'credit': {'id': id, 'season': -1, 'episode': -1},
    });
    final payload = data?['edenMoviePayload'];
    Map<String, dynamic>? part(String key) =>
        payload is Map && payload[key] is Map ? Map<String, dynamic>.from(stripTypename(payload[key]) as Map) : null;

    final movie = part('movie');
    final credit = part('credit');
    if (!mounted) return;
    setState(() {
      _movie = movie != null && truthy(movie['success']) ? movie : null;
      _people = [...asMapList(credit?['cast']), ...asMapList(credit?['crew'])];
      _loading = false;
    });
    final m = _movie;
    if (m == null) return;
    isInPlaylist(m['id'], _kind).then((inList) {
      if (inList && mounted) setState(() => _playlist = true);
    });
    _setGenres(m);
  }

  // Eden rows carry genre_ids only - name them from the genre list, as setGenreIDS
  Future<void> _setGenres(Map<String, dynamic> m) async {
    final named = asMapList(m['genres']);
    if (named.isNotEmpty) {
      setState(() => _genres = named);
      return;
    }
    if (m['genre_ids'] is! List) return;
    final ids = (m['genre_ids'] as List).map(toNum).toSet();
    final data = await Gql.query(kGenreQuery, {});
    final g = data?['genre'];
    if (g is! Map || !truthy(g['success']) || !mounted) return;
    setState(() => _genres =
        asMapList(g['data']).where((e) => ids.contains(toNum(e['id'])) && e['mode'] == 'movie').toList());
  }

  Future<void> _addToPlayList() async {
    final m = _movie;
    if (m == null) return;
    final status = await insertIntoPlaylist(m['id'], _kind);
    if (status == null || !mounted) return;
    showUkoAlert(context, status ? 'Success' : 'Error', status ? 'Added to playlist' : 'Already in playlist');
    setState(() => _playlist = true);
  }

  /// PRD #11: a reaction plays the title's own upload - no url, no reaction button
  bool get _hasUrl {
    final url = _movie?['url'];
    return url is Map && truthy(url['fileName']);
  }

  /// An Eden movie is only ever played from its upload - there is no third-party stream to fall back on.
  /// reaction: "start a reaction" - the player opens with the reaction set-up (speed.dart startParty, PRD #11)
  Future<void> _openPlay({bool reaction = false}) async {
    final m = _movie;
    if (m == null || _starting) return;
    final url = m['url'];
    if (url is! Map || !truthy(url['fileName'])) {
      showUkoSnack(context, 'error', 'This title is not uploaded yet');
      return;
    }
    setState(() => _starting = true);
    final ok = await canPlayWithCredits(context, m['id']);
    if (mounted) setState(() => _starting = false);
    if (!ok || !mounted) return;
    final release = '${m['release_date'] ?? ''}';
    Nav.push(context, Routes.videoSpeed, {
      'eden': true, // the credit charge pays the studio (user/credits/earnings.js)
      'stream': 'movie',
      'type': 'movie',
      'id': m['id'],
      'name': or([m['title'], m['original_title']]),
      'background': m['backdrop_path'],
      'dash': url.containsKey('dash'),
      'anime': isAnime(m),
      'date': m['release_date'],
      'year': release.length >= 4 ? release.substring(0, 4) : release,
      if (reaction) 'startParty': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    final m = _movie;
    if (m == null) {
      return const Center(child: Text('This Eden title could not be found.', style: TextStyle(color: UkoColors.divider)));
    }
    final width = MediaQuery.of(context).size.width;
    final btnW = (width - 24) / 2;
    final runtime = toNum(m['runtime']);
    final title = '${or([m['title'], m['original_title']]) ?? ''}';

    return ListView(
      key: ValueKey(_id),
      padding: const EdgeInsets.only(bottom: 128),
      children: [
        Stack(
          children: [
            EdenBackdrop(path: m['backdrop_path']?.toString(), height: 260),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  EdenImage(
                    path: m['poster_path']?.toString(),
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
                        if (truthy(m['original_title']) && m['original_title'] != m['title'])
                          Text('${m['original_title']}', style: const TextStyle(color: UkoColors.gray400)),
                        const SizedBox(height: 4),
                        Text('${m['release_date'] ?? ''}', style: _white),
                        if (runtime > 0)
                          Text(runtime > 60 ? '${runtime ~/ 60} h ${runtime % 60} min' : '${js(runtime)} min',
                              style: _white),
                        if (toNum(m['vote_average']) > 0)
                          Text('★ ${toNum(m['vote_average']).toStringAsFixed(1)}/10',
                              style: const TextStyle(color: UkoColors.yellow)),
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
              if (truthy(m['tagline']))
                Text('"${m['tagline']}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: UkoColors.yellow, fontStyle: FontStyle.italic)),
              GenreLine(genres: _genres),
              const SizedBox(height: 10),
              Text('${or([m['overview'], 'waiting for more content'])}', textAlign: TextAlign.justify, style: _white),
              const SizedBox(height: 8),
              if (truthy(m['original_language']))
                Text('${m['original_language']}', style: const TextStyle(color: UkoColors.gray400)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: btnW,
                    child: PillButton(
                      label: 'trailers',
                      onTap: () => Nav.push(context, Routes.moviesTrailer, {
                        'id': m['id'],
                        'eden': true,
                        'title': title,
                        'background': m['backdrop_path'],
                      }),
                    ),
                  ),
                  if (_layouts)
                    SizedBox(
                      width: btnW,
                      child: PillButton(
                        label: _starting ? ' checking...' : ' play',
                        filled: true,
                        icon: Icons.play_arrow,
                        onTap: _openPlay,
                      ),
                    )
                  else if (_needsPhone)
                    PlayPhonePrompt(width: btnW, onReturn: _runPlayGate),
                  if (_layouts && _hasUrl)
                    SizedBox(
                      width: btnW,
                      child: PillButton(label: ' start a reaction', icon: Icons.groups, onTap: () => _openPlay(reaction: true)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
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
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('CASTS',
                    style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
              ),
              EdenCastRow(people: _people),
            ],
          ),
        ),
        // movies PRD #4: viewers' comments on this Eden movie
        if ((_id ?? toNum(m['id']).toInt()) > 0)
          CommentsSection(type: 'movie', id: _id ?? toNum(m['id']).toInt(), eden: true),
      ],
    );
  }
}
