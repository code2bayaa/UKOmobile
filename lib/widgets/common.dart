import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import 'picture.dart';

/// "Loading..." block used all over the RN app
/// (`<ActivityIndicator size="large" color="#ffd800" /><Text>Loading...</Text>`).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading...', this.height});
  final String label;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: UkoColors.yellow),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// The section title row:
/// `<Text className="w-[5%] h-[100%] border-r-[10px] border-[#fff] bg-[#5A5A68]"/> <Text 25px>title</Text>`
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.fontSize = 25, this.barWidthFactor = 0.05});
  final String title;
  final Widget? trailing;
  final double fontSize;
  final double barWidthFactor;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return SizedBox(
      height: trailing == null ? 34 : 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: w * barWidthFactor,
            decoration: const BoxDecoration(
              color: UkoColors.slate,
              border: Border(right: BorderSide(color: Colors.white, width: 10)),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ukoHeading(fontSize: fontSize)),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Yellow-bordered "click tv" button shown next to section headers when the
/// remote is connected.
class ClickTvButton extends StatelessWidget {
  const ClickTvButton({super.key, required this.onPressed, this.label = 'click tv', this.disabled = false});
  final VoidCallback onPressed;
  final String label;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return SizedBox(
      width: w * 0.4,
      height: 40,
      child: Material(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: UkoColors.yellow, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: disabled ? null : onPressed,
          child: Center(
            child: Text(label, style: const TextStyle(color: UkoColors.yellow, fontSize: 17)),
          ),
        ),
      ),
    );
  }
}

/// The poster card rendered by `renderMovie` in movies/page, tv/page,
/// similar, recommendation, discover, platform screens... (and
/// components/home/MovieCard.tsx): 180px poster, one-line title, then
/// star + rating | year with a #808C8C bottom border.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    this.onTap,
    this.width,
    this.imageHeight = 180,
    this.tv = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final double? width;
  final double imageHeight;

  /// TV cards show first_air_date's year.
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final yearSource = tv ? item['first_air_date'] : or([item['release_date'], item['first_air_date']]);
    final year = yearSource is String && yearSource.isNotEmpty ? yearSource.split('-').first : '';
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: Picture(picture: item.posterOrBackdrop),
            ),
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
                  const Icon(Icons.star_border, size: 18, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(item.ratingText, style: const TextStyle(color: UkoColors.yellow, fontSize: 15)),
                  const SizedBox(width: 6),
                  const Text('|', style: TextStyle(color: Colors.white)),
                  const SizedBox(width: 6),
                  Text(year, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal list of [MediaCard]s (FlatList horizontal, item width 45% of
/// the screen, like `ITEM_WIDTH = width * 0.45`).
class MediaRow extends StatelessWidget {
  const MediaRow({super.key, required this.items, required this.onTap, this.tv = false, this.height = 250});
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;
  final bool tv;
  final double height;

  @override
  Widget build(BuildContext context) {
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, i) => Padding(
          padding: EdgeInsets.only(right: itemWidth * 0.011 + 2),
          child: MediaCard(item: items[i], width: itemWidth, tv: tv, onTap: () => onTap(items[i])),
        ),
      ),
    );
  }
}

/// Replacement for react-native-awesome-alerts / Alert.alert.
Future<void> showUkoAlert(BuildContext context, String title, String message, {String confirmText = 'OK'}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: UkoColors.gray900,
      title: Text(title, style: const TextStyle(color: UkoColors.yellow)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(confirmText)),
      ],
    ),
  );
}

/// Non-blocking toast-style alert (the RN screens show an AwesomeAlert and
/// auto-hide it via `removeAlert()` after a timeout).
void showUkoSnack(BuildContext context, String title, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    backgroundColor: UkoColors.gray900,
    duration: const Duration(seconds: 3),
    content: RichText(
      text: TextSpan(children: [
        TextSpan(text: '$title\n', style: const TextStyle(color: UkoColors.yellow, fontWeight: FontWeight.bold)),
        TextSpan(text: message, style: const TextStyle(color: Colors.white)),
      ]),
    ),
  ));
}
