// Port of mobile/app/(tabs)/people/id.tsx (PERSON).
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../services/remote.dart';
import '../../widgets/common.dart';
import '../../widgets/picture.dart';

const _fetchImageQuery = r'''
      query Image (
          $type: String!
          $season: Int!
          $episode: Int!
          $id : ID!
      ){
          image(
              type:$type,
              episode:$episode,
              season:$season,
              id:$id
          ) {
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
      }
''';

const _insertImageMutation = r'''
      mutation AddImage(
          $meta_data: META_DATA_INPUT!
          $data: DATA_INPUT!
      ) {
          addImage(
              meta_data: $meta_data
              data: $data
          ){
              data {
                  id
                  path
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

const _fetchPersonQuery = r'''
      query Person (
          $id: ID!
      ){
          person(
              id:$id
          ) {
              adult
              also_known_as
              biography
              birthday
              deathday
              gender
              homepage
              id
              imdb_id
              known_for_department
              name
              place_of_birth
              popularity
              profile_path
              success
              message
              error
          }
      }
''';

const _insertPersonMutation = r'''
      mutation AddPersonID(
          $single:PERSON_ID
      ) {
          addPersonID(
              single:$single
          ) {
              success
              message
          }
      }
''';

const _fetchPlayedQuery = r'''
        query Played(
            $id:Int!
            $type:String!
            $hashedKey:String!
        ){
            played(
                id:$id
                type:$type
                hashedKey:$hashedKey
            ){

                cast {
                    adult
                    backdrop_path
                    genre_ids
                    id
                    original_language
                    original_title
                    overview
                    popularity
                    poster_path
                    release_date
                    title
                    video
                    vote_average
                    vote_count
                    character
                    credit_id
                    order
                }
                crew {
                    adult
                    backdrop_path
                    genre_ids
                    id
                    original_language
                    original_title
                    overview
                    popularity
                    poster_path
                    release_date
                    title
                    video
                    vote_average
                    vote_count
                    character
                    credit_id
                    order
                }
                success
                error
                message
            }
        }
''';

const _insertPlayedMutation = r'''
        mutation AddPlayed(
            $id:Int!
            $cast:[ADD_CAST_PLAYED_RESULTS_INPUT]
            $crew:[ADD_CREW_PLAYED_RESULTS_INPUT]
            $hashedKey:String!
        ){
            addPlayed(
                id:$id
                cast:$cast
                crew:$crew
                hashedKey:$hashedKey
            ){
                success
                message
                error
            }
        }
''';

const _insertPlayedTvMutation = r'''
        mutation AddPlayedTV(
            $id:ID!
            $cast:[ADD_CAST_PLAYED_TV_RESULTS_INPUT]
            $crew:[ADD_CREW_PLAYED_TV_RESULTS_INPUT]
            $hashedKey:String!
        ){
            addPlayedTV(
                id:$id
                cast:$cast
                crew:$crew
                hashedKey:$hashedKey
            ){
                success
                message
                error
            }
        }
