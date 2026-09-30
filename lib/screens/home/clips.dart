// Port of mobile/components/home/clips.jsx (CLIPS).
//
// Like the RN component (which ends in `return false`), this widget renders
// nothing: it only resolves trailers for `data[0].results`, validates the
// YouTube thumbnails, enriches each clip with movie/tv details ("oneRing") and
// reports them through [Clips.addValidation] as `{key, name, movieInfo}` maps.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/http.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';

typedef ClipValidation = void Function(List<Map<String, dynamic>> items);

const String _fetchCombinedQuery = r'''
        query MoviePayload (
            $image: IMAGE_ARGUMENTS!
            $movie: SINGLE_MOVIE_ARGUMENTS!
            $credit: CREDIT_ITEM_ARGUMENTS!
        ) {
            moviePayload(
                image: $image,
                movie: $movie,
                credit: $credit
            ) {
                image {
                    data {
                        id
                        path
                    }
                    meta_data {
                        type
                        season
                        episode
                    }
                    success
                    error
                }
                movie {
                    adult
                    backdrop_path
                    genre_ids
                    genres {
                        id
                        name
                    }
                    id
                    original_language
                    original_title
                    overview
                    popularity
                    poster_path
                    release_date
                    title
                    video
                    runtime
                    revenue
                    budget
                    status
                    origin_country
                    production_companies {
                        id
                        name
                    }
                    tagline
                    vote_average
                    vote_count
                    url {
                        fileName
                    }
                    success
                    error
                    message
                }
                credit {
                    cast {
                        adult
                        gender
                        id
                        known_for_department
                        name
                        original_name
                        popularity
                        profile_path
                        cast_id
                        character
                        credit_id
                        order
                    }
                    crew {
                        adult
                        gender
                        id
                        known_for_department
                        name
                        original_name
                        popularity
                        profile_path
                        credit_id
                        department
                        job
                    }
                    success
                    error
                    message
                }
                success
                error
            }
        }
    ''';

const String _insertTvMutation = r'''
        mutation addTV(
            $single:COLLECT_TV_INPUT
        ) {
            addTV(
                single:$single
            ) {
                success
                message
            }
        }
    ''';

const String _insertMovieMutation = r'''
        mutation AddMovie(
            $adult:Boolean!
            $backdrop_path:String
            $id:Int!
            $original_language:String!
            $original_title:String!
            $overview:String!
            $popularity:Float!
            $poster_path:String
            $release_date:String!
            $title:String!
            $video :Boolean!
            $vote_average:Float!
            $vote_count:Float!
            $belongs_to_collection:COLLECTION_INPUT
            $production_companies:[PRODUCTION_COMPANIES_INPUT]
            $production_countries:[PRODUCTION_COUNTRIES_INPUT]
            $spoken_languages:[SPOKEN_LANGUAGES_INPUT]
            $runtime:Int!
            $genres:[GENRES_IDS_INPUT]
        ) {
            addMovie(
                adult:$adult
                backdrop_path:$backdrop_path
                genres:$genres
                id:$id
                original_language:$original_language
                original_title:$original_title
                overview:$overview
                popularity:$popularity
                poster_path:$poster_path
                release_date:$release_date
                title:$title
                video:$video
                vote_average:$vote_average
                vote_count:$vote_count
                belongs_to_collection:$belongs_to_collection
                production_companies:$production_companies
                production_countries:$production_countries
                runtime:$runtime
                spoken_languages:$spoken_languages
            ) {
                success
                message
            }
        }
    ''';

const String _fetchTrailerQuery = r'''
        query Video (
            $type: String!
            $season: Int!
            $episode: Int!
            $id : ID!
        ){
            video(
                type:$type,
                episode:$episode,
                season:$season,
                id:$id
            ) {
                data {
                    id
                    results {
                        key
                        name
                    }
                }
                success
                error
            }
        }
    ''';

