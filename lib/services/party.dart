import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/env.dart';
import '../core/http.dart';
import 'prefs.dart';

/// Watch party (movies PRD #11): up to 10 accounts watch one title in sync with camera / mic tiles, chat and
/// emoji. Same protocol as the web (web-app/src/components/party/usePartyRoom.js); see docs/notes.txt
/// "PRD #11 WATCH PARTY". Media goes peer to peer - the relay only carries offers / answers / ICE, which the
/// NEWCOMER starts with every member already in the room. The host's player drives play / pause / seek.
class PartyPeer {
  PartyPeer({required this.sid, required this.name, required this.role, required this.device, required this.media});
  final String sid;
  String name;
  String role;
  String device;
  bool media;
  bool camera = true;
  bool mic = false;
  RTCVideoRenderer? renderer;
  bool get isHost => role == 'host';
}

class PartyMessage {
  PartyMessage(this.from, this.name, this.text);
  final String from;
  final String name;
  final String text;
}

class PartyReaction {
  PartyReaction(this.emoji, this.name, this.key);
  final String emoji;
  final String name;
  final int key;
}

class PartyApi {
  PartyApi._();
  /// The reactions service takes the app token as Bearer (its URLs have no /android segment, so Http adds none).
  static Future<Map<String, dynamic>> post(String route, Map<String, dynamic> body) async {
    if (Api.reactionsBase.isEmpty) return {'status': false, 'message': 'Reactions are not configured (REACTIONS_API)'};
    final token = await Prefs.token;
    if (token == null || token.isEmpty) return {'status': false, 'message': 'Please sign in to use reactions'};
    final data = await Http.postJson(Api.reactions(route), body, headers: {'Authorization': 'Bearer $token'});
    return data is Map ? Map<String, dynamic>.from(data) : {'status': false, 'message': 'Something went wrong'};
  }
}

class PartyRoom extends ChangeNotifier {
  PartyRoom(this.code);
  final String code;

  static const reactionsAllowed = ['😂', '😮', '😍', '😢', '😡', '👏', '🔥', '❤️'];
  static const _driftS = 1.5;
  static const _hostBeat = Duration(seconds: 10);
  static const _iceBatch = Duration(milliseconds: 250);

  String status = 'idle'; // idle | connecting | live | ended | error
  String? error;
  String? role;
  String? me;
  Map<String, dynamic>? party;
  final Map<String, PartyPeer> peers = {};
  final List<PartyMessage> messages = [];
  final List<PartyReaction> reactions = [];
  bool camera = true;
  bool mic = false; // PRD: muted by default
  MediaStream? localStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  io.Socket? _socket;
  List<Map<String, dynamic>> _iceServers = [];
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, List<Map<String, dynamic>>> _iceOut = {};
  final Map<String, Timer> _iceTimers = {};
  final Map<String, List<RTCIceCandidate>> _iceIn = {};
  Player? _player;
  final List<StreamSubscription> _playerSubs = [];
  Timer? _beat;
  bool _disposed = false;
  int _reactionKey = 0;

  bool get isHost => role == 'host';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Joins the relay room; call once. The player is attached separately (it may not exist yet).
  Future<void> start() async {
    status = 'connecting';
    _changed();
    await localRenderer.initialize();
    // the reactions service's own room server - not the shared relay (M-PESA, shop chat, TV remote)
    final url = Api.reactionsBase;
    _socket = io.io(url.isEmpty ? 'http://127.0.0.1:4520' : url,
        io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().enableForceNew().build());
    final s = _socket!;
    s.onConnect((_) => _takeSeat());
    s.on('party-denied', (d) {
      status = 'error';
      error = d is Map ? '${d['reason']}' : 'could not join';
      _changed();
    });
    s.on('party-joined', (d) => _onJoined(Map<String, dynamic>.from(d as Map)));
    s.on('party-peer', (d) => _onPeer(Map<String, dynamic>.from(d as Map)));
    s.on('party-peer-left', (d) => _dropPeer('${(d as Map)['sid']}'));
    s.on('party-signal', (d) => _onSignal(Map<String, dynamic>.from(d as Map)));
    s.on('party-chat', (d) {
      final m = d as Map;
      messages.add(PartyMessage('${m['from']}', '${m['name']}', '${m['text']}'));
      if (messages.length > 100) messages.removeAt(0);
      _changed();
    });
    s.on('party-react', (d) {
      final r = d as Map;
      final item = PartyReaction('${r['emoji']}', '${r['name']}', _reactionKey++);
      reactions.add(item);
      if (reactions.length > 20) reactions.removeAt(0);
      _changed();
      Timer(const Duration(milliseconds: 3500), () {
        reactions.remove(item);
        _changed();
      });
    });
    s.on('party-media', (d) {
      final m = d as Map;
      final p = peers['${m['from']}'];
      if (p == null) return;
      p.camera = m['camera'] == true;
      p.mic = m['mic'] == true;
      _changed();
    });
    s.on('party-sync', (d) => _applySync(Map<String, dynamic>.from(d as Map)));
    s.on('party-sync-request', (_) => _sendState('state'));
    s.on('party-ended', (_) {
      status = 'ended';
      for (final sid in peers.keys.toList()) {
        _dropPeer(sid);
      }
      _changed();
    });
    s.connect();
  }

