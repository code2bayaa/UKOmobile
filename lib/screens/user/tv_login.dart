import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';
import '../../services/sockets.dart';
import '../../widgets/common.dart';
import '../../core/theme.dart';

/// Port of app/(tabs)/tvLogin.tsx: the phone sends the access code shown on
/// the TV plus the signed-in email (`tv-login`), then waits for the relay's
/// `feedback-user-login` (sent when the TV finished logging in).
///
/// The code is approved on the server first (`/user/tv/link`, with this phone's token); the TV
/// then claims its own token with a secret only it holds, so the socket message only wakes it up.
class TvLoginScreen extends StatefulWidget {
  const TvLoginScreen({super.key});

  @override
  State<TvLoginScreen> createState() => _TvLoginScreenState();
}

class _TvLoginScreenState extends State<TvLoginScreen> with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  bool _isLoggingIn = false;

  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _intro, curve: Curves.linear);
  late final Animation<double> _translateY =
      Tween<double>(begin: 30, end: 0).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutExpo));

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    // Registered once (RN added a new listener on every button press).
    SocketsService.instance.on('feedback-user-login', _onFeedback);
  }

  dynamic _onFeedback(dynamic _) {
    if (mounted) setState(() => _isLoggingIn = false);
    return null;
  }

  @override
  void dispose() {
    SocketsService.instance.off('feedback-user-login', _onFeedback);
    _intro.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoggingIn = true);
    final userEmail = await Prefs.user;
    if (!mounted) return;
    if (userEmail == null || userEmail.isEmpty) {
      setState(() => _isLoggingIn = false);
      showUkoAlert(context, 'Error', 'Sign in on this phone first');
      return;
    }
    final linked = await Http.postJson(Api.tvLink, {'code': code});
    if (!mounted) return;
    if (linked is! Map || linked['status'] != true) {
      setState(() => _isLoggingIn = false);
      final message = linked is Map ? linked['message'] : null;
      showUkoAlert(context, 'Error',
          message is String && message.isNotEmpty ? message : 'Could not reach the TV. Check the code and try again.');
      return;
    }
    await RemoteService.instance.tvLogin(code, userEmail);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isLoggingIn || _code.text.trim().isEmpty;
    return Container(
      color: UkoColors.card,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, child) => Opacity(
            opacity: _fade.value,
            child: Transform.translate(offset: Offset(0, _translateY.value), child: child),
          ),
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TV LogIn',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    const Text('Enter your access code to continue',
                        style: TextStyle(fontSize: 14, color: UkoColors.divider)),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _code,
                      obscureText: true,
                      enabled: !_isLoggingIn,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => disabled ? null : _handleLogin(),
                      decoration: InputDecoration(
                        hintText: 'Access code',
                        hintStyle: const TextStyle(color: UkoColors.divider),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        contentPadding: const EdgeInsets.all(15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: UkoColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: UkoColors.border),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: UkoColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: UkoColors.yellow),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Opacity(
                      opacity: disabled ? 0.4 : 1,
                      child: Material(
                        color: UkoColors.yellow,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: disabled ? null : _handleLogin,
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Center(
                              child: _isLoggingIn
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _Dot(delay: 0),
                                        SizedBox(width: 6),
                                        _Dot(delay: 200),
                                        SizedBox(width: 6),
                                        _Dot(delay: 400),
                                        SizedBox(width: 6),
                                        Text('LOGGING IN', style: _buttonText),
                                      ],
                                    )
                                  : const Text('ENTER', style: _buttonText),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _buttonText = TextStyle(color: Colors.black, fontWeight: FontWeight.w600, letterSpacing: 2);

/// Pulsing dot: scale 0.5 -> 1 (400ms, after [delay]) -> 0.5 (400ms), looped.
/// Like RN's Animated.loop(sequence([timing(delay), timing])), the delay is
/// part of every iteration.
class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final int delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final int _total = widget.delay + 800;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _total))..repeat();

  double _scale(double t) {
    final ms = t * _total;
    final d = widget.delay.toDouble();
    if (ms < d) return 0.5;
    if (ms < d + 400) return 0.5 + 0.5 * Curves.easeInOut.transform((ms - d) / 400);
    return 1 - 0.5 * Curves.easeInOut.transform(((ms - d - 400) / 400).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: _scale(_c.value),
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