const String _insertTrailerMutation = r'''
        mutation AddVideo(
            $meta_data: VIDEO_META_DATA_INPUT!
            $data: VIDEO_DATA_INPUT!
        ) {
            addVideo(
                meta_data: $meta_data
                data: $data
            ){
                data {
                    id
                    results {
                        iso_639_1
                        iso_3166_1
                        name
                        key
                        site
                        size
                        type
                        official
                        published_at
                        id
                    }
                }
                meta_data {
                    id
                    type
                    season
                    episode
                }
                success
                error
            }
        }
    ''';

const String _fetchVideoQuery = r'''
        query CollectionVideo (
            $type: String!
            $data : COLLECTION_VIDEO_DATA_INPUT!
        ){
            collectionVideo(
                type:$type,
                data:$data
            ) {
                data {
                    id
                    data {
                        key
                        name
                    }
                }
                success
                error
                message
            }
        }
    ''';

const String _insertVideoMutation = r'''
        mutation AddCollectionVideo(
            $meta_data: VIDEO_COLLECTION_META_DATA_INPUT!
            $data: VIDEO_COLLECTION_DATA_INPUT!
        ) {
            addCollectionVideo(
                meta_data: $meta_data
                data: $data
            ){
                success
                error
            }
        }
    ''';

class Clips extends StatefulWidget {
  const Clips({
    super.key,
    required this.stream,
    this.many = false,
    this.season,
    this.episode,
    this.addValidation,
    this.firstClip,
    this.data,
    this.updateClip,
  });

  /// "movie" | "tv"
  final String stream;

  /// true: per-id trailers (trailer screens); false: first valid trailer per
  /// title of a collection (home BLOCKBUSTER / BOX).
  final bool many;

  /// Raw route values (RN strings); null == absent (RN default `false`).
  final String? season;
  final String? episode;
  final ClipValidation? addValidation;
  final ValueChanged<String>? firstClip;

  /// `[{index, results: [{id}, ...], ...}]` — only `data[0].results` is used.
  final List<Map<String, dynamic>>? data;

  /// Kept for parity with the RN props (only used by the commented-out RN list).
  final ValueChanged<String>? updateClip;

  @override
  State<Clips> createState() => _ClipsState();
}

class _ClipsState extends State<Clips> {
  /// Bumped on every (re)run / dispose — replaces the RN AbortController.
  int _gen = 0;
  bool _waitingForKeys = false;

