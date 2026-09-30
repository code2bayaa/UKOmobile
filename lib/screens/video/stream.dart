import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import 'collection.dart';
import 'player_shared.dart';

const String _fetchPlayQuery = r'''
    query Play (
        $type: String!
        $season: Int!
        $episode: Int!
        $id : Int!
    ){
        play(
            type:$type,
            episode:$episode,
            season:$season,
            id:$id
        ) {
            tokens {
                title
                link
                seeders
                leechers
                size
                dateUploaded
                quality
                imdbId
                imdbLink
                token
                portal
            }

            success
            error
        }
    }
  ''';

const String _updatePlayMutation = r'''
      mutation UpdatePlay(
          $tokens: [PLAY_DATA_INPUT!]
          $type: String!
          $season: Int!
          $episode: Int!
          $id : Int!
          $token_expire: String
      ) {
          updatePlay(
              tokens: $tokens
              type: $type
              season: $season
              episode: $episode
              id: $id
              token_expire: $token_expire
          ){
              success
              error
          }
      }
    ''';

/// Port of app/video/stream.tsx: lists the torrent "collections" (qualities)
/// for a movie / episode. Cached tokens come from the `play` GraphQL query;
/// otherwise 4 parallel STREAM rounds (address 1..4) fetch fresh ones and
/// store them with `updatePlay`.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  List<Map<String, dynamic>>? _play;
  num _maxRate = 0;
  Map<String, dynamic>? _bests;
  double _target = 9.8;

  Map<String, dynamic> get p => widget.params;
  dynamic get _id => p['id'];
  dynamic get _stream => p['stream'];
  dynamic get _name => p['name'];
  dynamic get _year => p['year'];
  dynamic get _date => p['date'];
  dynamic get _imdbId => p['imdbId'];
  dynamic get _season => p['season'];
  dynamic get _episode => p['episode'];
  dynamic get _background => p['background'];
  dynamic get _anime => p['anime'];
  dynamic get _serieID => p['serieID'];

  String get _type => _stream == 'series'
      ? 'tv'
      : _stream == 'season'
          ? 'season'
          : _stream == 'episode'
              ? 'episode'
              : 'movie';

  @override
  void initState() {
    super.initState();
    _fetchToken();
  }

  /// `new Date(date)`; null when invalid (JS Invalid Date).
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse('$v');
  }

  /// checkCAM: every token is CAM and was uploaded on an earlier day of the
  /// month than `date` -> refresh.
  bool _checkCAM(List<Map<String, dynamic>> tokens) {
    if (tokens.isEmpty) return false;
    final now = _parseDate(_date);
    bool checkDate(dynamic current) {
      final then = _parseDate(current);
      if (now == null || then == null) return false; // NaN comparison
      return now.day > then.day;
    }

    return tokens.every((t) {
      final q = t['quality'];
      return checkDate(t['dateUploaded']) && truthy(q) && RegExp('CAM', caseSensitive: false).hasMatch('$q');
    });
  }

  static bool _isSmall(dynamic size) =>
      truthy(size) && RegExp(r'mib|mb', caseSensitive: false).hasMatch('$size');
  static bool _isLarge(dynamic size) =>
      truthy(size) && RegExp(r'gib|gb', caseSensitive: false).hasMatch('$size');
  static num _sizeNum(dynamic size) {
    final m = RegExp(r'[\d.]+').firstMatch('$size');
    return m == null ? 0 : (num.tryParse(m.group(0)!) ?? 0);
  }

  /// JS Array.prototype.sort is stable; Dart's List.sort is not.
  static List<T> _stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final c = cmp(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  List<Map<String, dynamic>> _smallThenLarge(List<Map<String, dynamic>> list) {
    final smallest = list.where((t) => _isSmall(t['size'])).toList();
    final largest = _stableSort(list.where((t) => _isLarge(t['size'])).toList(), (a, b) {
      final first = _sizeNum(a['size']);
      final second = _sizeNum(b['size']);
      if (first == 0 || second == 0) return 0;
      return (first - second).sign.toInt();
    });
    return smallest.isNotEmpty ? [...smallest, ...largest] : [...largest];
  }

  /// cleanTokens (stream.tsx:153). [target] is the `target` state captured by
  /// the calling closure.
  List<Map<String, dynamic>> _cleanTokens(List<Map<String, dynamic>> tokens, double target) {
    if (tokens.isEmpty) return [];
    final sorted = _stableSort(
        List<Map<String, dynamic>>.from(tokens), (a, b) => (toNum(b['seeders']) - toNum(a['seeders'])).sign.toInt());
    final maxRate = toNum(sorted[0]['seeders']);

    if (maxRate == 0) {
      if (mounted) setState(() => _maxRate = 0);
      return sorted
          .map((t) => {...t, 'seeders': toNum(t['seeders']), 'leechers': toNum(t['leechers'])})
          .toList();
    }
    var newSorted = sorted.where((t) => (toNum(t['seeders']) / maxRate) * 10 > target).toList();
    newSorted = _smallThenLarge(newSorted);

    if (newSorted.length < 5) {
      if (mounted) setState(() => _target = _target - 0.3);
      newSorted = sorted.where((t) => (toNum(t['seeders']) / maxRate) * 10 > 9.5).toList();
      newSorted = _smallThenLarge(newSorted);
    }

    var indexed = 0;
    var next = indexed + 1;
    Map<String, dynamic>? best = newSorted.isNotEmpty ? newSorted[indexed] : null;
    bool isCam(Map<String, dynamic>? b) =>
        b != null && truthy(b['quality']) && RegExp('CAM', caseSensitive: false).hasMatch('${b['quality']}');
    while (isCam(best) && newSorted.length > next) {
      best = newSorted[next];
      indexed = next;
      next += 1;
    }

    if (mounted) {
      setState(() {
        _bests = {...?best};
        if (newSorted.isNotEmpty) _maxRate = maxRate;
      });
    }

    return newSorted
        .map((t) => {
              ...t,
              'seeders': truthy(t['seeders']) ? toNum(t['seeders']) : t['seeders'],
              'leechers': truthy(t['leechers']) ? toNum(t['leechers']) : t['leechers'],
            })
        .toList();
  }

  bool _alertedNoMovies = false;
  bool _alertedTryLater = false;

  Future<void> _fetchFresh() async {
    final now = _parseDate(_date);
    final dayStr = now == null ? 'NaN' : '${now.day}'.padLeft(2, '0');
    final monthStr = now == null ? 'NaN' : '${now.month}'.padLeft(2, '0');
    final target = _target; // closure value, like the RN useCallback
    _alertedNoMovies = false;
    _alertedTryLater = false;

    Future<void> getStream(int round) async {
      Future<dynamic> fetchSource() => Http.post(Api.stream, {
            'name': _name,
            'anime': _anime,
            'imdbId': _imdbId,
            'year': _year,
            'season': _season,
            'episode': _episode,
            'id': _id,
            'serieID': _serieID,
            'stream': _stream,
            'address': round,
            'day': dayStr,
            'month': monthStr,
          });

      dynamic response;
      bool ok(dynamic r) => r != null && r.statusCode >= 200 && r.statusCode < 300;
      var count = 1;
      while (!ok(response)) {
        if (count > 5) break;
        response = await fetchSource();
        if (!mounted) return;
        if (count > 1) {
          await Future<void>.delayed(const Duration(seconds: 30));
          if (!mounted) return;
        }
        count++;
      }

      if (!ok(response)) {
        if (!_alertedTryLater) {
          _alertedTryLater = true;
          showUkoAlert(context, 'error', 'try again later');
        }
        return;
      }

      dynamic body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        return;
      }
      if (body is! Map || !mounted) return;
      final error = body['error'];
      if (error != null && error == 'No movies found matching the criteria') {
        if (!_alertedNoMovies) {
          _alertedNoMovies = true;
          showUkoAlert(context, 'error', '$error');
        }
        return;
      }
      if (truthy(body['status'])) {
        final movies = asMapList(body['movies']);
        if (movies.isNotEmpty) {
          final cleaned = _cleanTokens(movies, target);
          if (!mounted) return;
          setState(() => _play = [...?_play, ...cleaned]);
          Gql.mutate(_updatePlayMutation, {
            'type': _type,
            'season': parseIntOr(_season, -1),
            'episode': parseIntOr(_episode, -1),
            'id': parseIntOr(_id, -1),
            'tokens': cleaned.map((v) => {...v, 'portal': round}).toList(),
            'token_expire': jsIsoNow(),
          });
        }
      }
      debugPrint('round ${body['portal']}');
    }

    try {
      await Future.wait([for (var i = 1; i <= 4; i++) getStream(i)]);
    } catch (e) {
      debugPrint('fetchFresh error $e');
    }
  }

  Future<void> _fetchToken() async {
    if (_play != null) return;
    final data = await Gql.query(_fetchPlayQuery, {
      'type': _type,
      'episode': parseIntOr(_episode, -1),
      'season': parseIntOr(_season, -1),
      'id': parseIntOr(_id, -1),
    });
    if (!mounted) return;
    final play = data?['play'];
    final tokens = play is Map && play['tokens'] is List ? asMapList(stripTypename(play['tokens'])) : null;
    if (play is! Map ||
        play['error'] == 'no records found' ||
        play['error'] == 'no token found' ||
        tokens == null ||
        _checkCAM(tokens)) {
      await _fetchFresh();
    } else {
      if (tokens.isNotEmpty) setState(() => _maxRate = toNum(tokens[0]['seeders']));
      final cleaned = _cleanTokens(tokens, _target);
      if (mounted) setState(() => _play = [...cleaned]);
    }
  }

  void _alert(String title, String message) {
    if (!mounted) return;
    showAwesomeAlert(context, title, message);
  }

  Widget _collection(Map<String, dynamic> t, int index, bool connected, {Key? key}) {
    return Collection(
      key: key,
      id: _id,
      index: index,
      token: t['token'],
      quality: t['quality'],
      size: t['size'],
      seeders: t['seeders'],
      maxRate: _maxRate,
      title: t['title'],
      stream: _stream,
      background: _background,
      serieID: _serieID,
      anime: _anime,
      serieName: _name,
      season: _season,
      episode: _episode,
      connected: connected,
      onAlert: _alert,
    );
  }

  @override
  Widget build(BuildContext context) {
    final play = _play;
    return Scaffold(
      backgroundColor: UkoColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: RemoteService.instance,
          builder: (context, _) {
            final connected = RemoteService.instance.connected;
            return ListView(
              children: [
                const Text('COLLECTION', style: TextStyle(color: Colors.white, fontSize: 20)),
                if (_bests != null) ...[
                  const Text('Best Quality', style: TextStyle(color: UkoColors.yellow)),
                  if (play != null && play.isNotEmpty)
                    _collection(_bests!, 0, connected, key: ValueKey('best-${_bests!['token'] ?? '0'}')),
                  const Text('Other Qualities', style: TextStyle(color: UkoColors.yellow)),
                ],
                if (play != null && play.isNotEmpty)
                  for (var i = 0; i < play.length; i++) _collection(play[i], i, connected, key: ValueKey('c-$i'))
                else
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.8,
                    child: const LoadingView(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
