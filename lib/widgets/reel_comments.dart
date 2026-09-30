// Movies PRD #26: likes and comments (with replies) on Eden mini-series reels, Instagram-reels style - the
// phone version of web-app components/eden/reels.jsx. Contract: movies/back-end/user/reels/index.js,
// POST /reels/{stats,like,comments,comment,comment/remove}/android (reads need no account).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/http.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../routes.dart';
import '../services/profile.dart';
import 'comments_section.dart';
import 'common.dart';

const _maxBody = 500;
const _usernameCodes = {'username_required', 'username_taken', 'username_invalid'};

typedef ReelReply = ({Map<String, dynamic>? data, String? message, String? code, int status});

class ReelsApi {
  ReelsApi._();

  static Future<ReelReply> post(String route, Map<String, dynamic> body) async {
    final url = Api.reels(route);
    if (url.isEmpty) return (data: null, message: 'Reels are not configured in this build', code: null, status: 0);
    final res = await Http.post(url, body);
    if (res == null) return (data: null, message: 'Check your connection and try again', code: null, status: 0);
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (json is Map && res.statusCode == 200 && truthy(json['status'])) {
      return (data: Map<String, dynamic>.from(json), message: null, code: null, status: 200);
    }
    return (
      data: null,
      message: json is Map && json['message'] != null ? '${json['message']}' : 'Something went wrong (${res.statusCode})',
      code: json is Map && json['code'] != null ? '${json['code']}' : null,
      status: res.statusCode,
    );
  }

  /// likes / comments / liked for up to 50 reel keys at a time
  static Future<Map<String, Map<String, dynamic>>> stats(List<String> keys) async {
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < keys.length; i += 50) {
      final reply = await post('stats', {'keys': keys.sublist(i, (i + 50).clamp(0, keys.length))});
      final stats = reply.data?['stats'];
      if (stats is Map) {
        stats.forEach((k, v) {
          if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
        });
      }
    }
    return out;
  }
}

/// 1234 -> "1.2k", 12345 -> "12k"
String reelCount(dynamic n) {
  final v = toNum(n).toInt();
  if (v >= 10000) return '${(v / 1000).round()}k';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return '$v';
}

void _signInPrompt(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Sign in to $what'),
      action: SnackBarAction(label: 'Sign in', onPressed: () => Nav.push(context, Routes.signIn)),
    ));
}

/// The like + comment buttons at the bottom of a reel tile. [stat] is {likes, comments, liked};
/// [onChange] merges a change into it.
class ReelActions extends StatefulWidget {
  const ReelActions({super.key, required this.reelKey, required this.stat, required this.onChange, required this.onComments});
  final String reelKey;
  final Map<String, dynamic> stat;
  final void Function(Map<String, dynamic> change) onChange;
  final VoidCallback onComments;

  @override
  State<ReelActions> createState() => _ReelActionsState();
}

class _ReelActionsState extends State<ReelActions> {
  bool _busy = false;

