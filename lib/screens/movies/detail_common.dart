// Pieces shared by movies/id.dart and tv/id.dart (the two RN screens,
// app/(tabs)/movies/id.tsx and app/(tabs)/tv/id.tsx, are ~80% identical).
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/media.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/prefs.dart';
import '../../services/profile.dart';
import '../../widgets/picture.dart';

/// FETCH_GENRE_QUERY (verbatim).
const String kGenreQuery = r'''
      query Genre {
          genre {
              success
              date
              data {
                  id
                  name
                  mode
              }
          }
      }
  ''';

/// FETCH_COMINED_QUERY (verbatim, identical in movies/id.tsx and tv/id.tsx).
const String kMoviePayloadQuery = r'''
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

/// mutateInsertImage document (verbatim).
const String kAddImageMutation = r'''
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

/// Stores a TMDB /movie/{id} response (the movie detail cache). The RN port
/// declared TV fields ($name/$first_air_date required, $id as ID), so every
/// call was rejected and the movie page never cached. Only $id is required -
/// TMDB leaves any of the others null.
const String kAddMovieMutation = r'''
        mutation AddMovie(
            $adult:Boolean
            $backdrop_path:String
            $id:Int!
            $imdb_id:String
            $original_language:String
            $original_title:String
            $overview:String
            $popularity:Float
            $poster_path:String
            $release_date:String
            $title:String
            $video:Boolean
            $vote_average:Float
            $vote_count:Float
            $budget:Float
            $revenue:Float
            $homepage:String
            $status:String
            $tagline:String
            $origin_country:[String]
            $belongs_to_collection:COLLECTION_INPUT
            $production_companies:[PRODUCTION_COMPANIES_INPUT]
            $production_countries:[PRODUCTION_COUNTRIES_INPUT]
            $spoken_languages:[SPOKEN_LANGUAGES_INPUT]
            $runtime:Int
            $genres:[GENRES_IDS_INPUT]
        ) {
            addMovie(
                adult:$adult
                backdrop_path:$backdrop_path
                genres:$genres
                id:$id
                imdb_id:$imdb_id
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
                budget:$budget
                revenue:$revenue
                homepage:$homepage
                status:$status
                tagline:$tagline
                origin_country:$origin_country
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

/// INSERT_CREDITS_MUTATION. season/episode are -1 for a title's own credits.
const String kAddCreditsMutation = r'''
        mutation AddCredits(
            $id:Int
            $season:Int
            $episode:Int
            $cast:[CAST_INPUT]
            $crew:[CREW_INPUT]
            $chunking:Boolean!
            $chunking_index:Int!
        ) {
            addCredits(
                id:$id
                season:$season
                episode:$episode
                cast:$cast
                crew:$crew
                chunking:$chunking
                chunking_index:$chunking_index
            ) {
                success
                message
            }
        }
    ''';

/// imageRing's freshFetch path selection: tallest backdrop, replaced by the
/// tallest poster if taller, replaced by the tallest logo if taller still.
String pickBestImagePath(Map<String, dynamic> json) {
  num value = 0;
  var path = '';
  (num, String)? tallest(dynamic list) {
    final l = asMapList(list);
    if (l.isEmpty) return null;
    num maxH = toNum(l.first['height']);
    for (final e in l) {
      final h = toNum(e['height']);
      if (h > maxH) maxH = h;
    }
    final hit = l.firstWhere((e) => toNum(e['height']) == maxH, orElse: () => const {});
    return (maxH, '${hit['file_path'] ?? ''}');
  }

  final b = tallest(json['backdrops']);
  if (b != null) {
    value = b.$1;
    path = b.$2;
  }
  final p = tallest(json['posters']);
  if (p != null && p.$1 > value) {
    path = p.$2;
    value = p.$1;
  }
  final l = tallest(json['logos']);
  if (l != null && l.$1 > value) {
    path = l.$2;
  }
  return path;
}

/// Fetches TMDB images, stores the chosen path via addImage and returns it.
Future<String> freshImagePath({
  required String movieDb,
  required String apiKey,
  required MediaKind kind,
  required String idStr,
  required int? idInt,
}) async {
  final json = await Http.getJson('$movieDb${kind.api}/$idStr/images?api_key=$apiKey');
  final data = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
  final path = pickBestImagePath(data);
  Gql.mutate(kAddImageMutation, {
    'meta_data': {
      // RN hard-coded "movie" here in both screens while querying "tv" — see report.
      'type': kind.api,
      'season': -1,
      'episode': -1,
      'id': idInt ?? -1,
    },
    'data': {'id': data['id'], 'path': path},
  });
  return path;
}

/// TMDB crew entry reduced to the fields CREW_INPUT declares.
Map<String, dynamic> crewInput(Map<String, dynamic> c) => {
      'adult': c['adult'],
      'gender': c['gender'],
      'id': c['id'],
      'known_for_department': c['known_for_department'],
      'name': c['name'],
      'original_name': c['original_name'],
      'popularity': c['popularity'],
      'profile_path': c['profile_path'],
      'credit_id': c['credit_id'],
      'department': c['department'],
      'job': c['job'],
    };

/// creditRing's addCredits calls (chunks of 100) for a title's own credits
/// (season/episode -1). Crew is stored too - without it a cache hit had none.
void insertCredits(List<Map<String, dynamic>> cast, int? idInt, {List<Map<String, dynamic>> crew = const []}) {
  final id = idInt ?? 0;
  void store(String group, List<Map<String, dynamic>> people) {
    if (people.isEmpty) return;
    final chunked = people.length > 100;
    for (var i = 0, c = 0; i < people.length; i += 100, c++) {
      Gql.mutate(kAddCreditsMutation, {
        group: people.sublist(i, i + 100 > people.length ? people.length : i + 100),
        'id': id,
        'season': -1,
        'episode': -1,
        'chunking': chunked,
        'chunking_index': c,
      });
    }
  }

  store('cast', cast);
  store('crew', crew.map(crewInput).toList());
}

/// POST API_URL {email} -> {status, user}.
Future<Map<String, dynamic>?> fetchApiUser() async {
  final res = await Http.postJson(Api.apiUrl, {'email': await Prefs.user});
  return res is Map ? Map<String, dynamic>.from(res) : null;
}

/// checkFeedback: true when the title is already in the user's playlist.
Future<bool> isInPlaylist(dynamic id, MediaKind kind) async {
  final u = await fetchApiUser();
  if (u == null || !truthy(u['status'])) return false;
  final res = await Http.postJson(Api.playlistSelect, {'id': id, 'user': u['user'], 'type': kind.api});
  return res is Map && truthy(res['status']);
}

/// addToPlayList: returns the insert endpoint's `status` (null on failure).
Future<bool?> insertIntoPlaylist(dynamic id, MediaKind kind) async {
  final u = await fetchApiUser();
  final res = await Http.postJson(Api.insertPlaylist, {'id': id, 'user': u?['user'], 'type': kind.api});
  if (res is! Map) return null;
  debugPrint('response: ${res['response']} ${res['status']} status ${res['error']} ${res['message']} message');
  return truthy(res['status']);
}

/// Rounded outlined / filled button used in the detail headers
/// (`w-[48%] min-h-[40px] border-white border-2 rounded-full`).
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.filled = false, this.icon});
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : Colors.white;
    return Material(
      color: filled ? UkoColors.yellow : Colors.transparent,
      shape: StadiumBorder(side: filled ? BorderSide.none : const BorderSide(color: Colors.white, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 30, color: fg),
                Text(label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: filled ? FontWeight.bold : FontWeight.normal,
                      decoration: TextDecoration.underline,
                      decorationColor: fg,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// renderCredits: 180px profile picture, name, star rating | character.
class CastCard extends StatelessWidget {
  const CastCard({super.key, required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = or([item['name'], item['original_name'], item['name']]);
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: Picture(picture: truthy(item['profile_path']) ? '${item['profile_path']}' : ''),
          ),
          SizedBox(
            height: 25,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${name ?? ''}',
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
                const SizedBox(width: 6),
                const Text('|', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${item['character'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal cast FlatList (item width = 45% of the screen).
class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.cast, required this.onTap});
  final List<Map<String, dynamic>> cast;
  final void Function(Map<String, dynamic> item) onTap;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.45;
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cast.length,
        itemBuilder: (context, i) => Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.005 + 1),
          child: SizedBox(width: w, child: CastCard(item: cast[i], onTap: () => onTap(cast[i]))),
        ),
      ),
    );
  }
}

/// `movie.genres ? movie.genres.find(({id}) => id === 16) : movie.genre_ids ? movie.genre_ids.includes(16) : false`
/// (RN passed the found genre *object* as the param; the port passes a bool).
bool isAnime(Map<String, dynamic> m) {
  if (m['genres'] is List) return asMapList(m['genres']).any((g) => toNum(g['id']) == 16);
  if (m['genre_ids'] is List) return (m['genre_ids'] as List).any((g) => toNum(g) == 16);
  return false;
}

/// Blurred backdrop strip behind the detail header (ImageBackground blurRadius 3).
class BlurredBackdrop extends StatelessWidget {
  const BlurredBackdrop({super.key, required this.path, this.height = 200});
  final String? path;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!truthy(path)) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Picture(picture: path, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// runLocale(): true when the device is in Africa, Australia or Brazil. The device half of the
/// play gate only - screens should use playGate() (services/profile.dart), which also checks the
/// signed-in account's phone number (movies PRD #7).
Future<bool> playAllowedHere() => deviceInPlayRegion();
