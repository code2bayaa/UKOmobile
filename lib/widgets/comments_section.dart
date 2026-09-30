// Movies PRD #4: viewers' comments under a movie / series details screen (TMDB and Eden).
// Contract: movies/back-end/user/comments/index.js - POST /comments/{list,add,remove}/android.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/http.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../routes.dart';
import '../services/prefs.dart';
import '../services/profile.dart';
import 'common.dart';
import 'sign_in_required.dart';

/// [type] is "movie" or "tv"; [id] the TMDB id, or the Eden title id when [eden].
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.type, required this.id, this.eden = false});
  final String type;
  final int id;
  final bool eden;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  static const _maxBody = 1000;

  final _body = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false; // posting / deleting
  bool _signedIn = false; // a stored user, as SignInRequired / CreditGate check
  String? _error;

  int _count = 0;
  int _rated = 0;
  num? _average;
  int _page = 1;
  bool _more = false;
  Map<String, dynamic>? _mine;
  String? _username; // the viewer's, from the list reply; null = ask before the first post
  List<Map<String, dynamic>> _comments = [];
  int? _rating; // composer's stars, null = no rating

  Map<String, dynamic> get _title => {'type': widget.type, 'id': widget.id, 'eden': widget.eden};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CommentsSection old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.type != widget.type || old.eden != widget.eden) _start();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final user = await Prefs.user;
    if (!mounted) return;
    setState(() {
      _signedIn = user != null && user.isNotEmpty;
      _loading = true;
      _error = null;
    });
    final reply = await _call(Api.commentsList, {..._title, 'page': 1});
    if (!mounted) return;
    if (reply.data == null) {
      setState(() {
        _loading = false;
        _error = reply.message ?? 'Could not load comments';
      });
      return;
    }
    setState(() {
      _loading = false;
      _apply(reply.data!, prefill: true);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final reply = await _call(Api.commentsList, {..._title, 'page': _page + 1});
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      final data = reply.data;
      if (data == null) {
        showUkoSnack(context, 'Error', reply.message ?? 'Could not load more comments');
        return;
      }
      final known = _comments.map((c) => c['id']).toSet();
      _comments = [
        ..._comments,
        ...asMapList(data['comments']).where((c) => !known.contains(c['id'])),
      ];
      _page = toNum(data['page']).toInt();
      _more = truthy(data['more']);
      _count = toNum(data['count']).toInt();
    });
  }

  Future<void> _post() async {
    final body = _body.text.trim();
    if (body.length < 2) {
      showUkoSnack(context, 'Error', 'Write a comment first');
      return;
    }
    FocusScope.of(context).unfocus();
    // no username on the profile yet: ask for one and send it with the comment - the service saves it
    String? username;
    if (_username == null) {
      username = await _askUsername();
      if (username == null || !mounted) return;
    }
    setState(() => _busy = true);
    Map<String, dynamic> payload() =>
        {..._title, 'body': body, if (_rating != null) 'rating': _rating, if (username != null) 'username': username};
    var reply = await _call(Api.commentsAdd, payload());
    while (mounted && reply.data == null && _usernameCodes.contains(reply.code)) {
      username = await _askUsername(problem: reply.code == 'username_required' ? null : reply.message);
      if (username == null || !mounted) break;
      reply = await _call(Api.commentsAdd, payload());
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (reply.data != null) _apply(reply.data!, prefill: true);
    });
    if (reply.data != null && username != null) ProfileService.clearCache();
    if (reply.data == null && username == null && _usernameCodes.contains(reply.code)) return; // cancelled
    if (reply.data == null) {
      showUkoSnack(context, 'Error', reply.message ?? 'Could not save your comment');
    } else {
      showUkoSnack(context, 'Success', 'Your comment is saved');
    }
  }

  static const _usernameCodes = {'username_required', 'username_taken', 'username_invalid'};

  Future<String?> _askUsername({String? problem}) => askCommentUsername(context, problem: problem);

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UkoColors.gray900,
        title: const Text('Delete your comment?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: UkoColors.destructive)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final reply = await _call(Api.commentsRemove, _title);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (reply.data != null) {
        _apply(reply.data!, prefill: false);
        _body.clear();
        _rating = null;
      }
    });
    if (reply.data == null) showUkoSnack(context, 'Error', reply.message ?? 'Could not remove your comment');
  }

  /// A list-shaped reply (list, add and remove all answer with it).
  void _apply(Map<String, dynamic> data, {required bool prefill}) {
    _count = toNum(data['count']).toInt();
    _rated = toNum(data['rated']).toInt();
    _average = data['average'] == null ? null : toNum(data['average']);
    _page = toNum(data['page']).toInt();
    if (_page < 1) _page = 1;
    _more = truthy(data['more']);
    _comments = asMapList(data['comments']);
    _mine = data['mine'] is Map ? Map<String, dynamic>.from(data['mine'] as Map) : null;
    final username = data['username'];
    _username = username == null || '$username'.isEmpty ? null : '$username';
    final mine = _mine;
    if (prefill && mine != null) {
      _body.text = '${mine['body'] ?? ''}';
      final r = toNum(mine['rating']).toInt();
      _rating = r >= 1 && r <= 5 ? r : null;
    }
  }

  /// POST with the status code kept, so 400/401/409/429 `{status:false, code?, message}` reach the user.
  Future<({Map<String, dynamic>? data, String? message, String? code})> _call(String url, Map<String, dynamic> body) async {
    if (url.isEmpty) return (data: null, message: 'Comments are not configured in this build', code: null);
    final res = await Http.post(url, body);
    if (res == null) return (data: null, message: 'Check your connection and try again', code: null);
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (json is Map && res.statusCode == 200 && truthy(json['status'])) {
      return (data: Map<String, dynamic>.from(json), message: null, code: null);
    }
    final message = json is Map && json['message'] != null ? '${json['message']}' : null;
    final code = json is Map && json['code'] != null ? '${json['code']}' : null;
    return (data: null, message: message ?? 'Something went wrong (${res.statusCode})', code: code);
  }

  void _goSignIn() {
    final settings = ModalRoute.of(context)?.settings;
    final args = settings?.arguments;
    Navigator.of(context).pushNamed(Routes.signIn, arguments: <String, dynamic>{
      if (settings?.name != null) SignInReturn.next: settings!.name,
      SignInReturn.nextParams: args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorBox()
          else ...[
            if (_signedIn) _composer() else _signInPrompt(),
            const SizedBox(height: 16),
            if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No comments yet. Be the first to share what you think.',
                    style: TextStyle(color: UkoColors.gray400)),
              ),
            for (final c in _comments) _CommentTile(comment: c),
            if (_more)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : OutlinedButton(
                          onPressed: _loadMore,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: UkoColors.yellow,
                            side: const BorderSide(color: UkoColors.yellow),
                          ),
                          child: const Text('Load more'),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final avg = _average;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('COMMENTS ($_count)',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white)),
        const Spacer(),
        if (_rated > 0 && avg != null) ...[
          _Stars(value: avg.toDouble(), size: 16),
          const SizedBox(width: 4),
          Text('${avg.toStringAsFixed(1)} ($_rated)',
              style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _errorBox() => Column(
        children: [
          Text(_error ?? '', style: const TextStyle(color: UkoColors.gray400)),
          TextButton(onPressed: _start, child: const Text('Try again')),
        ],
      );

  Widget _signInPrompt() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: UkoColors.gray900,
          border: Border.all(color: UkoColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text('Sign in to comment and rate this title.', style: TextStyle(color: Colors.white)),
            ),
            FilledButton(
              onPressed: _goSignIn,
              style: FilledButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );

  Widget _composer() {
    final mine = _mine;
    final hidden = mine != null && mine['status'] == 'hidden';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UkoColors.gray900,
        border: Border.all(color: UkoColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hidden)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: UkoColors.destructive.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Your comment has been hidden by moderators. Only you can see it here; editing it keeps it hidden.',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          if (_username != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Posting as $_username', style: const TextStyle(color: UkoColors.gray400, fontSize: 12)),
            ),
          Row(
            children: [
              Text(mine == null ? 'Your rating' : 'Your comment',
                  style: const TextStyle(color: UkoColors.gray400, fontSize: 12)),
              const SizedBox(width: 8),
              for (var i = 1; i <= 5; i++)
                InkResponse(
                  radius: 18,
                  onTap: _busy ? null : () => setState(() => _rating = _rating == i ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      (_rating ?? 0) >= i ? Icons.star : Icons.star_border,
                      color: UkoColors.yellow,
                      size: 26,
                    ),
                  ),
                ),
              if (_rating != null)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _rating = null),
                  child: const Text('clear', style: TextStyle(color: UkoColors.gray400, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            maxLength: _maxBody,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'What did you think?',
              counterStyle: TextStyle(color: UkoColors.gray400),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: UkoColors.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: UkoColors.yellow)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (mine != null)
                TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Delete', style: TextStyle(color: UkoColors.destructive)),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _post,
                style: FilledButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(mine == null ? 'Post' : 'Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final rating = toNum(c['rating']).toInt();
    final mine = truthy(c['mine']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UkoColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('${c['author'] ?? 'UKO viewer'}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: mine ? UkoColors.yellow : Colors.white, fontWeight: FontWeight.bold)),
              ),
              if (mine) const Text(' (you)', style: TextStyle(color: UkoColors.gray400, fontSize: 12)),
              const SizedBox(width: 8),
              if (rating >= 1 && rating <= 5) _Stars(value: rating.toDouble(), size: 13),
              const Spacer(),
              Text(_when(c['created_at']), style: const TextStyle(color: UkoColors.gray400, fontSize: 11)),
              if (truthy(c['edited']))
                const Text(' · edited', style: TextStyle(color: UkoColors.gray400, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${c['body'] ?? ''}', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  static String _when(dynamic raw) => commentWhen(raw);
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.size = 14});
  final double value; // 0..5, halves shown
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i ? Icons.star : (value >= i - 0.5 ? Icons.star_half : Icons.star_border),
            color: UkoColors.yellow,
            size: size,
          ),
      ],
    );
  }
}

