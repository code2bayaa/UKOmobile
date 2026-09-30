// Eden mini series on the phone home, laid out like the Blockbusters tab: one
// full-screen vertical swiper (trailer_swiper.dart) of auto-playing reels, played in
// the app. Movie and series reels (/database/videos mode "mini_series", tv also takes
// reels on a season or episode) are interleaved and paged in as the viewer nears the end.
// PRD #26: each tile keeps its like + comment bar (widgets/reel_comments.dart).
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../widgets/common.dart';
import 'trailer_swiper.dart';

class _Stream {
  _Stream(this.type);
  final String type;
  int page = 0;
  int totalPages = 1;
  bool get done => page >= totalPages;
}

class MiniSeriesFeed extends StatefulWidget {
  const MiniSeriesFeed({super.key});

  @override
  State<MiniSeriesFeed> createState() => _MiniSeriesFeedState();
}

class _MiniSeriesFeedState extends State<MiniSeriesFeed> {
  final List<Map<String, dynamic>> _items = [];
  final _streams = [_Stream('movie'), _Stream('tv')];
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<List<Map<String, dynamic>>> _page(_Stream s) async {
    if (s.done) return const [];
    final res = await Http.postJson(Api.videos, {'page': s.page + 1, 'type': s.type, 'mode': 'mini_series'});
    if (res is! Map || res['data'] is! List) throw StateError('mini series ${s.type} failed');
    s.page++;
    s.totalPages = (res['total_pages'] is num) ? (res['total_pages'] as num).toInt() : 1;
    return asMapList(res['data']);
  }

  // the next page of both streams, movie and series reels taking turns
  Future<void> _more() async {
    if (_loading || _streams.every((s) => s.done)) return;
    setState(() => _loading = true);
    try {
      final pages = await Future.wait(_streams.map(_page));
      if (!mounted) return;
      final seen = _items.map((e) => e['key']).toSet();
      final merged = <Map<String, dynamic>>[];
      final longest = pages.fold<int>(0, (n, p) => p.length > n ? p.length : n);
      for (var i = 0; i < longest; i++) {
        for (final p in pages) {
          if (i < p.length && p[i]['key'] != null && seen.add(p[i]['key'])) merged.add(p[i]);
        }
      }
      setState(() {
        _items.addAll(merged);
        _failed = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _failed = _items.isEmpty);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const LoadingView();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_failed ? 'Mini series could not load.' : 'No mini series yet.',
                style: const TextStyle(color: UkoColors.divider)),
            if (_failed) TextButton(onPressed: _more, child: const Text('Try again')),
          ],
        ),
      );
    }
    return TrailerSwiper(items: List.unmodifiable(_items), onNearEnd: _more);
  }
}
