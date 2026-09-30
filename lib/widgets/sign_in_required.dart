import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/prefs.dart';

/// Movies PRD #5: screens that need an account (see `_signInRoutes` in routes.dart). Signed in
/// means a stored user (PrefKeys.user, written by sign-in, removed by SignOut). Anyone else is
/// sent to sign-in, which comes back to [route] with [params] once they have signed in.
class SignInRequired extends StatefulWidget {
  const SignInRequired({super.key, required this.route, required this.params, required this.child});
  final String route;
  final Map<String, dynamic> params;
  final Widget child;

  @override
  State<SignInRequired> createState() => _SignInRequiredState();
}

class _SignInRequiredState extends State<SignInRequired> {
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final user = await Prefs.user;
    if (!mounted) return;
    if (user != null && user.isNotEmpty) {
      setState(() => _signedIn = true);
      return;
    }
    Navigator.of(context).pushReplacementNamed(Routes.signIn, arguments: <String, dynamic>{
      SignInReturn.next: widget.route,
      SignInReturn.nextParams: widget.params,
    });
  }

  @override
  Widget build(BuildContext context) => _signedIn ? widget.child : const SizedBox.shrink();
}

/// The sign-in route's arguments that name where to go after signing in.
class SignInReturn {
  SignInReturn._();
  static const next = 'next';
  static const nextParams = 'nextParams';

  /// After a successful sign-in: home at the root (as before), then the screen that asked for
  /// sign-in, if any.
  static void go(BuildContext context, Map<String, dynamic> signInParams) {
    final nav = Navigator.of(context);
    nav.pushNamedAndRemoveUntil(Routes.home, (_) => false);
    final route = signInParams[next];
    if (route is String && route.isNotEmpty && route != Routes.home && route != Routes.signIn) {
      final p = signInParams[nextParams];
      nav.pushNamed(route, arguments: p is Map ? Map<String, dynamic>.from(p) : const <String, dynamic>{});
    }
  }
}
