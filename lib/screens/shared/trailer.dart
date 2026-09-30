// Every trailer on one title, laid out like the web's Eden mini series row
// (web-app/src/components/trailer.jsx): a player on top, a card per trailer below.
// Eden titles (params eden: true) read their studio's reels - trailers, then mini
// series - from /database/videos mode "title"; blockbusters read TMDB through Clips.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/yt_player.dart';
import '../home/clips.dart';

class TrailerScreen extends StatefulWidget {
  const TrailerScreen({super.key, required this.kind, this.params = const {}});
  final MediaKind kind;
  final Map<String, dynamic> params;

  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends State<TrailerScreen> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  Timer? _giveUp;
  int _playing = 0;
  bool _loading = true;

  // Built once so Clips does not re-run on every rebuild.
  late final List<Map<String, dynamic>> _data = [
    {
      'results': [
        {'id': widget.params['id']},
      ],
    },
  ];

  bool get _eden => P.boolOf(widget.params, 'eden');

  @override
  void initState() {
    super.initState();
    if (_eden) {
      _loadEden();
    } else {
      // a blockbuster with no trailers never calls back - stop the spinner after a while
      _giveUp = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadEden() async {
    final res = await Http.postJson(Api.videos, {
      'page': 1,
      'type': widget.kind.api,
      'id': widget.params['id'],
      'mode': 'title',
    });
    if (!mounted) return;
    _add(res is Map ? asMapList(res['data']) : const []);
    setState(() => _loading = false);
  }

  // merge a batch into the list once per key; the first one starts playing
  void _add(List<Map<String, dynamic>> videos) {
    if (!mounted) return;
    final fresh = videos
        .where((v) => v['key'] != null && '${v['key']}'.isNotEmpty && !_items.any((p) => p['key'] == v['key']))
        .toList();
    if (fresh.isEmpty) return;
    setState(() {
      _items.addAll(fresh);
      _loading = false;
    });
  }

  // roll on to the next trailer when one ends
  void _onEnded() {
    if (_playing < _items.length - 1) _play(_playing + 1, scroll: false);
  }

  void _play(int index, {bool scroll = true}) {
    setState(() => _playing = index);
    if (scroll && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = widget.kind.isTv;
    final title = P.str(widget.params, 'title');
    final background = widget.params['background'];
    final width = MediaQuery.of(context).size.width;
    final current = _items.isEmpty ? null : _items[_playing];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_eden)
          Clips(
            many: true,
            season: tv ? P.str(widget.params, 'season') : null,
            episode: tv ? P.str(widget.params, 'episode') : null,
            addValidation: _add,
            data: _data,
            stream: widget.kind.api,
          ),
        if (background is String && background.isNotEmpty)
          EdenImage(path: background, fit: BoxFit.cover), // Eden bucket keys or TMDB paths
        ColoredBox(color: Colors.black.withValues(alpha: 0.82)),
        CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              sliver: SliverList.list(children: [
                Row(
                  children: [
                    Expanded(
                      child: SectionHeader(
                        (title != null && title.isNotEmpty) ? '$title - trailers' : '${tv ? 'Series' : 'Movie'} trailers',
                        fontSize: 20,
                        barWidthFactor: 0.015,
                      ),
                    ),
                    if (_eden) const _Tag('Eden'),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: current != null
                        ? YtPlayer(videoId: '${current['key']}', onEnded: _onEnded)
                        : ColoredBox(
                            color: _loading ? UkoColors.gray800 : Colors.black,
                            child: _loading
                                ? const LoadingView()
                                : const Center(
                                    child: Text('No trailers yet for this title.',
                                        style: TextStyle(color: UkoColors.divider)),
                                  ),
                          ),
                  ),
                ),
                if (current != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('${current['name'] ?? ''}', style: const TextStyle(color: UkoColors.yellow)),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 128),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: width >= 900 ? 4 : (width >= 600 ? 3 : 2),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) => _TrailerCard(
                  item: _items[index],
                  active: index == _playing,
                  onTap: () => _play(index),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.item, required this.active, required this.onTap});
  final Map<String, dynamic> item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final key = '${item['key']}';
    return Material(
      color: UkoColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? UkoColors.yellow : UkoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // hqdefault exists for every upload, maxresdefault does not
                  Image.network(
                    'https://img.youtube.com/vi/$key/hqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, e, st) => const ColoredBox(color: Colors.black),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: active ? 0.35 : 0.15)),
                  Center(
                    child: Icon(active ? Icons.graphic_eq : Icons.play_arrow,
                        color: UkoColors.yellow, size: 34),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['name'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                    if (item['mode'] == 'mini_series')
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('Mini series', style: TextStyle(color: UkoColors.divider, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: UkoColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label.toUpperCase(),
          style: const TextStyle(color: UkoColors.divider, fontSize: 11, letterSpacing: 1.2)),
    );
  }
}
