import 'package:flutter/material.dart';

import '../routes.dart';

/// Port of app/+not-found.tsx.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oops!')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("This screen doesn't exist."),
            TextButton(
              onPressed: () => Nav.resetTo(context, Routes.signIn),
              child: const Text('Go to home screen!'),
            ),
          ],
        ),
      ),
    );
  }
}
