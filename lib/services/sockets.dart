import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/env.dart';

/// Port of middleware/sockets.js (+ the TV app's lib/config/socket.dart).
/// URL: SOCKET_API_SANDBOX in development, SOCKET_API_LIVE otherwise;
/// websocket transport only, autoConnect off.
class SocketsService {
  SocketsService._();
  static final SocketsService instance = SocketsService._();

  io.Socket? _socket;
  io.Socket? get socket => _socket;

  final List<void Function()> _connectListeners = [];

  io.Socket connect() {
    if (_socket != null) return _socket!;
    final url = Env.isDev ? Env.socketApiSandbox : Env.socketApiLive;
    if (kDebugMode) debugPrint('socket url: $url');
    _socket = io.io(
      url.isEmpty ? 'http://127.0.0.1:8082' : url,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    // Fires on the first connect and on every reconnect.
    _socket!.onConnect((_) {
      for (final l in List.of(_connectListeners)) {
        l();
      }
    });
    return _socket!;
  }

  void addConnectListener(void Function() l) => _connectListeners.add(l);

  /// `SOCKETS.socketConnect()`
  void socketConnect() {
    final s = connect();
    if (!s.connected) s.connect();
  }

  void disconnect() {
    if (_socket?.connected ?? false) _socket!.disconnect();
  }

  /// Emits `event` with multiple positional args, like
  /// `socket.emit(event, a, b, c)` in JS (socket_io_client spreads a List).
  void emitArgs(String event, List<dynamic> args) {
    socketConnect();
    _socket?.emit(event, args);
  }

  void on(String event, dynamic Function(dynamic) handler) => connect().on(event, handler);

  void off(String event, [dynamic Function(dynamic)? handler]) => _socket?.off(event, handler);

  /// `checkSocket` — emits "in" with an ack.
  Future<bool> checkSocket(String portal) {
    final c = Completer<bool>();
    final s = _socket;
    if (s == null) return Future.value(false);
    s.emitWithAck('in', portal, ack: (res) {
      if (!c.isCompleted) c.complete(res == true);
    });
    return c.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
  }
}