  KeyService get _keys => KeyService.instance;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_onKeys);
    _run();
  }

  @override
  void didUpdateWidget(covariant Clips old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data) ||
        old.many != widget.many ||
        old.stream != widget.stream ||
        old.season != widget.season ||
        old.episode != widget.episode) {
      _run();
    }
  }

  @override
  void dispose() {
    _gen++;
    _keys.removeListener(_onKeys);
    super.dispose();
  }

  // RN re-ran the validation when `safeKeys` changed.
  void _onKeys() {
    if (_waitingForKeys && _keys.movieDb.isNotEmpty) _run();
  }

  bool _alive(int g) => mounted && g == _gen;

  Future<void> _run() async {
    final g = ++_gen;
    try {
      if (widget.many) {
        await _validateTrailer(g);
      } else {
        await _validateVideos(g);
      }
    } catch (e) {
      debugPrint('CLIPS error: $e');
    }
  }

  // ---- helpers -------------------------------------------------------------

  /// `x ? parseInt(x) : -1` for the RN string params.
  static int _optInt(String? v) {
    if (v == null || v.isEmpty) return -1;
    return int.tryParse(v) ?? -1;
  }

  static int? _parseId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse('$id');
  }

  List<Map<String, dynamic>> get _firstResults {
    final data = widget.data;
    if (data == null || data.isEmpty) return <Map<String, dynamic>>[];
    return asMapList(data[0]['results']);
  }

  /// Check that the YouTube thumbnail exists (HEAD request, like RN checkURL).
  static Future<bool> _checkUrl(String url) async {
    try {
      final res = await http.head(Uri.parse(url));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('Error checking URL: $e');
      return false;
    }
  }

  /// Wait for the keys; false (and remember to re-run) when they are missing.
  Future<bool> _keysReady() async {
    await _keys.ready;
    if (_keys.movieDb.isEmpty) {
      _waitingForKeys = true;
      return false;
    }
    _waitingForKeys = false;
    return true;
  }

  // ---- oneRing / movieRing -------------------------------------------------

  Future<Map<String, dynamic>?> _freshDetail(dynamic id) async {
    final json = await Http.getJson('${_keys.movieDb}${widget.stream}/$id?api_key=${_keys.apiKey}');
    if (json is! Map) return null;
    final data = Map<String, dynamic>.from(json);
    if (widget.stream == 'movie') {
      Gql.mutate(_insertMovieMutation, {...data}).then((res) {
        final r = res?['addMovie'];
        if (r is Map && r['success'] != true) debugPrint('Failed to insert movies into MySQL: ${r['message']}');
      });
    } else {
      Gql.mutate(_insertTvMutation, {
        'single': {...data},
      }).then((res) {
        final r = res?['addTV'];
        if (r is Map && r['success'] != true) debugPrint('Failed to insert movies into MySQL: ${r['message']}');
      });
    }
    return {...data};
  }

  Future<Map<String, dynamic>?> _movieRing(Map<String, dynamic>? payload, dynamic id) async {
    if (payload != null && !truthy(payload['runtime'])) {
      // first time
      final movie = await _freshDetail(id);
      if (movie == null) return null;
      return {...payload, ...movie};
    } else if (payload != null && truthy(payload['success'])) {
      return {...payload};
    } else {
      // RN crashed here on a null payload (`payload.success` -> TypeError).
      return _freshDetail(id);
    }
  }

  /// Movie / tv details for the swiper (title, tagline, status, poster, overview).
  Future<Map<String, dynamic>?> _oneRing(dynamic id) async {
    try {
      if (_keys.movieDb.isEmpty) return null;
      // RN always asked moviePayload (movie table) — for tv that returns an
      // unrelated movie with the same numeric id, so tv goes straight to TMDB.
      if (widget.stream == 'tv') return await _movieRing(null, id);
      final idNum = _parseId(id);
      final fetched = await Gql.query(_fetchCombinedQuery, {
        'movie': {'id': idNum},
        'image': {
          'type': widget.stream,
          'episode': _optInt(widget.episode),
          'season': _optInt(widget.season),
          'id': idNum ?? -1,
        },
        'credit': {'id': idNum ?? 0},
      });
      final payload = (fetched?['moviePayload'] as Map?)?['movie'];
      return await _movieRing(
        payload is Map ? Map<String, dynamic>.from(stripTypename(payload) as Map) : null,
        id,
      );
    } catch (e) {
      debugPrint('oneRing error: $e');
      return null;
    }
  }

  // ---- many == false : collection trailers (home) ---------------------------

  Future<void> _validateVideos(int g) async {
    if (widget.data == null) return;
    if (!await _keysReady() || !_alive(g)) return;
    final stream = widget.stream;
    final results = _firstResults;

    Future<List<Map<String, dynamic>>> fetchFresh() async {
      final collection = <Map<String, dynamic>>[];
      for (final r in results) {
        if (!_alive(g)) return collection;
        final id = r['id'];
        final json = await Http.getJson('${_keys.movieDb}$stream/$id/videos?api_key=${_keys.apiKey}');
        final vids = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
        if (vids.isNotEmpty) {
          collection.add({
            'id': id,
            'data': [
              for (final v in vids) {'key': v['key'], 'name': v['name']},
            ],
          });
        }
      }
      if (!_alive(g)) return collection; // aborted: don't cache a partial set
      Gql.mutate(_insertVideoMutation, {
        'meta_data': {'type': stream},
        'data': {'videos': collection},
      }).then((res) {
        final r = res?['addCollectionVideo'];
        if (r is Map && r['success'] != true) debugPrint('Failed to insert trailer into MySQL: ${r['error']}');
      });
      return collection;
    }

    final fetched = await Gql.query(_fetchVideoQuery, {
      'type': stream,
      'data': {
        'data': [
          for (final r in results) {'id': r['id']},
        ],
      },
    });
    if (!_alive(g)) return;

    dynamic collectionTrailerData;
    final cv = fetched?['collectionVideo'];
    if (cv is Map) {
      if (cv['error'] == 'no records found') {
        collectionTrailerData = await fetchFresh();
      } else {
        collectionTrailerData = stripTypename(cv['data']);
      }
    } else {
      collectionTrailerData = await fetchFresh();
    }

    final additions = <Map<String, dynamic>>[];
    for (final collection in asMapList(collectionTrailerData)) {
      for (final v in asMapList(collection['data'])) {
        if (!_alive(g)) return;
        final key = '${v['key']}';
        if (await _checkUrl('https://img.youtube.com/vi/$key/maxresdefault.jpg')) {
          final movieInfo = await _oneRing(collection['id']);
          additions.add({'key': key, 'name': v['name'], 'movieInfo': movieInfo, 'id': collection['id'], 'stream': widget.stream});
          break; // only need the first valid for non-many
        }
      }
    }

    if (!_alive(g)) return;
    if (additions.isNotEmpty) {
      widget.firstClip?.call('${additions[0]['key']}');
      widget.addValidation?.call([...additions]);
    }
  }

  // ---- many == true : trailers of one title (trailer screens) ---------------

  Future<void> _validateTrailer(int g) async {
    if (widget.data == null) return;
    if (!await _keysReady() || !_alive(g)) return;
    final stream = widget.stream;
    final season = widget.season;
    final episode = widget.episode;

    for (final r in _firstResults) {
      if (!_alive(g)) return;
      final id = r['id'];
      final idNum = _parseId(id) ?? 0;

      Future<dynamic> fetchFresh() async {
        final url = '${_keys.movieDb}$stream/$id'
            '${(season != null && season.isNotEmpty) ? '/season/$season' : ''}'
            '${(episode != null && episode.isNotEmpty) ? '/episode/$episode' : ''}'
            '/videos?api_key=${_keys.apiKey}';
        final getVideoData = await Http.getJson(url);
        Gql.mutate(_insertTrailerMutation, {
          'meta_data': {
            'type': stream,
            'episode': _optInt(episode),
            'season': _optInt(season),
            'id': idNum,
          },
          'data': getVideoData is Map ? {...Map<String, dynamic>.from(getVideoData)} : <String, dynamic>{},
        }).then((res) {
          final a = res?['addVideo'];
          if (a is Map && a['success'] != true) debugPrint('Failed to insert trailer into MySQL: ${a['error']}');
        });
        return getVideoData;
      }

      final fetched = await Gql.query(_fetchTrailerQuery, {
        'type': stream,
        'episode': _optInt(episode),
        'season': _optInt(season),
        'id': idNum,
      });
      if (!_alive(g)) return;

      final video = fetched?['video'];
      if (video is Map) {
        // A cached row comes back with success - only go to TMDB when there is none.
        final cached = stripTypename(video['data']);
        final hasCached = video['success'] == true && cached is Map && asMapList(cached['results']).isNotEmpty;
        final trailerData = hasCached ? cached : await fetchFresh();
        if (!_alive(g)) return;
        final list = trailerData is Map ? asMapList(trailerData['results']) : <Map<String, dynamic>>[];
        // The trailer screen already knows the title - no movie lookup here.
        final additions = [
          for (final v in list)
            if (v['key'] != null && (v['site'] == null || v['site'] == 'YouTube'))
              {'key': '${v['key']}', 'name': v['name']},
        ];
        if (additions.isNotEmpty) {
          widget.firstClip?.call('${additions[0]['key']}');
          widget.addValidation?.call([...additions]);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
