import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../routes.dart';
import '../services/profile.dart';

/// The play buttons' "no credits" case for someone who is not signed in. Signed-out sessions get
/// no free credits (user/report/index.js) - the 600 free credits and the monthly top-up are for
/// accounts - so a guest is asked to sign up instead of being told to add credits.
///
/// Returns false when there is a signed-in account: the caller then shows its usual
/// "NO CREDITS add more credits". True when the guest prompt was shown.
Future<bool> promptGuestSignUp(BuildContext context) async {
  if (await ProfileService.signedIn) return false;
  if (!context.mounted) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: UkoColors.gray900,
      title: const Text('Sign up to watch', style: TextStyle(color: UkoColors.yellow)),
      content: const Text(
        'Create a free UKO account to get 600 free credits, topped back up every month.',
        style: TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not now')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(Routes.signIn), child: const Text('Sign in')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(Routes.signup), child: const Text('Sign up')),
      ],
    ),
  );
  if (choice != null && context.mounted) Navigator.of(context).pushNamed(choice);
  return true;
}
