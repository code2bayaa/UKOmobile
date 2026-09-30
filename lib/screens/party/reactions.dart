import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../routes.dart';
import '../../services/party.dart';
import '../../widgets/eden_image.dart';

/// Reactions (movies PRD #11): the reactions going on right now that their hosts made public, from the
/// reactions service's /reactions/live. Join opens the join screen (join_party.dart), which shows the fee and
/// takes the seat; a private reaction is joined with its code in the box at the top.
class ReactionsScreen extends StatefulWidget {
  const ReactionsScreen({super.key});

  @override
  State<ReactionsScreen> createState() => _ReactionsScreenState();
}

class _ReactionsScreenState extends State<ReactionsScreen> {
  static const _refresh = Duration(seconds: 20);
  final _code = TextEditingController();
  List<Map<String, dynamic>>? _parties;
  String? _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await PartyApi.post('live', {});
    if (!mounted) return;
    setState(() {
      if (res['status'] == true) {
        _message = null;
        _parties = (res['parties'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _message = '${res['message'] ?? 'Could not load reactions'}';
        _parties ??= [];
      }
    });
  }

  void _open(String code) => Nav.push(context, Routes.party, {'code': code});

  String _since(num minutes) {
    final m = minutes.toInt();
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final parties = _parties;
    return RefreshIndicator(
      onRefresh: _load,
      color: UkoColors.yellow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Row(children: [
            Icon(Icons.groups, color: UkoColors.yellow),
            SizedBox(width: 8),
            Text('Reactions', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          const Text('Watch along live with camera, mic and chat. Start one from any movie or episode with "start a reaction".',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, letterSpacing: 4),
                decoration: const InputDecoration(
                  hintText: 'Have a code?',
                  hintStyle: TextStyle(color: Colors.white38, letterSpacing: 0),
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
              onPressed: () {
                final code = _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                if (code.length == 6) _open(code);
              },
              child: const Text('Join'),
            ),
          ]),
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!, style: const TextStyle(color: Colors.redAccent))),
          if (parties == null)
            const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: CircularProgressIndicator(color: UkoColors.yellow))),
          if (parties != null && parties.isEmpty && _message == null)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Text('No public reactions right now. Start one from a movie or episode.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final p in parties ?? const <Map<String, dynamic>>[]) _card(p),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final members = (p['members'] as num?)?.toInt() ?? 0;
    final max = (p['max_members'] as num?)?.toInt() ?? 10;
    final fee = (p['fee'] as num?)?.toInt() ?? 0;
    final full = members >= max;
    final season = p['season'];
    return Container(
      margin: const EdgeInsets.only(top: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            // EdenImage shows an Eden upload itself and hands a TMDB path to Picture
            EdenImage(path: p['picture'] as String?),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(4)),
                child: Text('● LIVE ${_since((p['live_minutes'] as num?) ?? 0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            if (p['eden'] == true)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: Colors.black54,
                  child: const Text('EDEN', style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1)),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title'] ?? 'Untitled'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (season != null)
              Text('Season $season${p['episode'] != null ? ' · Episode ${p['episode']}' : ''}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 2),
            Text('Hosted by ${p['host']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text('$members / $max watching', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(fee > 0 ? '$fee credits to join' : 'Free to join', style: const TextStyle(color: UkoColors.yellow, fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
                onPressed: full ? null : () => _open('${p['code']}'),
                child: Text(full ? 'Full' : 'Join'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
