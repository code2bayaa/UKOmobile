import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../widgets/common.dart';
import '../auth/form_field.dart';
import '../../core/theme.dart';

/// Port of app/(tabs)/credits/earn.tsx (feedback form for free credits).
class EarnCreditsScreen extends StatefulWidget {
  const EarnCreditsScreen({super.key});

  @override
  State<EarnCreditsScreen> createState() => _EarnCreditsScreenState();
}

class _EarnCreditsScreenState extends State<EarnCreditsScreen> {
  // Same key order as the RN `form` state ({name, email, message, subject}),
  // which decides the "Fill input <key>" message.
  final Map<String, TextEditingController> _form = {
    'name': TextEditingController(),
    'email': TextEditingController(),
    'message': TextEditingController(),
    'subject': TextEditingController(),
  };
  bool _loading = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    for (final c in _form.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _alert(String title, String msg) {
    if (mounted) showUkoSnack(context, title, msg);
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      for (final c in _form.values) {
        c.clear();
      }
    });
  }

  Future<void> _handleSubmit() async {
    setState(() => _loading = true);

    final empty = _form.entries.where((e) => e.value.text.isEmpty).map((e) => e.key).firstOrNull;
    if (empty != null) {
      _alert('error', 'Fill input $empty');
      setState(() => _loading = false);
      return;
    }

    final body = {
      'name': _form['name']!.text,
      'email': _form['email']!.text,
      'subject': _form['subject']!.text,
      'message': _form['message']!.text,
      'session': await Prefs.user ?? '',
    };

    final res = await Http.postJson(Api.feedback, body,
        headers: const {'Content-type': 'application/json; charset=UTF-8'});
    if (!mounted) return;
    setState(() => _loading = false);
    if (res is! Map) {
      _alert('error', "Error I didn't receive your message 😢");
    } else if (truthy(res['status'])) {
      _alert('success', 'Thank you for your message 😃');
    } else {
      debugPrint('${res['error']}');
      _alert('error', "I didn't receive your message 😢");
    }
    _scheduleReset();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // PRD #15: the main way to earn - 5 UKOshop ads = 50 credits
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Nav.push(context, Routes.creditsEarnAds),
                  icon: const Icon(Icons.ondemand_video_outlined),
                  label: const Text('Watch 5 ads, earn 50 credits'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Or provide feedback for free credits', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 28),
            UkoFormField(label: 'Name', placeholder: 'Name', controller: _form['name']!),
            const SizedBox(height: 8),
            UkoFormField(
              label: 'Email',
              placeholder: 'BrianWekesa@hotmail.com',
              keyboardType: TextInputType.emailAddress,
              controller: _form['email']!,
            ),
            const SizedBox(height: 8),
            UkoFormField(label: 'Subject', placeholder: 'Subject', controller: _form['subject']!),
            const SizedBox(height: 8),
            UkoFormField(
              label: 'Your Message',
              placeholder: 'Write here...',
              multiline: true,
              controller: _form['message']!,
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _loading ? 0.5 : 1,
              child: SizedBox(
                width: w * 0.8,
                child: Material(
                  color: UkoColors.card, // bg-stone-900
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _loading ? null : _handleSubmit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      child: Center(
                        child: Text(_loading ? 'Sending...' : 'Submit',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
