// Buy a video from a nearby UKOapp user (movies PRD #10), the buyer's screen.
// Scan the seller's QR -> check the offer with the seller's phone (same Wi-Fi / their hotspot) and with UKO ->
// pay by M-PESA prompt -> once Safaricom confirms it, UKO hands this app a ticket and the seller's phone sends the
// video, which lands in Downloads like any other.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/profile.dart';
import '../../services/sales_api.dart';
import 'file_system.dart';

enum _Stage { scan, offer, paying, receiving, done }

class BuyVideoScreen extends StatefulWidget {
  const BuyVideoScreen({super.key});

  @override
  State<BuyVideoScreen> createState() => _BuyVideoScreenState();
}

class _BuyVideoScreenState extends State<BuyVideoScreen> {
  _Stage _stage = _Stage.scan;
  final _phone = TextEditingController();
  final MobileScannerController _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handlingScan = false;

  String? _code;
  String? _base; // http://<seller ip>:<port>
  Map<String, dynamic>? _sellerOffer; // from the seller's phone: name, data, format, size
  Map<String, dynamic>? _ukoOffer; // from UKO: price, seller, name
  int? _saleId;
  String? _ticket;
  String _status = '';
  String? _error;
  int _percent = 0;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    ProfileService.fetch().then((p) {
      if (mounted && _phone.text.isEmpty && p?.telephone != null) _phone.text = p!.telephone!;
    });
  }

  @override
  void dispose() {
    _cancelled = true;
    _scanner.dispose();
    _phone.dispose();
    super.dispose();
  }

  // ---- 1. scan
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handlingScan || _stage != _Stage.scan) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) return;
    Map<String, dynamic>? payload;
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['t'] == 'uko-sale') payload = Map<String, dynamic>.from(j);
    } catch (_) {}
    if (payload == null) {
      setState(() => _error = 'That is not a UKO sale code');
      return;
    }
    _handlingScan = true;
    setState(() {
      _error = null;
      _status = 'Finding the seller\'s phone...';
    });
    await _reachSeller(payload);
    _handlingScan = false;
  }

  // ---- 2. the offer, from the seller's phone (the file is there) and from UKO (the price that is charged)
  Future<void> _reachSeller(Map<String, dynamic> payload) async {
    final code = '${payload['code'] ?? ''}';
    final port = payload['port'];
    final hosts = payload['hosts'] is List ? (payload['hosts'] as List).map((h) => '$h').toList() : <String>[];
    for (final host in hosts) {
      final base = 'http://$host:$port';
      try {
        final res = await http.get(Uri.parse('$base/uko-sale/offer?code=$code')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body);
          if (j is Map && j['status'] == true) {
            final uko = await SalesApi.view(code);
            if (!mounted) return;
            if (uko['status'] != true) {
              setState(() => _error = '${uko['message'] ?? 'This offer has ended'}');
              return;
            }
            if (uko['mine'] == true) {
              setState(() => _error = 'This is your own video');
              return;
            }
            setState(() {
              _code = code;
              _base = base;
              _sellerOffer = Map<String, dynamic>.from(j);
              _ukoOffer = Map<String, dynamic>.from(uko['offer'] as Map);
              _stage = _Stage.offer;
              _status = '';
            });
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _status = '';
        _error = 'Could not reach the seller\'s phone. Connect to the same Wi-Fi, or to the seller\'s hotspot, and scan again.';
      });
    }
  }

  // ---- 3. pay: M-PESA prompt, then wait for Safaricom's answer through UKO
  Future<void> _pay() async {
    final code = _code;
    if (code == null) return;
    setState(() {
      _stage = _Stage.paying;
      _error = null;
      _status = 'Sending the M-PESA prompt...';
    });
    final res = await SalesApi.pay(code, _phone.text.trim());
    if (!mounted) return;
    if (res['status'] != true) {
      setState(() {
        _stage = _Stage.offer;
        _error = '${res['message'] ?? 'Could not start the payment'}';
      });
      return;
    }
    _saleId = int.tryParse('${res['sale_id']}');
    if (res['state'] == 'paid' && res['ticket'] != null) {
      _ticket = '${res['ticket']}';
      return _receive();
    }
    setState(() => _status = '${res['message'] ?? 'Check your phone for the M-PESA prompt'} - enter your PIN');
    // Daraja answers within a couple of minutes; poll UKO, which asks Safaricom
    for (var i = 0; i < 45 && !_cancelled; i++) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (_cancelled || !mounted || _saleId == null) return;
      final c = await SalesApi.confirm(_saleId!);
      if (!mounted) return;
      if (c['state'] == 'paid' && c['ticket'] != null) {
        _ticket = '${c['ticket']}';
        return _receive();
      }
      if (c['state'] == 'failed') {
        setState(() {
          _stage = _Stage.offer;
          _error = '${c['message'] ?? 'The payment did not go through'}';
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _stage = _Stage.offer;
        _error = 'No answer from M-PESA yet. If you paid, tap Pay again - you will not be charged twice.';
      });
    }
  }

  // ---- 4. receive the file from the seller's phone and add it to Downloads
  Future<void> _receive() async {
    final base = _base, code = _code, ticket = _ticket, offer = _sellerOffer;
    if (base == null || code == null || ticket == null || offer == null) return;
    setState(() {
      _stage = _Stage.receiving;
      _percent = 0;
      _status = 'Paid. Receiving the video from the seller\'s phone...';
    });
    final key = '${offer['name'] ?? 'sale-$code'}';
    final format = '${offer['format'] ?? 'mp4'}';
    final q = 'code=$code&ticket=${Uri.encodeQueryComponent(ticket)}';
    try {
      final video = await OfflineStore.downloadFile('video', '$base/uko-sale/video?$q', key, format: format,
          onProgress: (p) {
        if (mounted) setState(() => _percent = p);
      });
      if (video == null) throw Exception('the seller\'s phone did not send the video');
      String? image, subtitle;
      if (offer['has_image'] == true) {
        image = await OfflineStore.downloadFile('image', '$base/uko-sale/image?code=$code', key).catchError((_) => null);
      }
      if (offer['has_subtitle'] == true) {
        subtitle = await OfflineStore.downloadFile('subtitle', '$base/uko-sale/subtitle?$q', key).catchError((_) => null);
      }
      final saved = await OfflineStore.saveVideo(video, subtitle, image, offer['data'], key, format);
      if (!saved.status) throw Exception(saved.error ?? 'could not save');
      if (_saleId != null) await SalesApi.delivered(_saleId!);
      if (mounted) {
        setState(() {
          _stage = _Stage.done;
          _status = 'Saved to your downloads.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.offer;
          _error = 'The transfer stopped ($e). You have paid - stay on the seller\'s network and tap Receive again.';
        });
      }
    }
  }

  String get _title {
    final data = _sellerOffer?['data'] is Map ? Map<String, dynamic>.from(_sellerOffer!['data'] as Map) : <String, dynamic>{};
    return '${or([_ukoOffer?['name'], data['title'], data['name']]) ?? 'UKO video'}';
  }

  String _mb(dynamic bytes) => '${((int.tryParse('$bytes') ?? 0) / (1024 * 1024)).toStringAsFixed(0)} MB';

  Widget _scanView() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Connect to the seller\'s Wi-Fi or hotspot, then scan the code on their "Sell this video" screen.',
              style: TextStyle(color: UkoColors.text),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(controller: _scanner, onDetect: _onDetect),
            ),
          ),
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_status, style: const TextStyle(color: UkoColors.yellow))),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: UkoColors.destructive))),
        ],
      );

  Widget _offerView() {
    final receivePaid = _ticket != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_base != null && _sellerOffer?['has_image'] == true)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network('$_base/uko-sale/image?code=$_code', height: 220, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 12),
        Text(_title, style: ukoHeading(fontSize: 22)),
        const SizedBox(height: 4),
        Text('From ${_ukoOffer?['seller'] ?? 'a UKO seller'}  ·  ${_mb(_sellerOffer?['size'])}',
            style: const TextStyle(color: UkoColors.muted)),
        const SizedBox(height: 8),
        Text('KSh ${_ukoOffer?['price']}', style: const TextStyle(color: UkoColors.yellow, fontSize: 26, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (!receivePaid) ...[
          const Text('M-PESA number to pay from', style: TextStyle(color: UkoColors.muted)),
          const SizedBox(height: 6),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '0712 345 678')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: UkoColors.destructive))),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: receivePaid ? _receive : _pay,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(receivePaid ? 'Receive again' : 'Pay KSh ${_ukoOffer?['price']} with M-PESA'),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _stage = _Stage.scan;
            _error = null;
            _ticket = null;
            _saleId = null;
          }),
          child: const Text('Scan a different code'),
        ),
      ],
    );
  }

  Widget _progressView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_title, style: ukoHeading(fontSize: 22), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_stage == _Stage.receiving) ...[
              LinearProgressIndicator(value: _percent / 100),
              const SizedBox(height: 8),
              Text('$_percent%', style: const TextStyle(color: UkoColors.yellow)),
            ] else if (_stage == _Stage.paying)
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: UkoColors.text), textAlign: TextAlign.center),
            if (_stage == _Stage.done) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Nav.replace(context, Routes.offlineDownloads),
                child: const Text('Go to downloads'),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy from a phone')),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.scan => _scanView(),
          _Stage.offer => _offerView(),
          _ => _progressView(),
        },
      ),
    );
  }
}
