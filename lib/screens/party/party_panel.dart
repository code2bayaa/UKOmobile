import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/theme.dart';
import '../../services/party.dart';

/// Watch party side panel over the landscape player (movies PRD #11): camera / mic tiles, chat, emoji, and
/// the host's End / everyone's Leave. The room itself (relay, calls, sync) is services/party.dart.
class PartyPanel extends StatefulWidget {
  const PartyPanel({super.key, required this.room, required this.onLeave, this.onShowOnTv});
  final PartyRoom room;
  final VoidCallback onLeave;
  final VoidCallback? onShowOnTv;

  @override
  State<PartyPanel> createState() => _PartyPanelState();
}

class _PartyPanelState extends State<PartyPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    widget.room.sendChat(_text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.room,
      builder: (context, _) {
        final room = widget.room;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
        return Container(
          color: Colors.black.withValues(alpha: 0.82),
          padding: const EdgeInsets.all(8),
          child: switch (room.status) {
            'error' => _notice('Could not join the watch party: ${room.error ?? ''}'),
            'ended' => _notice('This watch party has ended.'),
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(room),
                  if (room.status == 'connecting')
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Connecting…', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ),
                  if (room.role != null && !room.isHost)
                    const Text('Only the host can play, pause, seek or stop the movie.',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  SizedBox(height: 84, child: _tiles(room)),
                  _controls(room),
                  Expanded(child: _chat(room)),
                  _input(),
                ],
              ),
          },
        );
      },
    );
  }

  Widget _notice(String text) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text, style: const TextStyle(color: Colors.white)),
          TextButton(onPressed: widget.onLeave, child: const Text('Close', style: TextStyle(color: UkoColors.yellow))),
        ],
      );

  Widget _header(PartyRoom room) {
    final fee = (room.party?['fee'] as num?)?.toInt() ?? 0;
    return Row(children: [
      const Icon(Icons.groups, color: UkoColors.yellow, size: 18),
      const SizedBox(width: 6),
      InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: room.code));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Party code copied')));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
          child: Text(room.code, style: const TextStyle(color: Colors.white, letterSpacing: 2, fontSize: 13)),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text('${room.peers.length + 1} watching · ${fee > 0 ? '$fee cr' : 'free'}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ),
      if (widget.onShowOnTv != null)
        IconButton(
          tooltip: 'Show on TV',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onShowOnTv,
          icon: const Icon(Icons.tv, color: Colors.white70, size: 18),
        ),
      TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () async {
          if (room.isHost) {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('End the party?'),
                content: const Text('Everyone leaves the room; each of you can keep watching on your own.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('End party')),
                ],
              ),
            );
            if (ok == true) await room.end();
          } else {
            widget.onLeave();
          }
        },
        child: Text(room.isHost ? 'End' : 'Leave',
            style: TextStyle(color: room.isHost ? Colors.redAccent : Colors.white70, fontSize: 12)),
      ),
    ]);
  }

  Widget _tiles(PartyRoom room) {
    final tiles = <Widget>[
      _Tile(
          renderer: room.localStream != null ? room.localRenderer : null,
          name: 'You',
          camera: room.camera,
          mic: room.mic,
          mirror: true,
          host: room.isHost),
      for (final p in room.peers.values)
        _Tile(
            renderer: p.renderer,
            name: p.name,
            camera: p.camera && p.media,
            mic: p.mic,
            tv: p.device == 'tv',
            host: p.isHost),
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: tiles.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, i) => tiles[i],
    );
  }

  Widget _controls(PartyRoom room) {
    final hasMedia = room.localStream != null;
    return Row(children: [
      _round(room.mic ? Icons.mic : Icons.mic_off, room.mic ? Colors.green : Colors.white12,
          hasMedia ? room.toggleMic : null),
      const SizedBox(width: 6),
      _round(room.camera ? Icons.videocam : Icons.videocam_off, room.camera ? Colors.white12 : Colors.red.withValues(alpha: 0.7),
          hasMedia ? room.toggleCamera : null),
      const SizedBox(width: 4),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in PartyRoom.reactionsAllowed)
              InkWell(
                onTap: () => room.react(e),
                child: Padding(padding: const EdgeInsets.all(4), child: Text(e, style: const TextStyle(fontSize: 20))),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _round(IconData icon, Color bg, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      );

  Widget _chat(PartyRoom room) {
    if (room.messages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text("Say hi - messages show on everyone's screen.", style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: room.messages.length,
      itemBuilder: (_, i) {
        final m = room.messages[i];
        final mine = m.from == room.me;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '${mine ? 'You' : m.name}: ',
                style: TextStyle(color: mine ? UkoColors.yellow : Colors.white60, fontSize: 12)),
            TextSpan(text: m.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ])),
        );
      },
    );
  }

  Widget _input() => Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            maxLength: 300,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onSubmitted: (_) => _send(),
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Message the party',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderSide: BorderSide.none),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(onPressed: _send, icon: const Icon(Icons.send, color: UkoColors.yellow)),
      ]);
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.renderer,
    required this.name,
    required this.camera,
    required this.mic,
    this.mirror = false,
    this.tv = false,
    this.host = false,
  });
  final RTCVideoRenderer? renderer;
  final String name;
  final bool camera;
  final bool mic;
  final bool mirror;
  final bool tv;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final showVideo = renderer != null && camera && !tv;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 96,
        color: const Color(0xFF2E2E3A),
        child: Stack(fit: StackFit.expand, children: [
          if (showVideo)
            // remote tiles also carry that person's voice; flutter_webrtc plays it through the renderer
            RTCVideoView(renderer!, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(
              child: tv
                  ? const Icon(Icons.tv, color: Colors.white54, size: 26)
                  : Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white54, fontSize: 24)),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Row(children: [
                if (host) const Icon(Icons.workspace_premium, color: UkoColors.yellow, size: 11),
                Expanded(
                  child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
                if (!tv) Icon(mic ? Icons.mic : Icons.mic_off, size: 11, color: mic ? Colors.greenAccent : Colors.white54),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Emoji the party sends float up over the video.
class PartyReactionsLayer extends StatelessWidget {
  const PartyReactionsLayer({super.key, required this.room});
  final PartyRoom room;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: room,
        builder: (context, _) => Stack(children: [
          for (final r in room.reactions)
            Positioned(
              key: ValueKey(r.key),
              left: 24.0 + (r.key * 53 % 280),
              bottom: 40,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 3000),
                builder: (_, t, child) => Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(offset: Offset(0, -160 * t), child: child),
                ),
                child: Text(r.emoji, style: const TextStyle(fontSize: 34)),
              ),
            ),
        ]),
      ),
    );
  }
}