''';

class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Map<String, dynamic>? _person;
  Map<String, dynamic>? _movies;
  Map<String, dynamic>? _series;
  String? _images;
  bool _following = false;

  /// RN `id` from useLocalSearchParams (a string; 'undefined' when missing,
  /// which is what the RN hash strings would contain).
  String get _id => P.str(widget.params, 'id') ?? 'undefined';
  int get _idInt => int.tryParse(_id) ?? -1;

  /// Eden studio people have their own screen at /eden/people/id (read from the
  /// database, never TMDB); a link that still lands here with `eden` is sent on.
  bool get _eden => P.boolOf(widget.params, 'eden');

  @override
  void initState() {
    super.initState();
    if (_eden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Nav.replace(context, Routes.edenPeopleId, widget.params);
      });
      return;
    }
    _graphImages();
    _fetchPerson();
    _fetchMovies();
    _fetchTv();
  }

  Future<void> _graphImages() async {
    Future<String> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final json = await Http.getJson('${k.movieDb}person/$_id/images?api_key=${k.apiKey}');
      var path = '';
      final profiles = json is Map ? asMapList(json['profiles']) : <Map<String, dynamic>>[];
      if (profiles.isNotEmpty) {
        final value = profiles.map((p) => toNum(p['height'])).reduce(math.max);
        final key = profiles.indexWhere((p) => toNum(p['height']) == value);
        if (key > -1) path = '${profiles[key]['file_path'] ?? ''}';
      }
      Gql.mutate(_insertImageMutation, {
        'meta_data': {'type': 'person', 'season': -1, 'episode': -1, 'id': _idInt},
        'data': {'id': json is Map ? json['id'] : null, 'path': path},
      });
      return path;
    }

    final data = await Gql.query(_fetchImageQuery, {'type': 'person', 'episode': -1, 'season': -1, 'id': _idInt});
    final image = data?['image'];
    String? path;
    if (image is Map && image['success'] == true) {
      final d = image['data'];
      path = d is Map ? d['path']?.toString() : null;
    } else {
      path = await freshFetch();
    }
    if (mounted) setState(() => _images = path);
  }

  Future<void> _fetchPerson() async {
    Future<Map<String, dynamic>> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final json = await Http.getJson('${k.movieDb}person/$_id?api_key=${k.apiKey}');
      final data = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      Gql.mutate(_insertPersonMutation, {'single': data});
      return data;
    }

    final data = await Gql.query(_fetchPersonQuery, {'id': _id});
    final person = data?['person'];
    Map<String, dynamic> result;
    if (person is Map && !truthy(person['biography'])) {
      // first check person
      result = await freshFetch();
    } else if (person is Map && truthy(person['success'])) {
      result = Map<String, dynamic>.from(person);
    } else {
      result = await freshFetch();
    }
    if (!mounted) return;
    setState(() => _person = result);
    if (result['id'] != null) _checkFeedback(result['id']);
  }

  /// /user/authentication/android is POST-only (a GET 404s, which read as "Sign in to follow" even
  /// when signed in). The app token names the viewer; the server writes its email over the body's.
  Future<dynamic> _signedIn() => Http.postJson(Api.apiUrl, const <String, dynamic>{});

  /// RN `checkFeedback` effect (runs whenever `person` changes).
  Future<void> _checkFeedback(dynamic id) async {
    final auth = await _signedIn();
    if (auth is! Map || !truthy(auth['status'])) return;
    final res = await Http.postJson(Api.followersSelect, {'id': id, 'user': auth['user']});
    if (res is Map && truthy(res['status']) && mounted) setState(() => _following = true);
  }

  Future<void> _fetchMovies() => _fetchPlayed(tv: false);
  Future<void> _fetchTv() => _fetchPlayed(tv: true);

  /// RN `fetchMovies` / `fetchTV`.
  Future<void> _fetchPlayed({required bool tv}) async {
    final type = tv ? 'tv' : 'movie';
    final hashedKey = sha256Hex('$_id$type');

    Future<Map<String, dynamic>> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final json = await Http.getJson('${k.movieDb}person/$_id/${tv ? 'tv_credits' : 'movie_credits'}?api_key=${k.apiKey}');
      final data = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      Gql.mutate(tv ? _insertPlayedTvMutation : _insertPlayedMutation, {
        ...data,
        'type': type,
        'hashedKey': hashedKey,
      });
      return data;
    }

    final data = await Gql.query(_fetchPlayedQuery, {'type': type, 'id': _idInt, 'hashedKey': hashedKey});
    final played = data?['played'];
    final result = played is Map && truthy(played['success']) ? Map<String, dynamic>.from(played) : await freshFetch();
    if (!mounted) return;
    setState(() {
      if (tv) {
        _series = result;
      } else {
        _movies = result;
      }
    });
  }

  Future<void> _addToFollowers() async {
    final person = _person;
    if (person == null) return;
    final auth = await _signedIn();
    if (!mounted) return;
    if (auth is Map && truthy(auth['status'])) {
      final res = await Http.postJson(Api.followers, {'id': person['id'], 'user': auth['user']});
      if (!mounted) return;
      if (res is Map && truthy(res['status'])) {
        showUkoSnack(context, 'success', 'Added to following');
      } else {
        showUkoSnack(context, 'Oops...', 'Already following');
      }
      setState(() => _following = true);
    } else {
      showUkoSnack(context, 'Oops...', 'Sign in to follow ${person['name'] ?? ''}');
    }
  }

  void _open(Map<String, dynamic> item, String type) {
    final id = item.idInt;
    final isTv = type == 'tv';
    Nav.push(context, isTv ? Routes.tvId : Routes.moviesId, {'id': id});
    RemoteService.instance.route(isTv ? TvPaths.tvId : TvPaths.moviesId, {'id': id});
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    final movies = _movies;
    final series = _series;
    if (person == null || movies == null || series == null) {
      return const LoadingView();
    }
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      children: [
        _header(person),
        const Text('TV', style: TextStyle(color: Colors.white)),
        _subTitle('PLAYED AS CAST'),
        _creditRow(asMapList(series['cast']), 'cast', 'tv'),
        _subTitle('PLAYED AS CREW'),
        _creditRow(asMapList(series['crew']), 'crew', 'tv'),
        const Text('MOVIES', style: TextStyle(color: Colors.white)),
        _subTitle('PLAYED AS CAST'),
        _creditRow(asMapList(movies['cast']), 'cast', 'movies'),
        _subTitle('PLAYED AS CREW'),
        _creditRow(asMapList(movies['crew']), 'crew', 'movies'),
      ],
    );
  }

  Widget _subTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
      );

  Widget _header(Map<String, dynamic> person) {
    final w = MediaQuery.of(context).size.width;
    const white = TextStyle(color: Colors.white);
    final aka = person['also_known_as'];
    final akaText = aka is List ? aka.map((e) => '$e').join(' || ') : '';
    final bg = _images != null && _images!.isNotEmpty ? '${KeyService.instance.imgPoster}$_images' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          if (bg != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Image.network(bg, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox()),
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 24),
                child: SizedBox(
                  width: w * 0.4,
                  height: 200,
                  child: Picture(picture: person['profile_path']?.toString(), fit: BoxFit.contain),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Text('${person['name'] ?? ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Text(akaText, style: white),
              Text('${person['birthday'] ?? ''} || ${person['deathday'] ?? ''}', style: white),
              Text(person['gender'] == 2 ? 'male' : person['gender'] == 1 ? 'female' : '', style: white),
              Text('${person['known_for_department'] ?? ''}', style: white),
              Text('${person['place_of_birth'] ?? ''}', style: white),
              Text('${person['biography'] ?? ''}', style: white),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: Material(
                  color: _following ? Colors.black : UkoColors.yellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: _following ? const BorderSide(color: UkoColors.yellow, width: 2) : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _addToFollowers,
                    child: Center(
                      child: Text(
                        _following ? 'following' : 'follow',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                          color: _following ? UkoColors.yellow : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _creditRow(List<Map<String, dynamic>> items, String c, String type) {
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return Padding(
            key: ValueKey('$type-$c-item-$i'),
            padding: EdgeInsets.only(right: itemWidth * 0.011 + 2),
            child: SizedBox(
              width: itemWidth,
              child: InkWell(
                onTap: () => _open(item, type),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 180, width: double.infinity, child: Picture(picture: item.posterOrBackdrop)),
                    SizedBox(
                      height: 25,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(item.displayTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: UkoColors.divider, width: 2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_border, size: 18, color: UkoColors.yellow),
                          const SizedBox(width: 4),
                          Text(item.ratingText, style: const TextStyle(color: UkoColors.yellow, fontSize: 15)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('${(c == 'cast' ? item['character'] : item['job']) ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