  Future<void> _like() async {
    if (_busy) return;
    final liked = truthy(widget.stat['liked']);
    final likes = toNum(widget.stat['likes']).toInt();
    setState(() => _busy = true);
    // show the tap at once; the reply has the real count
    widget.onChange({'liked': !liked, 'likes': (likes + (liked ? -1 : 1)).clamp(0, 1 << 31)});
    final reply = await ReelsApi.post('like', {'key': widget.reelKey});
    if (!mounted) return;
    setState(() => _busy = false);
    final data = reply.data;
    if (data != null) {
      widget.onChange({'liked': truthy(data['liked']), 'likes': toNum(data['likes']).toInt()});
      return;
    }
    widget.onChange({'liked': liked, 'likes': likes});
    if (reply.status == 401) {
      _signInPrompt(context, 'like reels');
    } else {
      showUkoSnack(context, 'Error', reply.message ?? 'Could not save your like');
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = truthy(widget.stat['liked']);
    return Row(children: [
      _action(
        icon: liked ? Icons.favorite : Icons.favorite_border,
        color: liked ? const Color(0xFFEF4444) : Colors.white,
        label: reelCount(widget.stat['likes']),
        semantics: liked ? 'Unlike' : 'Like',
        onTap: _like,
      ),
      const SizedBox(width: 16),
      _action(
        icon: Icons.mode_comment_outlined,
        color: Colors.white,
        label: reelCount(widget.stat['comments']),
        semantics: 'Comments',
        onTap: widget.onComments,
      ),
    ]);
  }

  Widget _action({required IconData icon, required Color color, required String label, required String semantics, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: semantics,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

/// Opens the comments of one reel in a bottom sheet; [onCount] gets the total whenever it is known.
Future<void> showReelComments(BuildContext context, {required String reelKey, required String name, required void Function(int count) onCount}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: UkoColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: _ReelCommentsSheet(reelKey: reelKey, name: name, onCount: onCount),
      ),
    ),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({required this.reelKey, required this.name, required this.onCount});
  final String reelKey;
  final String name;
  final void Function(int count) onCount;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final _body = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _comments = [];
  Map<String, dynamic>? _data; // the latest page reply
  String? _error;
  bool _busy = false;
  Map<String, dynamic>? _replyTo;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _show(ReelReply reply, {bool append = false}) {
    final data = reply.data;
    if (data == null) return false;
    setState(() {
      _data = data;
      _error = null;
      final page = asMapList(data['comments']);
      if (append) {
        final known = _comments.map((c) => c['id']).toSet();
        _comments = [..._comments, ...page.where((c) => !known.contains(c['id']))];
      } else {
        _comments = page;
      }
    });
    if (!append) widget.onCount(toNum(data['count']).toInt());
    return true;
  }

  Future<void> _reload() async {
    final reply = await ReelsApi.post('comments', {'key': widget.reelKey, 'page': 1});
    if (!mounted) return;
    if (!_show(reply)) setState(() => _error = reply.message ?? 'Comments could not load.');
  }

  Future<void> _more() async {
    setState(() => _busy = true);
    final reply = await ReelsApi.post('comments', {'key': widget.reelKey, 'page': toNum(_data?['page']).toInt() + 1});
    if (!mounted) return;
    setState(() => _busy = false);
    _show(reply, append: true);
  }

  void _reply(Map<String, dynamic> comment) {
    setState(() => _replyTo = comment);
    if (_body.text.trim().isEmpty) {
      _body.text = '@${comment['author']} ';
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
    }
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.isEmpty || _busy) return;
    String? username;
    if (_data?['username'] == null) {
      username = await askCommentUsername(context);
      if (username == null || !mounted) return;
    }
    setState(() => _busy = true);
    Map<String, dynamic> payload() => {
          'key': widget.reelKey,
          'body': text,
          if (_replyTo != null) 'parent': _replyTo!['id'],
          if (username != null) 'username': username,
        };
    var reply = await ReelsApi.post('comment', payload());
    while (reply.data == null && _usernameCodes.contains(reply.code)) {
      if (!mounted) return;
      username = await askCommentUsername(context, problem: reply.code == 'username_required' ? null : reply.message);
      if (username == null || !mounted) break;
      reply = await ReelsApi.post('comment', payload());
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (_show(reply)) {
      _body.clear();
      setState(() => _replyTo = null);
      if (username != null) ProfileService.clearCache();
      return;
    }
    if (_usernameCodes.contains(reply.code)) return; // cancelled the username
    if (reply.status == 401) {
      _signInPrompt(context, 'comment');
    } else {
      showUkoSnack(context, 'Error', reply.message ?? 'Could not post your comment');
    }
  }

  Future<void> _remove(Map<String, dynamic> comment) async {
    final isReply = comment['parent'] != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UkoColors.gray900,
        title: Text(isReply ? 'Delete your reply?' : 'Delete your comment?', style: const TextStyle(color: Colors.white)),
        content: isReply ? null : const Text('Its replies go with it.', style: TextStyle(color: UkoColors.gray400)),
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
    final reply = await ReelsApi.post('comment/remove', {'id': comment['id']});
    if (!mounted) return;
    if (reply.data == null) {
      showUkoSnack(context, 'Error', reply.message ?? 'Could not delete it');
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final count = toNum(data?['count']).toInt();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(count > 0 ? 'Comments ($count)' : 'Comments',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Close',
          ),
        ]),
      ),
      const Divider(height: 1, color: UkoColors.border),
      Expanded(
        child: data == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: UkoColors.yellow)
                    : Text(_error!, style: const TextStyle(color: UkoColors.divider)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('No comments yet. Start the conversation.', style: TextStyle(color: UkoColors.divider)),
                    ),
                  for (final c in _comments) ...[
                    _ReelComment(comment: c, onReply: () => _reply(c), onRemove: () => _remove(c)),
                    for (final r in asMapList(c['replies']))
                      _ReelComment(comment: r, small: true, onReply: () => _reply(c), onRemove: () => _remove(r)),
                    if (toNum(c['reply_count']).toInt() > asMapList(c['replies']).length)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text('+${toNum(c['reply_count']).toInt() - asMapList(c['replies']).length} older replies',
                            style: const TextStyle(color: UkoColors.divider, fontSize: 11)),
                      ),
                  ],
                  if (truthy(data['more']))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy ? null : _more,
                        child: const Text('Load more', style: TextStyle(color: UkoColors.yellow)),
                      ),
                    ),
                ],
              ),
      ),
      if (data != null) const Divider(height: 1, color: UkoColors.border),
      if (data != null)
        SafeArea(
          top: false,
          child: truthy(data['signed_in'])
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_replyTo != null)
                      Row(children: [
                        Text('Replying to ', style: const TextStyle(color: UkoColors.divider, fontSize: 12)),
                        Text('${_replyTo!['author'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        TextButton(
                          onPressed: () => setState(() {
                            _replyTo = null;
                            _body.clear();
                          }),
                          child: const Text('cancel', style: TextStyle(color: UkoColors.divider, fontSize: 12)),
                        ),
                      ]),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _body,
                          focusNode: _focus,
                          maxLength: _maxBody,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: _replyTo != null ? 'Write a reply…' : 'Add a comment…',
                            isDense: true,
                            filled: true,
                            fillColor: UkoColors.card,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: UkoColors.border)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: UkoColors.yellow)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _body,
                        builder: (context, value, _) => FilledButton(
                          onPressed: _busy || value.text.trim().isEmpty ? null : _send,
                          style: FilledButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
                          child: const Text('Post'),
                        ),
                      ),
                    ]),
                  ]),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Expanded(
                      child: Text('Sign in to like and comment.', style: TextStyle(color: UkoColors.divider, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => Nav.push(context, Routes.signIn),
                      child: const Text('Sign in', style: TextStyle(color: UkoColors.yellow)),
                    ),
                  ]),
                ),
        ),
    ]);
  }
}

class _ReelComment extends StatelessWidget {
  const _ReelComment({required this.comment, required this.onReply, required this.onRemove, this.small = false});
  final Map<String, dynamic> comment;
  final VoidCallback onReply;
  final VoidCallback onRemove;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: small ? 32 : 0, top: small ? 8 : 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '${comment['author'] ?? ''}  ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          TextSpan(text: '${comment['body'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 13)),
        ])),
        const SizedBox(height: 2),
        Row(children: [
          Text(commentWhen(comment['created_at']), style: const TextStyle(color: UkoColors.divider, fontSize: 11)),
          const SizedBox(width: 12),
          InkWell(
            onTap: onReply,
            child: const Text('Reply', style: TextStyle(color: UkoColors.divider, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          if (truthy(comment['mine'])) ...[
            const SizedBox(width: 12),
            InkWell(
              onTap: onRemove,
              child: const Text('Delete', style: TextStyle(color: UkoColors.divider, fontSize: 11)),
            ),
          ],
        ]),
      ]),
    );
  }
}