  Future<void> _takeSeat() async {
    final seat = await PartyApi.post('token', {'code': code});
    if (_disposed) return;
    if (seat['status'] != true) {
      status = 'error';
      error = '${seat['message'] ?? 'could not join the party'}';
      _changed();
      return;
    }
    _iceServers = (seat['ice'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    role = '${seat['role']}';
    party = seat['party'] is Map ? Map<String, dynamic>.from(seat['party'] as Map) : null;
    if (localStream == null) {
      try {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': {'echoCancellation': true, 'noiseSuppression': true},
          'video': {'facingMode': 'user', 'width': 320, 'height': 240, 'frameRate': 15},
        });
        for (final t in stream.getAudioTracks()) {
          t.enabled = false; // muted by default
        }
        if (_disposed) {
          await stream.dispose();
          return;
        }
        localStream = stream;
        localRenderer.srcObject = stream;
      } catch (e) {
        localStream = null; // permission refused / no camera: chat and watching still work
      }
    }
    _socket?.emit('party-join', [seat['ticket'], {'device': 'phone', 'media': localStream != null}]);
    _changed();
  }

  Future<void> _onJoined(Map<String, dynamic> d) async {
    me = '${d['you']}';
    role = '${d['role']}';
    status = 'live';
    for (final sid in peers.keys.toList()) {
      _dropPeer(sid); // a reconnect starts the calls over
    }
    for (final raw in (d['peers'] as List? ?? [])) {
      final p = Map<String, dynamic>.from(raw as Map);
      await _addPeer(p);
      unawaited(_offerTo('${p['sid']}'));
    }
    if (!isHost) _socket?.emit('party-sync-request');
    if (localStream != null) _socket?.emit('party-media', {'camera': camera, 'mic': mic});
    _attachHostListeners();
    _changed();
  }

  Future<void> _onPeer(Map<String, dynamic> p) async {
    await _addPeer(p);
    _changed();
  }

  Future<PartyPeer> _addPeer(Map<String, dynamic> p) async {
    final sid = '${p['sid']}';
    final existing = peers[sid];
    if (existing != null) return existing;
    final peer = PartyPeer(
      sid: sid,
      name: '${p['name'] ?? 'UKO viewer'}',
      role: '${p['role'] ?? 'guest'}',
      device: '${p['device'] ?? 'web'}',
      media: p['media'] != false,
    );
    peer.camera = peer.media;
    peers[sid] = peer;
    return peer;
  }

  Future<void> _dropPeer(String sid) async {
    final peer = peers.remove(sid);
    _iceTimers.remove(sid)?.cancel();
    _iceOut.remove(sid);
    _iceIn.remove(sid);
    final pc = _pcs.remove(sid);
    await pc?.close();
    final r = peer?.renderer;
    if (r != null) {
      r.srcObject = null;
      await r.dispose();
    }
    _changed();
  }

  void _signal(String to, Map<String, dynamic> data) => _socket?.emit('party-signal', {'to': to, 'data': data});

  void _queueIce(String to, RTCIceCandidate c) {
    (_iceOut[to] ??= []).add({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    _iceTimers[to] ??= Timer(_iceBatch, () {
      _iceTimers.remove(to);
      final list = _iceOut.remove(to) ?? [];
      if (list.isNotEmpty) _signal(to, {'ice': list});
    });
  }

  Future<RTCPeerConnection> _pcFor(String sid) async {
    final existing = _pcs[sid];
    if (existing != null) return existing;
    final pc = await createPeerConnection({'iceServers': _iceServers, 'sdpSemantics': 'unified-plan'});
    _pcs[sid] = pc;
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    } else {
      for (final kind in [RTCRtpMediaType.RTCRtpMediaTypeVideo, RTCRtpMediaType.RTCRtpMediaTypeAudio]) {
        await pc.addTransceiver(kind: kind, init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      }
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) _queueIce(sid, c);
    };
    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      final peer = peers[sid];
      if (peer == null) return;
      if (peer.renderer == null) {
        final r = RTCVideoRenderer();
        await r.initialize();
        peer.renderer = r;
      }
      peer.renderer!.srcObject = event.streams.first;
      _changed();
    };
    return pc;
  }