/// Asks for the unique username comments are posted under; null when cancelled. Shared by the title comments
/// here and the mini-series reel comments (widgets/reel_comments.dart, PRD #26).
Future<String?> askCommentUsername(BuildContext context, {String? problem}) {
  final field = TextEditingController();
  String? error = problem;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        void submit() {
          final p = usernameProblem(field.text);
          if (p != null) {
            setDialog(() => error = p);
            return;
          }
          Navigator.of(ctx).pop(cleanUsername(field.text));
        }

        return AlertDialog(
          backgroundColor: UkoColors.gray900,
          title: const Text('Choose a username', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Your comments are shown under your username. It's saved on your profile and must be unique.",
                style: TextStyle(color: UkoColors.gray400, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: field,
                autofocus: true,
                autocorrect: false,
                maxLength: 21,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: 'e.g. movie_fan254',
                  errorText: error,
                  errorMaxLines: 3,
                  counterStyle: const TextStyle(color: UkoColors.gray400),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: UkoColors.border)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: UkoColors.yellow)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: submit,
              style: FilledButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
              child: const Text('Save and post'),
            ),
          ],
        );
      },
    ),
  );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "just now", "5m", "3h", "4d", else "12 Mar" / "12 Mar 2025" - shared with the reel comments.
String commentWhen(dynamic raw) {
  final at = raw == null ? null : DateTime.tryParse('$raw')?.toLocal();
  if (at == null) return '';
  final now = DateTime.now();
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final day = '${at.day} ${_months[at.month - 1]}';
  return at.year == now.year ? day : '$day ${at.year}';
}
