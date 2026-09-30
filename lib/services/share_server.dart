// The seller's side of a phone-to-phone sale (movies PRD #10): a small HTTP server on the local network
// (the same Wi-Fi, or the seller's own hotspot - how Xender does it) that hands one downloaded video to a buyer.
//
//   GET /uko-sale/offer?code=C                  what is on offer (title, poster, sizes) - no file
//   GET /uko-sale/image?code=C                  the poster
//   GET /uko-sale/video?code=C&ticket=T         the video, only for a ticket UKO confirms is a paid sale of C
//   GET /uko-sale/subtitle?code=C&ticket=T      the subtitles, same rule
//
// Nothing is sent before UKO says the ticket is paid (SalesApi.verify), so the file only ever goes to a buyer
// whose M-PESA payment Safaricom confirmed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sales_api.dart';

class ShareTransfer {
  ShareTransfer(this.id);
  final int id;
  int sent = 0;
  int total = 0;
  String state = 'sending'; // sending | done | failed
}

class ShareServer {
  ShareServer({required this.code, required this.record, required this.onChange});

  /// the offer's code from UKO
  final String code;

  /// the OfflineStore index entry: {name, video, subtitle, image, data}
  final Map<String, dynamic> record;
  final VoidCallback onChange;

  HttpServer? _server;
  final Set<String> _paidTickets = {};
  final List<ShareTransfer> transfers = [];
  int _nextTransfer = 1;

  int get port => _server?.port ?? 0;

  /// the phone's local IPv4 addresses a buyer can reach - Wi-Fi and hotspot first
  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    int rank(NetworkInterface i) {
      final n = i.name.toLowerCase();
      if (n.contains('ap') || n.contains('swlan') || n.contains('softap')) return 0; // hotspot
      if (n.startsWith('wlan') || n.startsWith('en') || n.contains('wifi')) return 1;
      if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('pdp')) return 9; // mobile data - not local
      return 5;
    }
    interfaces.sort((a, b) => rank(a).compareTo(rank(b)));
    final hosts = <String>[];
    for (final i in interfaces) {
      if (rank(i) == 9) continue;
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) hosts.add(a.address);
      }
    }
    return hosts;
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_handle, onError: (e) => debugPrint('share server: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  File? _file(String key) {
    final p = record[key];
    if (p is! String || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  Future<bool> _ticketPaid(String ticket) async {
    if (ticket.isEmpty) return false;
    if (_paidTickets.contains(ticket)) return true;
    final res = await SalesApi.verify(code, ticket);
    if (res['status'] == true) {
      _paidTickets.add(ticket);
      return true;
    }
    return false;
  }

  Future<void> _json(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final q = req.uri.queryParameters;
      if (req.method != 'GET' || (q['code'] ?? '').toUpperCase() != code) {
        return await _json(req, 404, {'status': false, 'message': 'Not on offer here'});
      }
      switch (req.uri.path) {
        case '/uko-sale/offer':
          final video = _file('video');
          final ext = video == null ? 'mp4' : video.path.split('.').last;
          return await _json(req, 200, {
            'status': true,
            'code': code,
            'name': record['name'],
            'data': record['data'],
            'format': ext,
            'size': video?.lengthSync() ?? 0,
            'has_image': _file('image') != null,
            'has_subtitle': _file('subtitle') != null,
          });
        case '/uko-sale/image':
          final image = _file('image');
          if (image == null) return await _json(req, 404, {'status': false});
          req.response.headers.contentType = ContentType('image', 'jpeg');
          req.response.headers.contentLength = await image.length();
          await req.response.addStream(image.openRead());
          return await req.response.close();
        case '/uko-sale/video':
        case '/uko-sale/subtitle':
          if (!await _ticketPaid(q['ticket'] ?? '')) {
            return await _json(req, 403, {'status': false, 'message': 'Pay for this video first'});
          }
          final isVideo = req.uri.path.endsWith('video');
          final file = _file(isVideo ? 'video' : 'subtitle');
          if (file == null) return await _json(req, 404, {'status': false, 'message': 'File not found'});
          return await (isVideo ? _sendVideo(req, file) : _sendFile(req, file, ContentType('text', 'vtt')));
        default:
          return await _json(req, 404, {'status': false});
      }
    } catch (e) {
      debugPrint('share server request: $e');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _sendFile(HttpRequest req, File file, ContentType type) async {
    req.response.headers.contentType = type;
    req.response.headers.contentLength = await file.length();
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  Future<void> _sendVideo(HttpRequest req, File file) async {
    final transfer = ShareTransfer(_nextTransfer++)..total = await file.length();
    transfers.insert(0, transfer);
    onChange();
    var lastUpdate = DateTime.now();
    try {
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.headers.contentLength = transfer.total;
      await req.response.addStream(file.openRead().map((chunk) {
        transfer.sent += chunk.length;
        if (DateTime.now().difference(lastUpdate).inMilliseconds > 400) {
          lastUpdate = DateTime.now();
          onChange();
        }
        return chunk;
      }));
      await req.response.close();
      transfer.state = 'done';
    } catch (e) {
      transfer.state = 'failed';
      debugPrint('share server video: $e');
    }
    onChange();
  }
}