  Future<void> _offerTo(String sid) async {
    try {
      final pc = await _pcFor(sid);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _signal(sid, {'sdp': {'type': offer.type, 'sdp': offer.sdp}});
    } catch (e) {
      debugPrint('party offer: $e');
    }
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    final from = '${msg['from']}';
    final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : const <String, dynamic>{};
    try {
      final pc = await _pcFor(from);
      final sdp = data['sdp'];
      if (sdp is Map) {
        await pc.setRemoteDescription(RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'));
        for (final c in _iceIn.remove(from) ?? const <RTCIceCandidate>[]) {
          await pc.addCandidate(c);
        }
        if (sdp['type'] == 'offer') {
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _signal(from, {'sdp': {'type': answer.type, 'sdp': answer.sdp}});
        }
      }
      final ice = data['ice'];
      if (ice is List) {
        final candidates = ice.whereType<Map>().map((c) =>
            RTCIceCandidate('${c['candidate']}', c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt()));
        if (await pc.getRemoteDescription() == null) {
          (_iceIn[from] ??= []).addAll(candidates);
        } else {
          for (final c in candidates) {
            await pc.addCandidate(c);
          }
        }
      }
    } catch (e) {
      debugPrint('party signal: $e');
    }
  }

  // ---- playback: the host's player drives, everyone else follows

  /// The screen's media_kit player; attach as soon as it exists.
  void attachPlayer(Player player) {
    _player = player;
    _attachHostListeners();
  }

  void _attachHostListeners() {
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    _beat?.cancel();
    final p = _player;
    if (p == null || status != 'live') return;
    if (!isHost) return _attachGuestLock(p);
    _playerSubs.add(p.stream.playing.listen((playing) => _sendState(playing ? 'play' : 'pause')));
    // a seek shows up as a position jump the clock can't explain
    Duration last = p.state.position;
    DateTime lastAt = DateTime.now();
    _playerSubs.add(p.stream.position.listen((pos) {
      final now = DateTime.now();
      final expected = last + (p.state.playing ? now.difference(lastAt) : Duration.zero);
      if ((pos - expected).inMilliseconds.abs() > 2000) _sendState('seek');
      last = pos;
      lastAt = now;
    }));
    _beat = Timer.periodic(_hostBeat, (_) => _sendState('state'));
  }

  /// Only the host plays, pauses, seeks or stops. The speed screen hides a guest's controls ([isHost]); any
  /// play, pause or seek a guest still makes is put straight back to the host's last state.
  void _attachGuestLock(Player p) {
    _playerSubs.add(p.stream.playing.listen((playing) {
      final h = _hostNow();
      if (h == null || h.playing == playing) return;
      h.playing ? p.play() : p.pause();
    }));
    _playerSubs.add(p.stream.position.listen((pos) {
      final h = _hostNow();
      if (h != null && (pos - h.position).inMilliseconds.abs() > _driftS * 1000 * 2) p.seek(h.position);
    }));
  }

  ({Duration position, bool playing, DateTime at})? _hostState;
  ({Duration position, bool playing})? _hostNow() {
    final s = _hostState;
    if (s == null) return null;
    return (position: s.playing ? s.position + DateTime.now().difference(s.at) : s.position, playing: s.playing);
  }

  void _sendState(String action) {
    final p = _player;
    if (p == null || !isHost) return;
    _socket?.emit('party-sync', {
      'action': action,
      'position': p.state.position.inMilliseconds / 1000.0,
      'playing': p.state.playing,
    });
  }

  Future<void> _applySync(Map<String, dynamic> s) async {
    final p = _player;
    if (p == null || isHost) return;
    final target = Duration(milliseconds: ((s['position'] as num? ?? 0) * 1000).round());
    _hostState = (position: target, playing: s['playing'] == true, at: DateTime.now());
    if ((p.state.position - target).inMilliseconds.abs() > _driftS * 1000 || s['action'] == 'seek') {
      await p.seek(target);
    }
    final playing = s['playing'] == true;
    if (playing && !p.state.playing) await p.play();
    if (!playing && p.state.playing) await p.pause();
  }

  // ---- controls

  void toggleMic() {
    final stream = localStream;
    if (stream == null) return;
    mic = !mic;
    for (final t in stream.getAudioTracks()) {
      t.enabled = mic;
    }
    _socket?.emit('party-media', {'camera': camera, 'mic': mic});
    _changed();
  }

  void toggleCamera() {
    final stream = localStream;
    if (stream == null) return;
    camera = !camera;
    for (final t in stream.getVideoTracks()) {
      t.enabled = camera;
    }
    _socket?.emit('party-media', {'camera': camera, 'mic': mic});
    _changed();
  }

  void sendChat(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _socket?.emit('party-chat', clean.length > 300 ? clean.substring(0, 300) : clean);
  }

  void react(String emoji) => _socket?.emit('party-react', emoji);

  Future<void> end() async {
    if (!isHost) return;
    await PartyApi.post('end', {'code': code});
    _socket?.emit('party-end');
    status = 'ended';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _playerSubs) {
      s.cancel();
    }
    _beat?.cancel();
    for (final t in _iceTimers.values) {
      t.cancel();
    }
    final s = _socket;
    if (s != null) {
      s.emit('party-leave');
      s.clearListeners();
      s.dispose();
    }
    for (final pc in _pcs.values) {
      pc.close();
    }
    for (final p in peers.values) {
      p.renderer?.srcObject = null;
      p.renderer?.dispose();
    }
    localRenderer.srcObject = null;
    localRenderer.dispose();
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    super.dispose();
  }
}
