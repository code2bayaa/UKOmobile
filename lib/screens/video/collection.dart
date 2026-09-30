import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';
import '../../widgets/no_credits.dart';

/// `index.toString().replace("0","a").replace("1","b")...replace("9","j")`
/// from components/home/collection.jsx:262.
///
/// NOTE: JS `String.replace` with a string pattern replaces only the FIRST
/// occurrence, so "11" -> "b1" and "100" -> "ba0". The server decodes this
/// exact form, so the port keeps it (replaceFirst, in the same 0..9 order).
String encodeCollectionIndex(dynamic index) {
  var s = js(index);
  const letters = 'abcdefghij';
  for (var d = 0; d < 10; d++) {
    s = s.replaceFirst('$d', letters[d]);
  }
  return s;
}

/// Port of components/home/collection.jsx (COLLECTIONS): one quality button on
/// video/stream. Tapping it checks rent/credits, asks the PLAY endpoint to
/// prepare the torrent and opens /video/vlc. While the TV remote is on it first
/// shows the "Choose player" dialog (VLC / Remote Player on the TV).
class Collection extends StatefulWidget {
  const Collection({
    super.key,
    required this.id,
    required this.index,
    required this.token,
    required this.quality,
    required this.size,
    required this.seeders,
    required this.maxRate,
    required this.stream,
    required this.background,
    required this.serieID,
    required this.anime,
    required this.serieName,
    required this.season,
    required this.episode,
    required this.connected,
    required this.onAlert,
    this.title,
  });

  final dynamic id;
  final int index;
  final dynamic token;
  final dynamic quality;
  final dynamic size;
  final dynamic seeders;
  final num maxRate;
  final dynamic stream;
  final dynamic background;
  final dynamic serieID;
  final dynamic anime;
  final dynamic serieName;
  final dynamic season;
  final dynamic episode;
  final dynamic title;
  final bool connected;

  /// setTitleMsg + setMessageAlert + setShowAlert + removeAlert of the parent.
  final void Function(String title, String message) onAlert;

  @override
  State<Collection> createState() => _CollectionState();
}

class _CollectionState extends State<Collection> {
  bool _loading = false;
  double _rate = 0;

