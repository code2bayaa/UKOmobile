import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/picture.dart';
import '../../widgets/sweet_page.dart';
import '../../core/theme.dart';

/// Port of app/(tabs)/playlist.tsx.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  /// [{count, results, type: "movie"|"tv", page}]
  List<Map<String, dynamic>> _playlist = [];

  @override
  void initState() {
    super.initState();
    _initializeMovies(1);
  }

  dynamic _countOf(String type) {
    for (final g in _playlist) {
      if (g['type'] == type) return g['count'];
    }
    return null;
  }

  Future<void> _initializeMovies(int page) async {
    final data = await Http.postJson(Api.playlist, {
      'page': page,
      'email': await Prefs.user,
    });
    if (!mounted) return;
    final groups = data is Map ? data['data'] : null;
    if (data is Map && truthy(data['success']) && groups is List && groups.isNotEmpty) {
      setState(() => _playlist = asMapList(groups));
    } else if (data is Map && truthy(data['error'])) {
      showUkoAlert(context, 'Error', '${data['error']}');
    } else {
      showUkoAlert(context, 'Empty', 'add more movies');
    }
  }

  /// RN pushed `/${type}/id` ("/movie/id" doesn't exist -> movies/id) and
  /// emitted "TvDetail"/"MovieDetail" as the TV path.
  void _navRoute(String type, Map<String, dynamic> state) {
    if (type == 'tv') {
      Nav.replace(context, Routes.tvId, state);
      RemoteService.instance.route(TvPaths.tvId, state);
    } else {
      Nav.replace(context, Routes.moviesId, state);
      RemoteService.instance.route(TvPaths.moviesId, state);
    }
  }

  Future<void> _removePlaylist(dynamic id) async {
    final data = await Http.postJson(Api.removePlaylist, {
      'id': id,
      'email': await Prefs.user,
    });
    if (!mounted) return;
    if (data is Map && truthy(data['status'])) {
      showUkoAlert(context, 'success', '');
    } else if (data is Map && truthy(data['error'])) {
      showUkoAlert(context, 'Error', '${data['error']}');
    } else {
      showUkoAlert(context, 'Error', 'could not remove, try later');
    }
  }

  Widget _pill(double width, Color color, String label, VoidCallback onTap) => SizedBox(
        width: width,
        height: 30,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );

  Widget _renderMovie(Map<String, dynamic> s, String type, double width) {
    final title = or([s['name'], s['original_name']]) ?? '';
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: Picture(picture: or([s['profile_path'], s['poster_path'], s['backdrop_path']]) as String?),
          ),
          SizedBox(
            height: 25,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('$title',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: UkoColors.divider, width: 2)),
            ),
            child: Row(
              children: [
                _pill(width * 0.48, UkoColors.green, 'watch', () => _navRoute(type, {'id': s.idInt})),
                const SizedBox(width: 4),
                _pill(width * 0.48, UkoColors.red, 'remove', () => _removePlaylist(s['id'])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderMovies(Map<String, dynamic> item) {
    final w = MediaQuery.of(context).size.width;
    final itemWidth = w * 0.45;
    final results = asMapList(item['results']);
    final type = (or([item['type'], 'movie'])).toString();
    final total = toNum(item['type'] == 'movie' ? _countOf('movie') : _countOf('tv')).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: w * 0.02,
                decoration: const BoxDecoration(
                  color: UkoColors.slate,
                  border: Border(right: BorderSide(color: Colors.white, width: 10)),
                ),
              ),
              SizedBox(width: w * 0.01),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${item['type'] ?? ''}', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
        SweetPage(
          page: toNum(item['page']).toInt() == 0 ? 1 : toNum(item['page']).toInt(),
          totalPages: total,
          onPageChange: _initializeMovies,
        ),
        SizedBox(
          // card 180 + 25 + 30 + 2 border = 237, plus 8+8 vertical padding
          height: 253,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: results.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _renderMovie(results[i], type, itemWidth),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final movieCount = _countOf('movie');
    final tvCount = _countOf('tv');
    Widget box(String label, dynamic count) => Container(
          width: MediaQuery.of(context).size.width * 0.48,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text('${truthy(count) ? count : 0}', style: const TextStyle(color: UkoColors.muted)),
            ],
          ),
        );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Your favorite movies and tv in one place.',
              textAlign: TextAlign.center, style: TextStyle(color: UkoColors.muted, fontSize: 19)),
        ),
        SizedBox(height: MediaQuery.of(context).size.width * 0.02),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [box('movies', movieCount), box('tv', tvCount)],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_playlist.isEmpty) {
      return Stack(
        alignment: Alignment.center,
        children: [
          FractionallySizedBox(
            widthFactor: 0.8,
            heightFactor: 0.8,
            child: Image.asset('assets/images/playlist.png', fit: BoxFit.contain),
          ),
          const Align(
            alignment: Alignment.topCenter,
            child: Text('No playlist added', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, bottom: 256),
      itemCount: _playlist.length + 1,
      itemBuilder: (_, i) => i == 0 ? _header() : _renderMovies(_playlist[i - 1]),
    );
  }
}
