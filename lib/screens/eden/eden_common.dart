// Pieces shared by the Eden detail screens (eden/movie.dart, eden/serie.dart) -
// ports of web-app/src/components/eden/movie.jsx and serie.jsx. Eden titles live in
// the movies table with data.eden = studio id; their images are Eden bucket keys.
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/no_credits.dart';

/// edenMoviePayload - the database service's Eden twin of moviePayload.
const String kEdenMoviePayloadQuery = r'''
  query EdenMoviePayload(
    $image: EDEN_IMAGE_ARGUMENTS!
    $movie: EDEN_SINGLE_MOVIE_ARGUMENTS!
    $credit: EDEN_CREDIT_ITEM_ARGUMENTS!
  ) {
    edenMoviePayload(image: $image, movie: $movie, credit: $credit) {
      image { data { id path logo } success error }
      movie {
        adult backdrop_path genre_ids genres { id name } id original_language original_title
        overview poster_path release_date title runtime status origin_country
        production_companies { id name } tagline vote_average vote_count
        url { fileName } success error message
      }
      credit {
        cast { id name original_name profile_path character known_for_department }
        crew { id name original_name profile_path department job }
        success error message
      }
      success
      error
    }
  }
''';

/// edenTvPayload - series, its seasons (Eden season rows) and its cast.
const String kEdenTvPayloadQuery = r'''
  query EdenTvPayload(
    $image: EDEN_IMAGE_TV_ARGUMENTS!
    $tv: EDEN_SINGLE_TV_ARGUMENTS!
    $credit: EDEN_CREDIT_ITEM_TV_ARGUMENTS!
  ) {
    edenTvPayload(image: $image, tv: $tv, credit: $credit) {
      image { data { id path logo } success error }
      tv {
        adult backdrop_path genre_ids genres { id name } id original_language original_name name
        overview poster_path first_air_date status origin_country tagline vote_average
        seasons { id name overview season_number episode_count poster_path }
        success error message
      }
      credit {
        cast { id name original_name profile_path character known_for_department }
        crew { id name original_name profile_path department job }
        success error message
      }
      success
      error
    }
  }
''';

/// POST /database/eden/episodes {id} - the series' episodes, season then episode order.
Future<List<Map<String, dynamic>>> fetchEdenEpisodes(dynamic seriesId) async {
  final res = await Http.postJson(Api.edenEpisodes, {'id': seriesId});
  return res is Map ? asMapList(res['data']) : const [];
}

/// The rent / credit gate every play button runs before the speed player
/// (movies/id.dart _goToSpeed): a paid rental, else more than 49 credits.
Future<bool> canPlayWithCredits(BuildContext context, dynamic id) async {
  var hasCredits = false;
  var hasPaid = false;
  final email = await Prefs.user;
  // a guest has no credits to check - ask them to sign up (widgets/no_credits.dart)
  if (email == null || email.isEmpty) {
    if (context.mounted) await promptGuestSignUp(context);
    return false;
  }
  final paid = await Http.postJson(Api.userPaid, {'id': id, 'email': email});
  if (!context.mounted) return false;
  if (paid is Map) {
    if (truthy(paid['status'])) {
      hasPaid = true;
      showUkoSnack(context, 'success', 'rent paid ${paid['message']}');
    } else if (paid['message'] == 'day for movie credits ended') {
      showUkoSnack(context, 'error', 'rent elapsed ${paid['message']}');
    }
  }
  final credits =
      await Http.postJson(Api.checkUserCredits, {'username': email});
  if (!context.mounted) return false;
  if (credits is Map && toNum(credits['sum']) > 49) hasCredits = true;
  if (!hasCredits && !hasPaid) {
    showUkoSnack(context, 'error', 'NO CREDITS add more credits');
    return false;
  }
  return true;
}

/// Backdrop with the page's dark gradient over it, as the web's
/// `linear-gradient(105deg, #0d0d0d, rgba(0,0,0,0.75), #000, ...)` background.
class EdenBackdrop extends StatelessWidget {
  const EdenBackdrop({super.key, required this.path, this.height = 240});
  final String? path;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (truthy(path)) EdenImage(path: path, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x660D0D0D), Color(0xCC000000), Colors.black],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "EDEN" chip, as the web's mini series rows.
class EdenTag extends StatelessWidget {
  const EdenTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: UkoColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('EDEN',
          style: TextStyle(
              color: UkoColors.divider, fontSize: 11, letterSpacing: 1.2)),
    );
  }
}

/// `Genre || Genre` line in yellow.
class GenreLine extends StatelessWidget {
  const GenreLine({super.key, required this.genres});
  final List<Map<String, dynamic>> genres;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) return const SizedBox.shrink();
    return Text(
      genres
          .map((g) => '${g['name'] ?? ''}')
          .where((n) => n.isNotEmpty)
          .join(' || '),
      textAlign: TextAlign.center,
      style: const TextStyle(color: UkoColors.yellow, fontSize: 12),
    );
  }
}

/// Cast & crew from Eden's stars/crew tables. A card opens the Eden person screen.
class EdenCastRow extends StatelessWidget {
  const EdenCastRow({super.key, required this.people});
  final List<Map<String, dynamic>> people;

  @override
  Widget build(BuildContext context) {
    final named = people
        .where((p) => truthy(p['name']) || truthy(p['original_name']))
        .toList();
    if (named.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No cast listed yet.',
            style: TextStyle(color: UkoColors.divider)),
      );
    }
    final w = MediaQuery.of(context).size.width * 0.34;
    return SizedBox(
      height: w * 1.5 + 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: named.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = named[i];
          final role =
              or([p['character'], p['job'], p['known_for_department']]);
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Nav.push(context, Routes.edenPeopleId,
                {'id': p['id'], 'person_id': p['person_id'], 'eden': true}),
            child: SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EdenImage(
                    path: truthy(p['profile_path'])
                        ? '${p['profile_path']}'
                        : null,
                    width: w,
                    height: w * 1.5,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 4),
                  Text('${or([p['name'], p['original_name']]) ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white)),
                  if (truthy(role))
                    Text('$role',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: UkoColors.divider, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
