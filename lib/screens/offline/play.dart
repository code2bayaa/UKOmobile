// Port of mobile/app/offline/play.tsx (react-native-vlc-media-player -> media_kit).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import 'player_time.dart';

class OfflinePlayScreen extends StatefulWidget {
  const OfflinePlayScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<OfflinePlayScreen> createState() => _OfflinePlayScreenState();
}

class _OfflinePlayScreenState extends State<OfflinePlayScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hideTimer;

  // RN: `play` is really the `paused` flag (paused={play}).
  bool _paused = false;
  double _duration = 0; // ms
  double _currentTime = 0; // ms
  bool _seeking = false;
  bool _controlsVisible = false;
  bool _isLoadingVideo = true;

  String? get _video => P.str(widget.params, 'video');
  String? get _subtitle => P.str(widget.params, 'subtitle');
  String? get _name => P.str(widget.params, 'name');

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    final st = _player.stream;
    _subs.addAll([
      st.duration.listen((d) {
        if (mounted) setState(() => _duration = d.inMilliseconds.toDouble());
      }),
      st.position.listen((p) {
        if (!_seeking && mounted) setState(() => _currentTime = p.inMilliseconds.toDouble());
      }),
      st.playing.listen((playing) {
        // VLCPlayer onPlaying -> hide the spinner.
        if (playing && _isLoadingVideo && mounted) setState(() => _isLoadingVideo = false);
      }),
      st.error.listen((e) => debugPrint('offline player error: $e')),
    ]);
    _open();
  }

  Future<void> _open() async {
    final video = _video;
    if (video == null) return;
    try {
      await _player.open(Media(_asUri(video)), play: true);
      final sub = _subtitle;
      if (sub != null && await File(sub).exists()) {
        await _player.setSubtitleTrack(SubtitleTrack.uri(_asUri(sub), title: 'English', language: 'en'));
      }
    } catch (e) {
      debugPrint('offline open error: $e');
      if (mounted) setState(() => _isLoadingVideo = false);
    }
  }

  /// Accepts both absolute paths (port) and `file://` URIs (old RN records).
  String _asUri(String p) => p.startsWith('file://') ? p : Uri.file(p).toString();

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _vlcPlay() {
    setState(() => _paused = !_paused);
    _paused ? _player.pause() : _player.play();
    _showControls();
  }

  void _slideSeek(double value) {
    setState(() {
      _currentTime = value;
      _seeking = false;
    });
    _player.seek(Duration(milliseconds: value.round()));
  }

  Widget _roundButton({required Widget child, required VoidCallback onTap, required double width}) {
    return Container(
      margin: EdgeInsets.all(width * 0.01),
      width: width * 0.06,
      height: 50,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final max = _duration > 0 ? _duration : 1.0;
    return Scaffold(
      backgroundColor: UkoColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControls,
        child: Stack(
          children: [
            Center(
              child: SizedBox(
                width: 350,
                height: 275,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: _controller, controls: NoVideoControls, aspectRatio: 16 / 9, fit: BoxFit.contain),
                    if (_isLoadingVideo)
                      IgnorePointer(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.5),
                          alignment: Alignment.center,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: UkoColors.yellow),
                              SizedBox(height: 8),
                              Text('Loading video...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_controlsVisible)
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: size.width * 0.05),
                      Text('Playing ${_name ?? ''}', style: const TextStyle(color: Colors.white)),
                      SizedBox(height: size.width * 0.20),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _roundButton(
                            width: size.width,
                            onTap: _vlcPlay,
                            child: Icon(_paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
                                size: 30, color: Colors.black),
                          ),
                          Container(
                            margin: EdgeInsets.only(top: size.width * 0.01),
                            width: size.width * 0.8,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: Text(formatPlayerTime(_currentTime),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ),
                                Expanded(
                                  child: Slider(
                                    min: 0,
                                    max: max,
                                    value: _currentTime.clamp(0, max).toDouble(),
                                    activeColor: UkoColors.red,
                                    inactiveColor: UkoColors.border,
                                    thumbColor: UkoColors.red,
                                    onChangeStart: (_) => setState(() => _seeking = true),
                                    onChanged: (v) => setState(() => _currentTime = v),
                                    onChangeEnd: _slideSeek,
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: Text(formatPlayerTime(_duration),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
