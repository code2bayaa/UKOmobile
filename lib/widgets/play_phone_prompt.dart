import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../routes.dart';

/// Stands in for the play button when the device is in a play region but the signed-in account's
/// phone number isn't (movies PRD #7, see services/profile.dart playGate()). Opens the profile
/// screen; [onReturn] runs when the viewer comes back, so the screen can check again.
class PlayPhonePrompt extends StatelessWidget {
  const PlayPhonePrompt({super.key, this.onReturn, this.width});
  final VoidCallback? onReturn;

  /// Defaults to PillButton's width (49% of the screen).
  final double? width;

  static const message = 'Add a phone number from Africa, Australia or Brazil to play';

  @override
  Widget build(BuildContext context) {
    final w = width ?? (MediaQuery.of(context).size.width - 8) * 0.49;
    return SizedBox(
      width: w,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: UkoColors.yellow, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Nav.push(context, Routes.profile);
            onReturn?.call();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Center(
                child: Text(message,
                    textAlign: TextAlign.center, style: TextStyle(color: UkoColors.yellow, fontSize: 12)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
