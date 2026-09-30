import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../services/rewarded_ad.dart';

/// Earn credits by watching UKOshop ads and Google rewarded ads (movies PRD #15) - the phone version of web-app
/// components/earn.jsx.
/// Every 5 ads = 50 credits. The server opens and closes each ad (movies/back-end/user/earn/index.js): Next only
/// counts after the minimum time and after the description was read or the video watched to the end. The question
/// about the ad is optional - a right answer earns the bonus. A Google ad (AdMob, services/rewarded_ad.dart) counts once Google's
/// own server-side verification callback reached the server - the app only waits for it. Nothing here decides
/// the reward.
class EarnAdsScreen extends StatefulWidget {
  const EarnAdsScreen({super.key});

  @override
  State<EarnAdsScreen> createState() => _EarnAdsScreenState();
}

class _Ad {
  _Ad(this.data, this.impressionId, this.minSeconds, this.quiz) : started = DateTime.now();
  final Map data;
  final int impressionId;
  final int minSeconds;
  final Map? quiz;
  final DateTime started;
  bool get isVideo => data['video'] is String && (data['video'] as String).isNotEmpty;
}

class _EarnAdsScreenState extends State<EarnAdsScreen> {
  Map? _progress;
  List<Map> _queue = [];
  String? _admobUnit; // null: the server has no Google ads for phones
  String? _error;
  bool _needsSignIn = false;
  bool _loading = true;
  bool _busy = false;

  _Ad? _ad;
  bool _scrolled = false;
  bool _watched = false;
  int _interactions = 0;
  String? _answer;
  int _elapsed = 0;
  Timer? _ticker;
  final ScrollController _desc = ScrollController();
  final ScrollController _page = ScrollController();
  VideoPlayerController? _video;
  Duration _maxWatched = Duration.zero;

