// Port of mobile/app/offline/downloads.tsx
// The screen is just the downloaded movies. Each one can be watched, sold offline to a nearby UKOapp user
// (movies PRD #10 - sell.dart) or removed. Buying from another phone and the sales balance sit in the app bar.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import 'file_system.dart';

class OfflineDownloadsScreen extends StatefulWidget {
  const OfflineDownloadsScreen({super.key});

  @override
  State<OfflineDownloadsScreen> createState() => _OfflineDownloadsScreenState();
}

class _OfflineDownloadsScreenState extends State<OfflineDownloadsScreen> {
  List<Map<String, dynamic>> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      final data = await OfflineStore.listVideos();
      if (mounted) setState(() => _movies = [...data]);
    } catch (e) {
      debugPrint('listVideos error $e');
      if (mounted) setState(() => _movies = []);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(String key, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('$title will be deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove', style: TextStyle(color: UkoColors.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OfflineStore.deleteVideo(key);
    } catch (e) {
      debugPrint('deleteVideo error $e');
    }
    _loadVideos();
  }

  Widget _image(dynamic path) {
    const fallback = 'assets/images/alt.webp';
    if (path is! String || path.isEmpty) return Image.asset(fallback, fit: BoxFit.cover);
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, st) => Image.asset(fallback, fit: BoxFit.cover),
    );
  }

  Widget _renderDownload(Map<String, dynamic> item) {
    final data = item['data'] is Map ? Map<String, dynamic>.from(item['data'] as Map) : <String, dynamic>{};
    final title = '${or([data['title'], data['original_title'], data['name'], data['original_name']]) ?? item['name']}';
    final va = double.tryParse('${data['vote_average']}');
    final year = '${data['release_date'] ?? data['first_air_date'] ?? ''}'.split('-').first;
    final key = '${item['name']}';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: UkoColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UkoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 110, height: 165, child: _image(item['image'])),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: ukoHeading(fontSize: 17)),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _remove(key, title),
                          icon: const Icon(Icons.delete_outline, color: UkoColors.muted, size: 20),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (va != null) ...[
                          const Icon(Icons.star, size: 16, color: UkoColors.yellow),
                          Text(' ${va.toStringAsFixed(1)}', style: const TextStyle(color: UkoColors.yellow)),
                          const SizedBox(width: 10),
                        ],
                        if (year.isNotEmpty) Text(year, style: const TextStyle(color: UkoColors.muted)),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UkoColors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => Nav.push(context, Routes.offlinePlay, {
                              'video': item['video'],
                              'subtitle': item['subtitle'],
                              'image': item['image'],
                              'name': data['title'] ?? title,
                            }),
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Watch'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        //PRD #10: sell this download to a nearby UKOapp user - price, QR, M-PESA, 70% to the seller
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: UkoColors.yellow,
                              side: const BorderSide(color: UkoColors.yellow),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => Nav.push(context, Routes.offlineSell, {'key': key}),
                            icon: const Icon(Icons.sell_outlined, size: 18),
                            label: const Text('Sell offline'),
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

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No downloaded movies yet.\nDownload one from its player, or get one from a nearby phone with the '
            'scan button above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: UkoColors.muted),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UkoColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          //PRD #10: get a video from a nearby phone, and the seller's balance
          IconButton(
            tooltip: 'Buy from a phone',
            onPressed: () async {
              await Nav.push(context, Routes.offlineBuy);
              _loadVideos();
            },
            icon: const Icon(Icons.qr_code_scanner, color: UkoColors.yellow),
          ),
          IconButton(
            tooltip: 'My sales',
            onPressed: () => Nav.push(context, Routes.offlineSales),
            icon: const Icon(Icons.account_balance_wallet_outlined, color: UkoColors.yellow),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _movies.isEmpty
                ? _empty()
                : RefreshIndicator(
                    onRefresh: _loadVideos,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _movies.length,
                      itemBuilder: (context, i) => _renderDownload(_movies[i]),
                    ),
                  ),
      ),
    );
  }
}
