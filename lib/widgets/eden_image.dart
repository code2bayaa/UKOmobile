// Eden studio images. Their paths are bucket keys ("6/images/1785....jpg"), not
// TMDB paths, so Picture's IMG_POSTER prefix does not apply: the bytes come from
// Eden's public POST /cinema/poster, as the web's eden/movies.jsx POSTER does.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/http.dart';
import 'picture.dart';
import '../core/theme.dart';

class EdenImage extends StatefulWidget {
  const EdenImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String? path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  static final RegExp _studioImage = RegExp(r'^\d+/images/');

  /// Studio uploads go through Eden; anything else (a TMDB path, a full URL) is Picture's.
  static bool isStudio(String? path) => path != null && _studioImage.hasMatch(path);

  // one request per image for the life of the app - a rail of posters shares them
  static final Map<String, Future<Uint8List?>> _cache = {};

  static Future<Uint8List?> _load(String path) {
    return _cache.putIfAbsent(path, () async {
      final res = await Http.post(Api.edenPoster, {'image': path});
      final type = res?.headers['content-type'] ?? '';
      if (res == null || res.statusCode != 200 || !type.startsWith('image/')) {
        _cache.remove(path); // let a later build retry
        return null;
      }
      return res.bodyBytes;
    });
  }

  @override
  State<EdenImage> createState() => _EdenImageState();
}

class _EdenImageState extends State<EdenImage> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant EdenImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    _bytes = EdenImage.isStudio(path) ? EdenImage._load(path!) : null;
  }

  Widget _fallback() => Image.asset('assets/images/alt.webp', fit: widget.fit, width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    Widget child;
    if (!EdenImage.isStudio(path)) {
      child = Picture(picture: path, fit: widget.fit, width: widget.width, height: widget.height);
    } else {
      child = FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const ColoredBox(color: UkoColors.border),
            );
          }
          final bytes = snap.data;
          if (bytes == null) return _fallback();
          return Image.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            gaplessPlayback: true,
            errorBuilder: (context, e, st) => _fallback(),
          );
        },
      );
    }
    final radius = widget.borderRadius;
    return radius == null ? child : ClipRRect(borderRadius: radius, child: child);
  }
}
