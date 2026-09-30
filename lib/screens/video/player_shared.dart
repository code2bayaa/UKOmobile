import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../services/prefs.dart';

/// Helpers shared by the video/stream, video/vlc and video/play ports
/// (collection.jsx, vlc.tsx, play.tsx all repeat the same AwesomeAlert +
/// "pay with credits" code).

/// `<AwesomeAlert show title message showCancelButton showConfirmButton
/// confirmButtonColor="#DD6B55" closeOnTouchOutside />` followed by
/// `removeAlert()` (auto-hide after 2 s).
Future<void> showAwesomeAlert(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AutoHideAlert(title: title, message: message),
  );
}

class _AutoHideAlert extends StatefulWidget {
  const _AutoHideAlert({required this.title, required this.message});
  final String title;
  final String message;

  @override
  State<_AutoHideAlert> createState() => _AutoHideAlertState();
}

class _AutoHideAlertState extends State<_AutoHideAlert> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _close);
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    // removeRoute (not pop) so a screen pushed meanwhile is never popped.
    if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black)),
      content: Text(widget.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          style: TextButton.styleFrom(backgroundColor: const Color(0xFFD0D0D0), foregroundColor: Colors.white),
          onPressed: _close,
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(backgroundColor: const Color(0xFFDD6B55), foregroundColor: Colors.white),
          onPressed: _close,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

enum PlayerPayment {
  /// USER_PAID said the rent is active and UPDATE_USER_CREDITS succeeded.
  paid,

  /// PAY_USER_CREDITS charged 50 credits (RN shows "success / paid with credits").
  paidWithCredits,

  /// Not paid -> RN calls `router.back()`.
  notPaid,

  /// A request failed / returned non-JSON. In RN the `await res.json()`
  /// rejection was unhandled (the try/catch wrapped only the call, not the
  /// promise), so the screen just stayed open. Kept.
  error,
}

/// `processPayment()` from app/video/vlc.tsx:749 and app/video/play.tsx:135
/// (identical code): USER_PAID -> UPDATE_USER_CREDITS, else PAY_USER_CREDITS
/// with `credit: 50.00` (JSON.stringify writes `50`). The second value is which credits paid (movies PRD #27,
/// e.g. "30 subscription + 20 free credits"), when the server says.
Future<(PlayerPayment, String?)> processPlayerPayment({required dynamic id, required dynamic type}) async {
  final email = await Prefs.user;
  final paidRes = await Http.postJson(Api.userPaid, {'id': id, 'email': email});
  if (paidRes is! Map) return (PlayerPayment.error, null);
  if (truthy(paidRes['status'])) {
    final res = await Http.postJson(Api.updateUserCredits, {'type': type, 'id': id, 'email': email});
    if (res is! Map) return (PlayerPayment.error, null);
    return (truthy(res['success']) ? PlayerPayment.paid : PlayerPayment.notPaid, null);
  }
  final res = await Http.postJson(Api.payUserCredits, {
    'credit': 50,
    'data': {
      'receipt': 'player',
      'player-type': [type],
      'title': id,
    },
    'email': email,
  });
  if (res is! Map) return (PlayerPayment.error, null);
  if (!truthy(res['status'])) return (PlayerPayment.notPaid, null);
  return (PlayerPayment.paidWithCredits, paidWithOf(res));
}

/// "Paid with 30 subscription + 20 free credits" from a debit reply's earning.paid_with (PRD #27), or null.
String? paidWithOf(dynamic reply) {
  final earning = reply is Map ? reply['earning'] : null;
  final text = earning is Map ? earning['paid_with'] : null;
  return text is String && text.isNotEmpty ? text : null;
}

/// `parseMaybeArray` from the RN video screens.
List<dynamic>? parseMaybeArray(dynamic val) {
  if (!truthy(val)) return null;
  if (val is List) return val;
  if (val is String) {
    try {
      final parsed = jsonDecode(val);
      return parsed is List ? parsed : null;
    } catch (_) {
      return [val];
    }
  }
  return null;
}

/// `(parseFloat(x)).toFixed(1)` (NaN -> "NaN").
String toFixed1(dynamic v) {
  final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
  if (d == null || d.isNaN) return 'NaN';
  return d.toStringAsFixed(1);
}

/// Params in RN are strings; `season ? parseInt(season) : -1`.
int parseIntOr(dynamic v, int fallback) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty || s == 'undefined' || s == 'null' || s == 'false') return fallback;
  final m = RegExp(r'^[+-]?\d+').firstMatch(s);
  return m == null ? fallback : int.parse(m.group(0)!);
}

/// `new Date().toISOString()` (millisecond precision, `Z`).
String jsIsoNow() {
  final d = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = d.millisecond.toString().padLeft(3, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T'
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${ms}Z';
}
