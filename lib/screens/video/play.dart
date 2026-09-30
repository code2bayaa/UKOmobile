import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import 'player_shared.dart';

/// Port of app/video/play.tsx: react-native-video (`controls`, WebVTT text
/// track) -> media_kit `Video` with its default controls, HOST_PLAY stream +
/// SUB_PLAYING subtitle, and the episodes / seasons rows passed as params.
class VideoPlayScreen extends StatefulWidget {
  const VideoPlayScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<VideoPlayScreen> createState() => _VideoPlayScreenState();
}

class _VideoPlayScreenState extends State<VideoPlayScreen> {
  Map<String, dynamic> get p => widget.params;
  dynamic get _index => p['index'];
  dynamic get _id => p['id'];
  dynamic get _type => p['type'];
  dynamic get _many => p['many'];
  dynamic get _serieName => p['serie_name'];
  dynamic get _serieID => p['serieID'];
  dynamic get _season => p['season'];
  dynamic get _episode => p['episode'];
  dynamic get _anime => p['anime'];

  late final List<dynamic>? _seasonsArr = parseMaybeArray(p['seasons']);
  late final List<dynamic>? _episodesArr = parseMaybeArray(p['episodes']);

  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _isLoadingVideo = true;
  bool _subtitleReady = false;
  bool _videoLoaded = false;
  bool _checkActive = true;

  String get _videoSource => '${Api.hostPlay}/${js(_id)}/${js(_index)}/${js(_many)}';
  String get _subtitleUrl => '${Api.subPlaying}/${js(_id)}/${js(_index)}';

  @override
  void initState() {
    super.initState();
    _subtitleReady = _subtitleUrl.isEmpty;
    final st = _player.stream;
    _subs.addAll([
      // onLoad: video is loaded; hide spinner only when the subtitle is ready.
      st.duration.listen((d) {
        if (d > Duration.zero && !_videoLoaded && mounted) {
          setState(() {
            _videoLoaded = true;
            if (_subtitleReady) _isLoadingVideo = false;
          });
        }
      }),
      // onBuffer
      st.buffering.listen((b) {
        if (mounted && _videoLoaded) setState(() => _isLoadingVideo = b);
      }),
      // onError
      st.error.listen((e) {
        debugPrint('Video error $e');
        if (mounted) setState(() => _isLoadingVideo = false);
      }),
    ]);
    _player.open(Media(_videoSource));
    _checkSubtitle();
    _processPayment();
  }

  @override
  void dispose() {
    _checkActive = false;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  /// HEAD the subtitle, falling back to GET (play.tsx:96).
  Future<void> _checkSubtitle() async {
    if (_subtitleUrl.isEmpty) {
      setState(() => _subtitleReady = true);
      return;
    }
    bool ready;
    try {
      final res = await http.head(Uri.parse(_subtitleUrl));
      if (!_checkActive) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ready = true;
      } else {
        final r2 = await http.get(Uri.parse(_subtitleUrl));
        if (!_checkActive) return;
        ready = r2.statusCode >= 200 && r2.statusCode < 300;
      }
    } catch (_) {
      if (!_checkActive) return;
      ready = false;
    }
    if (!mounted) return;
    setState(() {
      _subtitleReady = ready;
      if (ready && _videoLoaded) _isLoadingVideo = false;
    });
    if (ready) {
      try {
        await _player.setSubtitleTrack(SubtitleTrack.uri(_subtitleUrl, title: 'English', language: 'en'));
      } catch (e) {
        debugPrint('subtitle track failed: $e');
      }
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

  void _navEpisode(Map<String, dynamic> item) {
    Nav.push(context, Routes.tvEpisode, {
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
    });
  }

  void _navSeason(Map<String, dynamic> item) {
    Nav.push(context, Routes.tvSeason, {
      'stream': 'series',
      'id': _serieID,
      'seasonID': item['id'],
      'season': item['season_number'],
      'name': _serieName,
      if (_seasonsArr != null) 'seasons': jsonEncode(_seasonsArr),
      'anime': _anime,
      'background': truthy(item['poster_path']) ? item['poster_path'] : '/image/logo3.png',
    });
  }

  Widget _tile(double itemWidth, VoidCallback onTap, List<Widget> lines) {
    return SizedBox(
      width: itemWidth,
      height: 150,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: itemWidth * 0.6),
          margin: EdgeInsets.all(itemWidth * 0.005),
          padding: const EdgeInsets.only(left: 4),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.white, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
        ),
      ),
    );
  }

  Widget _rating(dynamic v) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_border, size: 16, color: UkoColors.yellow),
        Text(' ${toFixed1(v)}', style: const TextStyle(color: UkoColors.yellow)),
      ]);

  Widget _row(List<Map<String, dynamic>> items, Widget Function(Map<String, dynamic>) builder) {
    return SizedBox(
      height: 150 + 16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (_, i) => builder(items[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final itemWidth = w * 0.45;
    final title = StringBuffer('Playing ${_serieName ?? ''} ');
    if (truthy(_season)) title.write(' || $_season');
    if (truthy(_episode)) title.write(' || $_episode');
    final seasons = asMapList(_seasonsArr);
    final episodes = asMapList(_episodesArr);
    const white = TextStyle(color: Colors.white);

    return Scaffold(
      backgroundColor: UkoColors.background,
      body: SafeArea(
        child: ListView(
          children: [
            Text(title.toString(), style: white),
            Center(
              child: SizedBox(
                width: 350,
                height: 275,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: _video, fit: BoxFit.contain),
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
                                Text('Loading video...', style: white),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (seasons.isNotEmpty && episodes.isNotEmpty)
              Container(
                width: w * 0.8,
                margin: EdgeInsets.only(left: w * 0.1, right: w * 0.1, top: w * 0.02, bottom: w * 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Episodes', style: white),
                    _row(
                        episodes,
                        (item) => _tile(itemWidth, () => _navEpisode(item), [
                              Text('${item['name'] ?? ''}', style: white),
                              Text('episode ${item['episode_number']}', style: white),
                              _rating(item['vote_average']),
                            ])),
                    const Text('Seasons', style: white),
                    _row(seasons, (item) {
                      final count = item['episode_count'];
                      return _tile(itemWidth, () => _navSeason(item), [
                        Text('${item['name'] ?? ''}', style: white),
                        Text(
                            'season ${item['season_number']} || (${js(count)} ${toNum(count) > 1 ? "episodes" : ".episode"})',
                            style: white),
                        _rating(item['vote_average']),
                      ]);
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
