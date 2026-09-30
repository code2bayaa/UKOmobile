// Full-screen vertical trailer swiper shared by home.tsx and
// movies|tv/trailer.tsx (SwiperFlatList vertical + VideoItem with a muted,
// auto-playing react-native-youtube-iframe player).
// Each preview has a like + comment bar at the bottom (widgets/reel_comments.dart,
// user service /reels - it takes the blockbuster trailers too).
// Eden mini series use the same tiles (items with eden: true): their title comes from
// /database/videos movieInfo, the poster is an Eden bucket key, and "Read more" opens the
// Eden detail page (blockbuster trailers open their movie / TV page). Videos play in the app (widgets/yt_player.dart), never on YouTube.
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/picture.dart';
import '../../widgets/reel_comments.dart';
import '../../widgets/yt_player.dart';

/// an Eden reel tagged on a movie or a series opens that title's Eden page
const _edenDetail = {'movie': Routes.moviesEden, 'tv': Routes.tvEden};

/// a blockbuster trailer opens its TMDB title page (clips.dart tags each with its stream)
const _detail = {'movie': Routes.moviesId, 'tv': Routes.tvId};

class TrailerSwiper extends StatefulWidget {
  const TrailerSwiper({super.key, required this.items, this.onNearEnd});

  /// Validated clips from CLIPS: `{key, name, movieInfo}`, or Eden reels from /database/videos.
  final List<Map<String, dynamic>> items;

  /// asked for more when the viewer is three tiles from the end (Eden paging)
  final VoidCallback? onNearEnd;

  @override
  State<TrailerSwiper> createState() => _TrailerSwiperState();
}

class _TrailerSwiperState extends State<TrailerSwiper> {
  final PageController _controller = PageController();
  int _activeIndex = 0;
  // one mute switch for the feed - previews start muted, like the RN swiper
  bool _muted = true;
  // {likes, comments, liked} per trailer key; fetched as new trailers arrive
  final Map<String, Map<String, dynamic>> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant TrailerSwiper old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) _loadStats();
  }

  Future<void> _loadStats() async {
    final fresh = [for (final v in widget.items) '${v['key']}'].where((k) => !_stats.containsKey(k)).toList();
    if (fresh.isEmpty) return;
    for (final k in fresh) {
      _stats[k] = {}; // asked - not again when more trailers arrive
    }
    final got = await ReelsApi.stats(fresh);
    if (!mounted || got.isEmpty) return;
    setState(() => got.forEach((k, v) => _stats[k] = {..._stats[k] ?? {}, ...v}));
  }

  void _updateStat(String key, Map<String, dynamic> change) =>
      setState(() => _stats[key] = {'likes': 0, 'comments': 0, 'liked': false, ..._stats[key] ?? {}, ...change});

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (!mounted) return;
    if (_activeIndex < widget.items.length - 1 && _controller.hasClients) {
      _controller.animateToPage(
        _activeIndex + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      itemCount: widget.items.length,
      onPageChanged: (i) {
        setState(() => _activeIndex = i);
        if (i >= widget.items.length - 3) widget.onNearEnd?.call();
      },
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final key = '${item['key']}';
        return _VideoItem(
          key: ValueKey(key),
          item: item,
          isActive: index == _activeIndex,
          muted: _muted,
          onMute: () => setState(() => _muted = !_muted),
          onVideoEnd: _handleNext,
          reactions: ReelActions(
            reelKey: key,
            stat: _stats[key] ?? const {},
            onChange: (change) => _updateStat(key, change),
            onComments: () => showReelComments(
              context,
              reelKey: key,
              name: '${item['name'] ?? ''}',
              onCount: (n) => _updateStat(key, {'comments': n}),
            ),
          ),
        );
      },
    );
  }
}

class _VideoItem extends StatefulWidget {
  const _VideoItem({
    super.key,
    required this.item,
    required this.isActive,
    required this.muted,
    required this.onMute,
    required this.onVideoEnd,
    required this.reactions,
  });
  final Map<String, dynamic> item;
  final bool isActive;
  final bool muted;
  final VoidCallback onMute;
  final VoidCallback onVideoEnd;

  /// the like + comment bar at the bottom of the preview
  final Widget reactions;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  Timer? _endTimer;

  String get _videoId => '${widget.item['key']}';
  bool get _eden => widget.item['eden'] == true;

  void _ended() {
    _endTimer?.cancel();
    _endTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) widget.onVideoEnd();
    });
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.item['movieInfo'];
    final movie = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final reelName = '${widget.item['name'] ?? ''}';
    final title = '${or([movie['title'], movie['name'], if (_eden) reelName]) ?? ''}';
    final id = widget.item['id'] ?? movie['id'];
    final detail = !truthy(id)
        ? null
        : _eden
            ? _edenDetail[widget.item['type']]
            : _detail[widget.item['stream'] ?? 'movie'];
    final tagline = '${movie['tagline'] ?? ''}';
    final status = '${movie['status'] ?? ''}';
    final overview = '${movie['overview'] ?? ''}';
    final poster = movie['poster_path'];

    return LayoutBuilder(builder: (context, c) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: blurred YouTube thumbnail (blurRadius 10)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Image.network(
                  'https://img.youtube.com/vi/$_videoId/maxresdefault.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, st) => const ColoredBox(color: Colors.black),
                ),
              ),
            ),
            // Overlay rgba(0,0,0,0.4)
            ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
            // Video: absolute, top 20%, full width, height 250
            Positioned(
              top: c.maxHeight * 0.2,
              left: 0,
              right: 0,
              height: 250,
              child: YtPlayer(
                videoId: _videoId,
                active: widget.isActive,
                autoplay: widget.isActive,
                muted: widget.muted,
                onEnded: _ended,
              ),
            ),
            Positioned(
              top: c.maxHeight * 0.2 + 258,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: widget.muted ? 'Sound on' : 'Sound off',
                onPressed: widget.onMute,
                icon: Icon(widget.muted ? Icons.volume_off : Icons.volume_up),
              ),
            ),
            // Content (justifyContent: flex-end)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_eden)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                border: Border.all(color: UkoColors.border), borderRadius: BorderRadius.circular(4)),
                            child: const Text('EDEN MINI SERIES',
                                style: TextStyle(color: UkoColors.divider, fontSize: 11, letterSpacing: 1.2)),
                          ),
                        Text(title,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        // the reel's own name under its title (a title has many reels)
                        if (_eden && reelName.isNotEmpty && reelName != title)
                          Text(reelName, style: const TextStyle(color: UkoColors.divider)),
                        if (tagline.isNotEmpty)
                          Text('"$tagline"',
                              style: const TextStyle(color: UkoColors.yellow, fontStyle: FontStyle.italic)),
                        if (detail != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: OutlinedButton.icon(
                              onPressed: () => Nav.push(context, detail, {'id': id}),
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text('Read more', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: UkoColors.yellow,
                                backgroundColor: Colors.black.withValues(alpha: 0.65),
                                side: const BorderSide(color: UkoColors.yellow, width: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (status.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(status, style: const TextStyle(color: UkoColors.yellow)),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_eden)
                              // Eden posters are bucket keys, never TMDB paths
                              EdenImage(
                                path: poster is String ? poster : null,
                                width: 100,
                                height: 150,
                                borderRadius: BorderRadius.circular(10),
                              )
                            else
                              Picture(
                                picture: poster is String ? poster : null,
                                width: 100,
                                height: 150,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  overview,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: Colors.black.withValues(alpha: 0.45),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: widget.reactions,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
