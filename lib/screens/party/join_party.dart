import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../routes.dart';
import '../../services/party.dart';

/// Join a watch party by its code (movies PRD #11): shows the title, host and party fee; joining pays the fee
/// (if any) and opens the same title in the player, where the party panel takes over. params: {code?}.
class JoinPartyScreen extends StatefulWidget {
  const JoinPartyScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends State<JoinPartyScreen> {
  final _code = TextEditingController();
  Map<String, dynamic>? _info;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final code = '${widget.params['code'] ?? ''}'.toUpperCase();
    if (code.isNotEmpty && code != 'NULL') {
      _code.text = code;
      _look(code);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _clean(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _look(String value) async {
    final code = _clean(value);
    if (code.length != 6) return;
    setState(() => _busy = true);
    final res = await PartyApi.post('info', {'code': code});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res['status'] == true) {
        _info = res;
        _message = null;
      } else {
        _info = null;
        _message = '${res['message'] ?? 'No party with that code'}';
      }
    });
  }

  void _openPlayer(Map<String, dynamic> party) {
    final launch = party['launch'] is Map ? Map<String, dynamic>.from(party['launch'] as Map) : <String, dynamic>{};
    // the web player sends its backdrop as {path, logo}; the phone player takes the path
    final bg = launch['background'];
    if (bg is Map) launch['background'] = bg['path'];
    Nav.push(context, Routes.videoSpeed, {...launch, 'party': party['code']});
  }

  Future<void> _join() async {
    final party = Map<String, dynamic>.from(_info!['party'] as Map);
    final you = _info!['you'] is Map ? _info!['you'] as Map : const {};
    if (you['member'] == true) return _openPlayer(party);
    final fee = (party['fee'] as num?)?.toInt() ?? 0;
    if (fee > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Join for $fee credits?'),
          content: const Text(
              "The party fee goes to the host (60%) and UKO (40%). You also pay the title's normal play charge unless you already watched it today."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Pay $fee credits')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final res = await PartyApi.post('join', {'code': party['code'], 'fee': fee});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['status'] != true) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Watch party'),
          content: Text('${res['message'] ?? 'Could not join'}'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    // PRD #27: which credits paid the fee
    final paidWith = res['paid_with'];
    if (paidWith is String && paidWith.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Party fee paid with $paidWith')));
    }
    _openPlayer(Map<String, dynamic>.from(res['party'] as Map));
  }

  @override
  Widget build(BuildContext context) {
    final party = _info?['party'] is Map ? _info!['party'] as Map : null;
    final you = _info?['you'] is Map ? _info!['you'] as Map : const {};
    final members = (party?['members'] as num?)?.toInt() ?? 0;
    final max = (party?['max_members'] as num?)?.toInt() ?? 10;
    final fee = (party?['fee'] as num?)?.toInt() ?? 0;
    final open = party?['open'] == true;
    final full = members >= max && you['member'] != true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Row(children: [
          Icon(Icons.groups, color: UkoColors.yellow),
          SizedBox(width: 8),
          Text('Watch party', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        const Text('Watch together with up to 10 people - camera, mic and chat. Ask the host for the party code.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 18),
        TextField(
          controller: _code,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 6),
          onChanged: (v) => _look(v),
          decoration: const InputDecoration(
            labelText: 'Party code',
            labelStyle: TextStyle(color: Colors.white60),
            counterText: '',
            filled: true,
            fillColor: Colors.white10,
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(color: UkoColors.yellow)),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (party != null) ...[
          const SizedBox(height: 18),
          Text('${party['title'] ?? 'Untitled'}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Hosted by ${party['host']}', style: const TextStyle(color: Colors.white70)),
          Text('$members / $max watching', style: const TextStyle(color: Colors.white70)),
          Text(fee > 0 ? '$fee credits to join' : 'Free to join', style: const TextStyle(color: UkoColors.yellow)),
          if (!open) const Text('This party has ended.', style: TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: UkoColors.yellow, foregroundColor: Colors.black),
            onPressed: _busy || !open || full ? null : _join,
            child: Text(you['member'] == true ? 'Back to the party' : full ? 'Party is full' : 'Join the party'),
          ),
        ],
      ],
    );
  }
}
