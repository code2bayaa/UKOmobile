import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';
import '../../services_ext/report.dart';
import '../../widgets/common.dart';
import '../../widgets/sign_in_required.dart';
import 'form_field.dart';
import '../../core/theme.dart';

/// Port of app/index.tsx (sign-in by account number).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.params = const {}});

  /// [SignInReturn.next] / [SignInReturn.nextParams]: the screen to open after signing in
  /// (set by SignInRequired, movies PRD #5).
  final Map<String, dynamic> params;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // rate-limit config
  static const _maxAttempts = 5;
  static const _lockWindowMs = 15 * 60 * 1000; // 15 minutes lockout
  static const _attemptsKey = 'signin_attempts_v1';

  final _account = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _authentication();
  }

  /// Auto-redirect when the stored user is still logged in.
  Future<void> _authentication() async {
    final res = await Http.postJson(Api.apiUrl, {'email': await Prefs.user});
    if (!mounted) return;
    if (res is Map && truthy(res['status']) && res['message'] == 'logged in') {
      RemoteService.instance.joinRoom();
      SignInReturn.go(context, widget.params);
      Report.collect();
    }
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getAttempts() async {
    try {
      final raw = await Prefs.getItem(_attemptsKey);
      if (raw == null || raw.isEmpty) return {'count': 0, 'firstAt': 0, 'lockedUntil': 0};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {'count': 0, 'firstAt': 0, 'lockedUntil': 0};
    }
  }

  Future<void> _setAttempts(Map<String, dynamic> obj) => Prefs.setItem(_attemptsKey, jsonEncode(obj));
  Future<void> _resetAttempts() => Prefs.removeItem(_attemptsKey);

  void _alert(String title, String message) {
    if (!mounted) return;
    showUkoSnack(context, title, message);
  }

  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _handleSubmit() async {
    setState(() => _loading = true);
    try {
      final account = _account.text;
      if (account.isEmpty) {
        _alert('error', 'Add an account');
        return;
      }
      // check lockout
      final attempts = await _getAttempts();
      final now = DateTime.now().millisecondsSinceEpoch;
      final lockedUntil0 = _int(attempts['lockedUntil']);
      if (lockedUntil0 != 0 && lockedUntil0 > now) {
        final mins = ((lockedUntil0 - now) / 60000).ceil();
        _alert('Too many attempts', 'Try again in $mins minute(s)');
        return;
      }

      final data = await Http.postJson(Api.signin, {
        'account': account
      }, headers: const {
        'Content-Type': 'application/json',
      });
      if (data == null) throw Exception('sign-in request failed');

      final status = data is Map ? data['status'] : null;
      if (!truthy(status)) {
        // increment attempts
        final prev = await _getAttempts();
        final newCount = _int(prev['count']) + 1;
        final firstAt = _int(prev['firstAt']) != 0 ? _int(prev['firstAt']) : now;
        final lockedUntil = newCount >= _maxAttempts ? now + _lockWindowMs : 0;
        await _setAttempts({'count': newCount, 'firstAt': firstAt, 'lockedUntil': lockedUntil});
        if (lockedUntil != 0) {
          _alert(
              'Too many attempts', 'Too many failed sign-ins. Locked for ${(_lockWindowMs / 60000).ceil()} minutes.');
        } else {
          final msg = data is Map ? data['message'] : null;
          _alert('error', (msg is String && msg.isNotEmpty) ? msg : 'Invalid credentials');
        }
        return;
      }
      // PRD #22: the right number only gets a code emailed; the token comes from /verify
      final signedIn = truthy((data as Map)['twoFactor']) ? await _askForCode(data) : data;
      if (signedIn == null) return;
      await _finishSignIn(signedIn);
    } catch (e) {
      debugPrint('$e');
      _alert('error', 'Unexpected error. Try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks for the emailed code until it is right; null when the user gives up or it expires.
  Future<Map?> _askForCode(Map challenge) async {
    final sentTo = '${challenge['sentTo'] ?? 'your email'}';
    while (true) {
      if (!mounted) return null;
      final code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CodeDialog(sentTo: sentTo),
      );
      if (code == null) return null;
      final res = await Http.postJson(Api.signinVerify, {'challenge': challenge['challenge'], 'code': code},
          headers: const {'Content-Type': 'application/json'});
      if (res is Map && truthy(res['status'])) return res;
      final msg = res is Map ? '${res['message'] ?? 'Wrong code'}' : 'Could not check the code. Try again.';
      _alert('error', msg);
      if (RegExp('sign in again', caseSensitive: false).hasMatch(msg)) return null;
    }
  }

  Future<void> _finishSignIn(Map data) async {
    final user = data['user'];
    if (user == null) throw Exception('no user in sign-in response');
    await Prefs.setItem(PrefKeys.user, '$user');
    final token = data['token'];
    if (token is String && token.isNotEmpty) await Prefs.setItem(PrefKeys.token, token);
    // success -> clear attempts
    await _resetAttempts();
    await RemoteService.instance.joinRoom();
    if (!mounted) return;
    SignInReturn.go(context, widget.params);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // full-screen artwork under the form, edge to edge (behind the status bar too)
          Positioned.fill(child: Image.asset('assets/images/background.png', fit: BoxFit.cover)),
          SafeArea(
            child: Container(
              // dims the artwork enough for the form to stay readable
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x99000000), Color(0xB3000000), Color(0xCC000000)],
                  stops: [0, 0.5, 0.6, 1],
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Kwani UKO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: w * 0.1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UkoFormField(
                            label: 'Account Number',
                            placeholder: 'Account Number',
                            controller: _account,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: w * 0.4,
                              height: 30,
                              child: Material(
                                color: UkoColors.border, // bg-gray-600
                                borderRadius: BorderRadius.circular(6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: _loading ? null : _handleSubmit,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(_loading ? 'Signing in...' : 'Sign In',
                                          style: const TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _link('Register', () => Nav.push(context, Routes.signup)),
                          _link('Change Account No', () => Nav.push(context, Routes.change)),
                        ],
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: InkWell(
                          onTap: () => Nav.push(context, Routes.offlineDownloads),
                          child: Container(
                            constraints: BoxConstraints(minWidth: w * 0.3),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: UkoColors.purple, width: 1.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text('Go to Offline Downloads',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// The 6-digit sign-in code emailed by /signin/android (PRD #22).
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.sentTo});
  final String sentTo;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (RegExp(r'^\d{6}$').hasMatch(code)) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your sign-in code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('We emailed a 6-digit code to ${widget.sentTo}. It works for 10 minutes.'),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Verify')),
      ],
    );
  }
}
