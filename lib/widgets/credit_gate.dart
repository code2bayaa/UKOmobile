import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/prefs.dart';
import '../services/region.dart';

/// Wraps the earn / buy credits screens: only signed-in users in a [creditsAllowedHere]
/// place get [child]; everyone else is sent home. Shows nothing while checking.
class CreditGate extends StatefulWidget {
  const CreditGate({super.key, required this.child});
  final Widget child;

  @override
  State<CreditGate> createState() => _CreditGateState();
}

class _CreditGateState extends State<CreditGate> {
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final user = await Prefs.user;
    final allowed = user != null && user.isNotEmpty && await creditsAllowedHere();
    if (!mounted) return;
    if (allowed) {
      setState(() => _allowed = true);
    } else {
      Nav.switchTab(context, Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) => _allowed ? widget.child : const SizedBox.shrink();
}