  /// Replaces the AbortController: bumped on dispose / new run so stale
  /// responses are ignored.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _putStream();
  }

  @override
  void didUpdateWidget(covariant Collection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxRate != widget.maxRate ||
        oldWidget.seeders != widget.seeders ||
        oldWidget.stream != widget.stream) {
      _putStream();
    }
  }

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  /// useEffect([maxRate, seeders, stream]): rate + AsyncStorage "type".
  void _putStream() {
    final idx = (toNum(widget.seeders) / widget.maxRate) * 10;
    _rate = idx.toDouble();
    final s = truthy(widget.stream) ? '${widget.stream}' : 'default';
    Prefs.setItem(PrefKeys.type, s);
  }

  bool _alive(int gen) => mounted && gen == _gen;

  Map<String, dynamic> _tvState() => {
        'id': widget.id,
        'index': widget.index,
        'type': widget.stream,
        'background': widget.background,
        'serieID': widget.serieID,
        'anime': widget.anime,
        'serie_name': widget.serieName,
        'season': widget.season,
        'episode': widget.episode,
      };

  Future<void> _runStream() async {
    final gen = ++_gen;
    final stream = await Prefs.getItem(PrefKeys.type);
    var hasCredits = false;
    var hasPaid = false;

    final email = await Prefs.user;
    // a guest has no credits to check - ask them to sign up (widgets/no_credits.dart)
    if (email == null || email.isEmpty) {
      // `mounted` spelled out so the analyzer sees the guard (_alive checks it too)
      if (!mounted || !_alive(gen)) return;
      await promptGuestSignUp(context);
      return;
    }
    final paid = await Http.postJson(Api.userPaid, {'id': widget.id, 'email': email});
    if (!_alive(gen)) return;
    // RN: `await response.json()` throwing -> caught, nothing else happens.
    if (paid is! Map) return;
    if (truthy(paid['status'])) {
      hasPaid = true;
      widget.onAlert('success', 'rent paid ${js(paid['message'])}');
    } else if (paid['message'] == 'day for movie credits ended') {
      widget.onAlert('rent elapsed', '${paid['message']}');
    }

    final credits = await Http.postJson(Api.checkUserCredits, {'username': await Prefs.user});
    if (!_alive(gen)) return;
    if (credits is! Map) return;
    final sum = credits['sum'];
    if (truthy(sum) && toNum(sum) > 49) hasCredits = true;

    if (!hasCredits && !hasPaid) {
      widget.onAlert('NO CREDITS', 'add more credits');
      return;
    }
    if (!truthy(widget.token)) return;

    setState(() => _loading = true);
    final index = encodeCollectionIndex(widget.index);
    final res = await Http.postJson(Api.play, {
      'token': widget.token,
      'id': widget.id,
      'index': index,
      'quality': widget.quality,
      'stream': stream,
      'size': widget.size,
    });
    if (!_alive(gen)) return;
    if (res is! Map) {
      setState(() => _loading = false);
      return;
    }
    if (truthy(res['status'])) {
      final files = res['files'];
      Map? video;
      if (files is List) {
        for (final f in files) {
          if (f is Map) {
            final name = '${f['name']}';
            if (name.endsWith('.mp4') || name.endsWith('.mkv')) {
              video = f;
              break;
            }
          }
        }
      }
      if (video != null) {
        final type = video.containsKey('name') ? '${video['name']}'.split('.').last : null;
        setState(() => _loading = false);
        if (!mounted) return;
        Nav.push(context, Routes.videoVlc, {
          'id': widget.id,
          'url': res['url'],
          'index': index,
          'type': type,
          'background': widget.background,
          'serieID': widget.serieID,
          'anime': widget.anime,
          'serie_name': widget.serieName,
          'season': widget.season,
          'episode': widget.episode,
        });
      } else {
        widget.onAlert('error', 'media not found');
      }
    } else {
      widget.onAlert('choose next collection', 'was not worth your time');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openModal() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
      builder: (ctx) {
        final w = MediaQuery.of(ctx).size.width * 0.8;
        Widget button(String label, Color bg, Color fg, Color? border, VoidCallback onTap) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: border == null ? BorderSide.none : BorderSide(color: border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(child: Text(label, style: TextStyle(color: fg))),
                    ),
                  ),
                ),
              ),
            );
        return Dialog(
          backgroundColor: UkoColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: w,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Choose player',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  button('Play with VLC', UkoColors.yellow, Colors.black, null, () {
                    Navigator.of(ctx).pop();
                    _openVlcPlayer();
                  }),
                  button('Play with Remote Player', UkoColors.card, UkoColors.yellow, UkoColors.yellow, () {
                    Navigator.of(ctx).pop();
                    _openRemotePlayer();
                  }),
                  button('Cancel', Colors.transparent, Colors.white, Colors.white, () => Navigator.of(ctx).pop()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// openVLCPlayer: run the stream locally AND tell the TV to open `/third`.
  /// The TV state carries the original (un-encoded) index, as in RN.
  void _openVlcPlayer() {
    unawaited(_runStream());
    RemoteService.instance.route(TvPaths.third, _tvState(), true);
  }

  /// openRemotePlayer: same, TV route `/remote`.
  void _openRemotePlayer() {
    unawaited(_runStream());
    RemoteService.instance.route(TvPaths.remotePlayer, _tvState(), true);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final sizeText = size == null ? '' : '$size'.replaceFirst('i', '').toLowerCase();
    return Container(
      width: MediaQuery.of(context).size.width * 0.98,
      constraints: const BoxConstraints(minHeight: 40),
      margin: EdgeInsets.all(MediaQuery.of(context).size.width * 0.01),
      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)),
      child: InkWell(
        onTap: _loading
            ? null
            : () {
                if (widget.connected) {
                  _openModal();
                } else {
                  _runStream();
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _loading
              ? const Text('loading...', style: TextStyle(color: Colors.white))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.quality}',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (_rate > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_border, size: 30, color: UkoColors.yellow),
                            Text(' ${_rate.isFinite ? _rate.toStringAsFixed(1) : 'Infinity'}',
                                style: const TextStyle(color: UkoColors.yellow, fontSize: 20)),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(sizeText,
                          style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 20)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
