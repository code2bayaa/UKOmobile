import 'package:flutter/material.dart';

import '../services/keys.dart';

/// Port of components/home/picture.tsx.
/// - [asset]: local asset path (RN `url={require(...)}`)
/// - [picture]: TMDB path (prefixed with safeKeys.IMG_POSTER) or absolute url
/// - neither: assets/images/logo3.png; load error: assets/images/alt.webp
class Picture extends StatelessWidget {
  const Picture({
    super.key,
    this.picture,
    this.asset,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.alignment = Alignment.center,
  });

  final String? picture;
  final String? asset;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Alignment alignment;

  static String? resolve(String? picture) {
    if (picture == null || picture.isEmpty || picture == 'null' || picture == 'undefined') return null;
    if (RegExp(r'^(https?:)?//', caseSensitive: false).hasMatch(picture)) return picture;
    return KeyService.instance.imgPoster + picture;
  }

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (asset != null) {
      img = Image.asset(asset!, fit: fit, width: width, height: height, alignment: alignment);
    } else {
      img = ListenableBuilder(
        listenable: KeyService.instance,
        builder: (context, _) {
          final url = resolve(picture);
          if (url == null || (!url.startsWith('http') && !url.startsWith('//'))) {
            return Image.asset('assets/images/logo3.png', fit: fit, width: width, height: height);
          }
          return Image.network(
            url.startsWith('//') ? 'https:$url' : url,
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
              opacity: frame == null && !sync ? 0.3 : 1,
              duration: const Duration(milliseconds: 250),
              child: child,
            ),
            errorBuilder: (context, error, st) =>
                Image.asset('assets/images/alt.webp', fit: fit, width: width, height: height),
          );
        },
      );
    }
    if (borderRadius != null) img = ClipRRect(borderRadius: borderRadius!, child: img);
    return img;
  }
}