  @override
  void initState() {
    super.initState();
    _desc.addListener(_onScroll);
    _loadFeed();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _desc.dispose();
    _page.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final token = await Prefs.token;
    return {...Http.jsonHeaders, if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
  }

  /// The earn routes answer 401 / 403 / 429 with a message the screen shows, so the status code is kept.
  Future<Map<String, dynamic>> _call(String path, [Map<String, dynamic>? body]) async {
    final url = '${Api.earn}$path';
    if (Api.earn.isEmpty) return {'code': 0, 'message': 'Earning is not set up in this build'};
    try {
      final headers = await _headers();
      final res = body == null
          ? await http.get(Uri.parse(url), headers: headers)
          : await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return {'code': res.statusCode, ...data};
    } catch (e) {
      debugPrint('earn $path failed: $e');
      return {'code': 0, 'message': 'No connection - try again'};
    }
  }

  Future<void> _loadFeed() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _call('/feed');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['code'] == 401) {
        _needsSignIn = true;
      } else if (res['status'] != true) {
        _error = '${res['message'] ?? 'Could not load ads'}';
      } else {
        _progress = res['progress'] as Map?;
        _queue = [for (final a in (res['ukoshop'] as List? ?? const [])) if (a is Map) a];
        final admob = res['admob'];
        _admobUnit = admob is Map && admob['unit'] is String ? admob['unit'] as String : null;
        if (_queue.isEmpty && _admobUnit == null && res['shop_error'] != null) _error = '${res['shop_error']}';
      }
    });
  }

  Future<void> _nextAd() async {
    _ticker?.cancel();
    await _video?.dispose();
    _video = null;
    setState(() => _ad = null);
    if (_queue.isEmpty) return _loadFeed();
    final next = _queue.removeAt(0);
    final isVideo = next['video'] is String && (next['video'] as String).isNotEmpty;
    final res = await _call('/start', {'provider': 'ukoshop', 'kind': isVideo ? 'video' : 'image', 'ad_ref': '${next['id']}'});
    if (!mounted) return;
    if (res['status'] != true) {
      _snack('${res['message'] ?? 'Could not start the ad'}');
      return;
    }
    final ad = _Ad(next, (res['impression_id'] as num).toInt(), (res['min_seconds'] as num?)?.toInt() ?? 31, res['quiz'] as Map?);
    setState(() {
      _ad = ad;
      _scrolled = false;
      _watched = false;
      _interactions = 0;
      _answer = null;
      _elapsed = 0;
      _maxWatched = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _ad == null) return;
      final s = DateTime.now().difference(ad.started).inSeconds;
      if (s != _elapsed) setState(() => _elapsed = s);
    });
    if (ad.isVideo) {
      final c = VideoPlayerController.networkUrl(Uri.parse(ad.data['video'] as String));
      _video = c;
      c.addListener(_onVideo);
      try {
        await c.initialize();
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('earn ad video failed: $e');
      }
    } else {
      // a short description needs no scrolling - it is read once it is on screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_desc.hasClients) return;
        if (_desc.position.maxScrollExtent <= 4) setState(() => _scrolled = true);
      });
    }
  }

  /// A Google rewarded ad: the server opens the impression, AdMob shows the ad, and then the server is asked
  /// until Google's verification callback has arrived (usually a few seconds after the ad closes).
  Future<void> _watchGoogle() async {
    if (_busy || _ad != null) return;
    setState(() => _busy = true);
    try {
      final start = await _call('/start', {'provider': 'google', 'kind': 'rewarded'});
      if (!mounted) return;
      final admob = start['admob'];
      if (start['status'] != true || admob is! Map) {
        _snack('${start['message'] ?? 'Could not start a Google ad'}');
        return;
      }
      final shown = await RewardedAds.show(
        unit: '${admob['unit']}',
        customData: '${admob['custom_data']}',
        userId: '${admob['user_id']}',
      );
      if (!mounted) return;
      if (!shown.earned) {
        _snack(shown.error ?? 'Watch the whole ad to earn from it');
        return;
      }
      // Google's callback normally lands within seconds; the next ad started closes this one, so wait up to 30s
      for (var attempt = 0; attempt < 15; attempt++) {
        final res = await _call('/complete', {
          'impression_id': (start['impression_id'] as num).toInt(),
          'proof': {'granted': true, 'next_clicked': true},
        });
        if (!mounted) return;
        if (res['code'] == 202 && res['pending'] == true) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if (res['status'] != true) {
          _snack('${res['message'] ?? 'That ad did not count'}');
          return;
        }
        setState(() => _progress = res['progress'] as Map? ?? _progress);
        final rewarded = res['rewarded'];
        _snack(rewarded is Map ? '+${rewarded['credits']} credits added to your balance' : 'Google ad counted');
        return;
      }
      _snack("Google didn't confirm that ad in time, so it didn't count");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onScroll() {
    if (!_desc.hasClients || _scrolled) return;
    if (_desc.position.pixels >= _desc.position.maxScrollExtent - 4) setState(() => _scrolled = true);
  }

  void _onVideo() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    // normal speed only, and no jumping around the timeline, forward or back
    if (c.value.playbackSpeed != 1.0) c.setPlaybackSpeed(1.0);
    if (pos > _maxWatched + const Duration(seconds: 2) || pos < _maxWatched - const Duration(seconds: 2)) {
      c.seekTo(_maxWatched);
      return;
    }
    if (pos > _maxWatched) _maxWatched = pos;
    if (!_watched && c.value.duration > Duration.zero && pos >= c.value.duration - const Duration(milliseconds: 300)) {
      setState(() => _watched = true);
    }
  }

  bool get _engaged {
    final ad = _ad;
    if (ad == null) return false;
    // the question is optional - Next only waits for the ad itself
    return ad.isVideo ? _watched : _scrolled;
  }

  int get _baseCredits => ((_progress?['credits_per_ad'] as Map?)?['ukoshop'] as num?)?.toInt() ?? 10;
  int get _quizCredits => ((_progress?['credits_per_ad'] as Map?)?['ukoshop_quiz'] as num?)?.toInt() ?? 15;

  Future<void> _finish() async {
    final ad = _ad;
    if (ad == null || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await _call('/complete', {
        'impression_id': ad.impressionId,
        if (_answer != null) 'answer': _answer,
        'proof': {
          'scrolled_to_end': _scrolled,
          'watched_to_end': _watched,
          'next_clicked': true,
          'interactions': _interactions,
          'dwell_ms': DateTime.now().difference(ad.started).inMilliseconds,
          if (ad.isVideo) 'video_seconds': _maxWatched.inMilliseconds / 1000,
        },
      });
      if (!mounted) return;
      if (res['status'] != true) {
        _snack('${res['message'] ?? 'That ad did not count'}');
        return;
      }
      setState(() => _progress = res['progress'] as Map? ?? _progress);
      final rewarded = res['rewarded'];
      if (rewarded is Map) {
        _snack('+${rewarded['credits']} credits added to your balance');
      } else if (res['counted'] != true && res['reason'] != null) {
        _snack('${res['reason']}');
      }
      await _nextAd();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UkoColors.background,
      appBar: AppBar(title: const Text('Watch ads, earn credits')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _ad == null) return const Center(child: CircularProgressIndicator());
    if (_needsSignIn) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sign in to earn credits'),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => Nav.push(context, Routes.signIn), child: const Text('Sign in')),
        ]),
      );
    }
    final p = _progress;
    // the whole ad scrolls with a visible bar (like the web page), with room below Next above the tab bar
    return Scrollbar(
      controller: _page,
      child: ListView(controller: _page, padding: const EdgeInsets.fromLTRB(16, 16, 16, 48), children: [
        Text(
          'Each UKOshop ad earns ${(p?['credits_per_ad'] as Map?)?['ukoshop'] ?? 10} credits - '
          '${(p?['credits_per_ad'] as Map?)?['ukoshop_quiz'] ?? 15} when you answer its question right. '
          'Credits are added every ${p?['per_reward'] ?? 5} ads. Read each ad or watch its video to the end, then press Next.',
          style: const TextStyle(color: UkoColors.muted),
        ),
        const SizedBox(height: 12),
        if (p != null) _progressBar(p),
        const SizedBox(height: 16),
        if (_error != null && _ad == null)
          Text(_error!, style: const TextStyle(color: UkoColors.muted))
        else if (_ad == null)
          Center(
            child: _queue.isEmpty && _admobUnit == null
                ? const Text('No ads right now - check back later.', style: TextStyle(color: UkoColors.muted))
                : Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    if (_queue.isNotEmpty)
                      ElevatedButton(
                        onPressed: _busy ? null : _nextAd,
                        child: Text(((p?['counted'] as num?) ?? 0) > 0 ? 'Continue with UKOshop ads' : 'Watch UKOshop ads'),
                      ),
                    if (_admobUnit != null)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _watchGoogle,
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(_busy ? 'Waiting for Google…' : 'Watch a Google ad'),
                      ),
                  ]),
          )
        else
          _adCard(_ad!),
      ]),
    );
  }

  Widget _progressBar(Map p) {
    final counted = (p['counted'] as num?)?.toInt() ?? 0;
    final per = (p['per_reward'] as num?)?.toInt() ?? 5;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$counted of $per ads', style: const TextStyle(fontSize: 13)),
        Text('${(p['credits_today'] as num?)?.toInt() ?? 0} credits today',
            style: const TextStyle(fontSize: 13)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: per > 0 ? counted / per : 0,
          minHeight: 8,
          backgroundColor: UkoColors.border,
          color: UkoColors.yellow,
        ),
      ),
    ]);
  }

  Widget _adCard(_Ad ad) {
    final left = (ad.minSeconds - _elapsed).clamp(0, ad.minSeconds);
    final seen = ad.isVideo ? _watched : _scrolled;
    final status = left > 0
        ? '${left}s'
        : !seen
            ? (ad.isVideo ? 'Watch to the end' : 'Scroll to the end of the description')
            : ad.quiz != null && _answer == null
                ? 'Ready - answer for +${_quizCredits - _baseCredits} more'
                : 'Ready';
    final images = ad.data['images'];
    final image = images is List && images.isNotEmpty ? '${images.first}' : null;
    final video = _video;
    final amount = ad.data['amount'];
    return GestureDetector(
      onTap: () => _interactions++,
      child: Container(
        decoration: BoxDecoration(
          color: UkoColors.card,
          border: Border.all(color: UkoColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (ad.isVideo)
            AspectRatio(
              aspectRatio: video != null && video.value.isInitialized ? video.value.aspectRatio : 16 / 9,
              child: video != null && video.value.isInitialized
                  ? Stack(alignment: Alignment.center, children: [
                      VideoPlayer(video),
                      if (!video.value.isPlaying)
                        IconButton(
                          iconSize: 56,
                          icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                          onPressed: () => setState(() => video.play()),
                        ),
                    ])
                  : const Center(child: CircularProgressIndicator()),
            )
          else if (image != null)
            Image.network(image, height: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('UKOSHOP AD', style: TextStyle(color: UkoColors.yellow, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text('${ad.data['title'] ?? ''}', style: ukoHeading(fontSize: 18)),
              if (amount is num && amount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('KSh ${_thousands(amount)}', style: const TextStyle(color: UkoColors.text)),
                ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: Scrollbar(
                  controller: _desc,
                  child: SingleChildScrollView(
                    controller: _desc,
                    child: Text('${ad.data['description'] ?? ''}', style: const TextStyle(color: UkoColors.muted)),
                  ),
                ),
              ),
              if (ad.quiz != null) ...[
                const SizedBox(height: 14),
                Text('${ad.quiz!['question']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                RadioGroup<String>(
                  groupValue: _answer,
                  onChanged: (v) => setState(() => _answer = v),
                  child: Column(children: [
                    for (final o in (ad.quiz!['options'] as List? ?? const []))
                      if (o is Map)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: '${o['id']}',
                          title: Text('${o['label']}'),
                        ),
                  ]),
                ),
                Text('Optional - answer right for $_quizCredits credits, or skip it and press Next for $_baseCredits.',
                    style: TextStyle(color: UkoColors.muted, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(status, style: const TextStyle(color: UkoColors.muted, fontSize: 12))),
                ElevatedButton(
                  onPressed: _busy || left > 0 || !_engaged ? null : _finish,
                  child: Text(_busy ? '…' : 'Next'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _thousands(num n) =>
      n.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
