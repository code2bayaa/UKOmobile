// In-app YouTube playback for trailers and Eden reels. The YouTube iframe embed
// shows "Watch on YouTube" (error 152/153) inside an app WebView, so the video is
// resolved to its own stream with youtube_explode_dart and played by media_kit,
// the app's player. The iframe stays only as a last resort when a video cannot be
// resolved (age-gated, removed, or YouTube changed its API).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as iframe;

import '../core/theme.dart';

/// Resolves a YouTube id to a playable stream URL, cached for the session.
class YtStreams {
  YtStreams._();
  static final YoutubeExplode _yt = YoutubeExplode();
  // stream URLs expire after about 6 hours - resolve again after 5
  static final Map<String, ({Future<String?> url, DateTime at})> _cache = {};

  static Future<String?> resolve(String videoId) {
    final hit = _cache[videoId];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(hours: 5)) return hit.url;
    final url = _resolve(videoId);
    _cache[videoId] = (url: url, at: DateTime.now());
    url.then((u) {
      if (u == null) _cache.remove(videoId); // let a later tile retry
    });
    return url;
  }

  static Future<String?> _resolve(String videoId) async {
    for (final clients in [null, [YoutubeApiClient.androidVr]]) {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId, ytClients: clients);
        final muxed = manifest.muxed.where((s) => s.container == StreamContainer.mp4).toList();
        final pick = muxed.isNotEmpty ? muxed : manifest.muxed.toList();
        if (pick.isNotEmpty) return pick.withHighestBitrate().url.toString();
      } catch (e) {
        debugPrint('youtube stream $videoId (${clients?.length ?? 'default'}): $e');
      }
    }
    return null;
  }
}

/// A YouTube video played in the app. Swap [videoId] to play another one.
class YtPlayer extends StatefulWidget {
  const YtPlayer({
    super.key,
    required this.videoId,
    this.autoplay = true,
    this.muted = false,
    this.active = true,
    this.controls = true,
    this.fit = BoxFit.contain,
    this.onEnded,
  });

  final String videoId;
  final bool autoplay;
  final bool muted;

  /// false pauses it (a swiper page scrolled away)
  final bool active;
  final bool controls;
  final BoxFit fit;
  final VoidCallback? onEnded;

  @override
  State<YtPlayer> createState() => _YtPlayerState();
}

class _YtPlayerState extends State<YtPlayer> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  StreamSubscription<bool>? _completed;
  iframe.YoutubePlayerController? _fallback;
  bool _loading = true;
  bool _failed = false;
  int _load = 0; // drops a stale resolve when the id changed meanwhile

  @override
  void initState() {
    super.initState();
    _completed = _player.stream.completed.listen((done) {
      if (done) widget.onEnded?.call();
    });
    _open();
  }

  @override
  void didUpdateWidget(covariant YtPlayer old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      _open();
      return;
    }
    if (old.muted != widget.muted) _player.setVolume(widget.muted ? 0 : 100);
    if (old.active != widget.active) {
      if (widget.active) {
        _player.play();
        _fallback?.playVideo();
      } else {
        _player.pause();
        _fallback?.pauseVideo();
      }
    }
  }

  Future<void> _open() async {
    final load = ++_load;
    _fallback?.pauseVideo();
    setState(() {
      _loading = true;
      _failed = false;
    });
    final url = await YtStreams.resolve(widget.videoId);
    if (!mounted || load != _load) return;
    if (url == null) {
      _player.stop();
      _openFallback();
      return;
    }
    await _player.setVolume(widget.muted ? 0 : 100);
    await _player.open(Media(url), play: widget.autoplay && widget.active);
    if (mounted && load == _load) setState(() => _loading = false);
  }

  void _openFallback() {
    _fallback ??= iframe.YoutubePlayerController(
      params: const iframe.YoutubePlayerParams(
        showFullscreenButton: true,
        playsInline: true,
        strictRelatedVideos: true,
        // YouTube wants an embedder identity; the default youtube.com origin gets error 152/153
        origin: 'https://uko-app.co.ke',
      ),
    );
    if (widget.autoplay && widget.active) {
      _fallback!.loadVideoById(videoId: widget.videoId);
    } else {
      _fallback!.cueVideoById(videoId: widget.videoId);
    }
    if (widget.muted) _fallback!.mute();
    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  @override
  void dispose() {
    _completed?.cancel();
    _player.dispose();
    _fallback?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed && _fallback != null) {
      return iframe.YoutubePlayer(controller: _fallback!, backgroundColor: Colors.black);
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // the thumbnail until the first frame
          if (_loading)
            Image.network(
              'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, e, st) => const SizedBox.shrink(),
            ),
          Video(
            controller: _video,
            fit: widget.fit,
            fill: Colors.transparent,
            controls: widget.controls ? AdaptiveVideoControls : NoVideoControls,
          ),
          if (_loading) const Center(child: CircularProgressIndicator(color: UkoColors.yellow)),
        ],
      ),
    );
  }
}
