// Sell a downloaded video to a nearby UKOapp user (movies PRD #10), the seller's screen.
// Set a price -> UKO opens an offer -> this phone serves the file on the local network (Wi-Fi or its hotspot) and
// shows a QR. The buyer scans it in their app, pays by M-PESA, and the file comes straight from this phone.
// 70% of the price goes to the seller's sales balance (withdrawn to M-PESA), 30% to UKO.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/sales_api.dart';
import '../../services/share_server.dart';
import 'file_system.dart';

class SellVideoScreen extends StatefulWidget {
  const SellVideoScreen({super.key, required this.params});
  final Map<String, dynamic> params;

  @override
  State<SellVideoScreen> createState() => _SellVideoScreenState();
}

class _SellVideoScreenState extends State<SellVideoScreen> {
  final _price = TextEditingController(text: '50');
  Map<String, dynamic>? _record;
  Map<String, dynamic>? _offer;
  ShareServer? _server;
  List<String> _hosts = [];
  bool _busy = false;
  String? _error;
  double? _share;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stop(silent: true);
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = '${widget.params['key'] ?? ''}';
    final record = await OfflineStore.getVideoRecord(key);
    if (mounted) setState(() => _record = record);
  }

  Map<String, dynamic> get _data =>
      _record?['data'] is Map ? Map<String, dynamic>.from(_record!['data'] as Map) : <String, dynamic>{};

  String get _title => '${or([_data['title'], _data['original_title'], _data['name'], _data['original_name'], _record?['name']]) ?? 'UKO video'}';

  // TV rows carry name / first_air_date; movies title / release_date
  String get _type => (_data['first_air_date'] != null || (_data['title'] == null && _data['name'] != null)) ? 'tv' : 'movie';

  Future<void> _start() async {
    final record = _record;
    final price = int.tryParse(_price.text.trim());
    if (record == null) return;
    if (price == null || price < 10 || price > 10000) {
      setState(() => _error = 'Set a price of KSh 10 - 10,000');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final hosts = await ShareServer.localAddresses();
    if (hosts.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Turn on Wi-Fi or your hotspot first - the buyer connects to it to receive the video.';
      });
      return;
    }
    final videoPath = record['video'];
    final res = await SalesApi.offer(
      titleId: '${_data['id'] ?? record['name']}',
      titleType: _type,
      eden: _data['eden'] != null && '${_data['eden']}' != '0' && '${_data['eden']}' != 'false',
      name: _title,
      price: price,
      fileSize: videoPath is String ? await OfflineStore.fileSize(videoPath) : null,
    );
    if (res['status'] != true || res['offer'] is! Map) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${res['message'] ?? 'Could not start selling'}';
        });
      }
      return;
    }
    final offer = Map<String, dynamic>.from(res['offer'] as Map);
    final server = ShareServer(code: '${offer['code']}', record: record, onChange: () {
      if (mounted) setState(() {});
    });
    try {
      await server.start();
    } catch (e) {
      await SalesApi.close('${offer['code']}');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not share on this network ($e)';
        });
      }
      return;
    }
    if (!mounted) {
      await server.stop();
      return;
    }
    setState(() {
      _busy = false;
      _offer = offer;
      _server = server;
      _hosts = hosts;
      _share = double.tryParse('${res['seller_share']}');
    });
  }

  Future<void> _stop({bool silent = false}) async {
    final server = _server;
    final code = _offer?['code'];
    _server = null;
    await server?.stop();
    if (code != null) await SalesApi.close('$code');
    if (!silent && mounted) setState(() => _offer = null);
  }

  String get _qrPayload => jsonEncode({'t': 'uko-sale', 'v': 1, 'code': _offer?['code'], 'hosts': _hosts, 'port': _server?.port});

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Widget _pricing() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_title, style: ukoHeading(fontSize: 22)),
          const SizedBox(height: 16),
          const Text('Price for one copy (KSh)', style: TextStyle(color: UkoColors.muted)),
          const SizedBox(height: 6),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: 'KSh ', hintText: '50'),
          ),
          const SizedBox(height: 8),
          Text(
            'The buyer gets the video, its poster and description${_record?['subtitle'] != null ? ' and subtitles' : ''} '
            'straight from this phone over Wi-Fi or your hotspot - no internet data used for the file.',
            style: const TextStyle(color: UkoColors.divider, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'You get 70% of every sale in your sales balance, withdrawable to M-PESA. UKO keeps 30%.',
            style: TextStyle(color: UkoColors.divider, fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: UkoColors.destructive)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy || _record == null ? null : _start,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_busy ? 'Starting...' : 'Start selling'),
            ),
          ),
        ],
      );

  Widget _selling() {
    final server = _server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_title, style: ukoHeading(fontSize: 22)),
        const SizedBox(height: 4),
        Text('KSh ${_offer?['price']}  ·  you get KSh ${_share?.toStringAsFixed(2) ?? '-'} a copy',
            style: const TextStyle(color: UkoColors.yellow)),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(data: _qrPayload, size: 220, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('Code ${_offer?['code']}', style: const TextStyle(color: UkoColors.muted, letterSpacing: 2))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: UkoColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: UkoColors.border),
          ),
          child: const Text(
            'Buyer: connect to the same Wi-Fi as this phone (or to this phone\'s hotspot), open UKO > Downloads, tap the '
            'scan button at the top and scan this code. The video is sent once their M-PESA payment is confirmed. '
            'Keep this screen open until it finishes.',
            style: TextStyle(color: UkoColors.text, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        if (server != null)
          for (final t in server.transfers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                t.state == 'done' ? Icons.check_circle : t.state == 'failed' ? Icons.error_outline : Icons.upload,
                color: t.state == 'done' ? UkoColors.green : t.state == 'failed' ? UkoColors.destructive : UkoColors.yellow,
              ),
              title: Text('Buyer ${t.id}', style: const TextStyle(color: UkoColors.text)),
              subtitle: t.state == 'sending'
                  ? LinearProgressIndicator(value: t.total > 0 ? t.sent / t.total : null)
                  : Text(t.state == 'done' ? 'Sent ${_mb(t.total)}' : 'Stopped at ${_mb(t.sent)} - they can scan again',
                      style: const TextStyle(color: UkoColors.muted)),
            ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => _stop(), child: const Text('Stop selling')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell this video'),
        actions: [
          TextButton(onPressed: () => Nav.push(context, Routes.offlineSales), child: const Text('My sales')),
        ],
      ),
      body: SafeArea(
        child: _record == null
            ? const Center(child: Text('This download was not found', style: TextStyle(color: UkoColors.muted)))
            : ListView(padding: const EdgeInsets.all(16), children: [_offer == null ? _pricing() : _selling()]),
      ),
    );
  }
}
