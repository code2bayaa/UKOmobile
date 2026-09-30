// Shared pieces of the ports of mobile/app/(tabs)/tv/season.tsx and
// mobile/app/(tabs)/tv/episode.tsx (both files duplicate these verbatim).
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import '../../widgets/picture.dart';

/// `FETCH_IMAGE_QUERY` (identical in season.tsx / episode.tsx).
const String kFetchImageQuery = r'''
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

/// `mutateInsertImage` document.
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

/// `INSERT_CREDITS_MUTATION`. A season's credits are stored under (series id,
/// season, -1), an episode's under (series id, season, episode).
const String kAddCreditsMutation = r'''
        mutation AddCredits(
            $id:Int!
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

/// JS `x ? parseInt(String(x)) : fallback`.
int parseIntOr(dynamic v, int fallback) {
  if (!truthy(v)) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final m = RegExp(r'^\s*([+-]?\d+)').firstMatch(v.toString());
  return m == null ? fallback : int.parse(m.group(1)!);
}

/// `chunkArray(array, size)`
List<List<T>> chunkList<T>(List<T> list, int size) {
  final out = <List<T>>[];
  for (var i = 0; i < list.length; i += size) {
    out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
  }
  return out;
}

/// Picks the file_path of the tallest image in [list] (JS
/// `Math.max(...list.map(h))` + `findIndex(height === max)`), or null.
({num height, String? path})? tallestImage(dynamic list) {
  final items = asMapList(list);
  if (items.isEmpty) return null;
  num max = toNum(items.first['height']);
  for (final i in items) {
    final h = toNum(i['height']);
    if (h > max) max = h;
  }
  final hit = items.firstWhere((i) => toNum(i['height']) == max, orElse: () => const {});
  return (height: max, path: hit['file_path'] as String?);
}

/// The `renderCredits` card (same in season.tsx and episode.tsx): 180px
/// profile picture, name, then star + rating | character over a #808C8C
/// bottom border.
class CreditCard extends StatelessWidget {
  const CreditCard({super.key, required this.item, required this.onTap, required this.width});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final name = or([item['name'], item['original_name'], item['name']]);
    return SizedBox(
      width: width,
      child: InkWell(
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
                child: Text(name == null ? '' : '$name',
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
                    child: Text(item['character'] == null ? '' : '${item['character']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal FlatList of [CreditCard]s (`ITEM_WIDTH = width * 0.45`).
class CreditRow extends StatelessWidget {
  const CreditRow({super.key, required this.items, required this.onTap});
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;

  @override
  Widget build(BuildContext context) {
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 8),
        itemCount: items.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: CreditCard(item: items[i], width: itemWidth, onTap: () => onTap(items[i])),
        ),
      ),
    );
  }
}

/// `w-[48%] min-h-[40px] border-white border-2 rounded-full` pressable with
/// underlined text; [filled] = the yellow "play" variant.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.filled = false, this.icon});
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 8; // px-1
    final fg = filled ? Colors.black : Colors.white;
    return SizedBox(
      width: w * 0.49,
      child: Material(
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
                  if (icon != null) ...[Icon(icon, size: 30, color: fg), const SizedBox(width: 4)],
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
      ),
    );
  }
}

/// The ListHeaderComponent shell: blurred 200px background image
/// (`ImageBackground blurRadius={3}` absolutely positioned at the top), the
/// poster (`h-[200px] object-contain w-[40%] ml-10 mt-6`), then [details]
/// and the wrapped [buttons] row.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.background,
    required this.poster,
    required this.details,
    required this.buttons,
  });

  /// TMDB path or absolute url for the blurred background (null = none).
  final String? background;
  final String? poster;
  final List<Widget> details;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final bgUrl = Picture.resolve(background);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          if (bgUrl != null && bgUrl.startsWith('http'))
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Image.network(bgUrl,
                      fit: BoxFit.cover, errorBuilder: (context, e, st) => const SizedBox.shrink()),
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 40, top: 24),
                  child: SizedBox(
                    width: w * 0.4,
                    height: 200,
                    child: Picture(picture: poster, fit: BoxFit.contain),
                  ),
                ),
              ),
              ...details,
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 4,
                  children: buttons,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Overview block: `serie.overview || "waiting for more content"`.
class OverviewText extends StatelessWidget {
  const OverviewText(this.overview, {super.key});
  final dynamic overview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12), // p-2 m-1
        child: Text(
          truthy(overview) ? '$overview' : 'waiting for more content',
          textAlign: TextAlign.justify,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
