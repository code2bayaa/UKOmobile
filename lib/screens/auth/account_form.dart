import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../core/theme.dart';

/// Shared bits of app/signup.tsx and app/change.tsx (they are near copies).

// Account numbers are made and emailed by the server (movies user service /signup/account and
// /change); the app used to compute them from the email and mail them through an open relay.

/// Shared layout: image + underlined 30px title, an email input, a small
/// slate button and the helper text.
class AccountEmailForm extends StatefulWidget {
  const AccountEmailForm({
    super.key,
    required this.image,
    required this.title,
    required this.buttonLabel,
    required this.loadingLabel,
    required this.onSubmit,
    this.extra,
  });

  final String image;
  final String title;
  final String buttonLabel;
  final String loadingLabel;

  /// More fields under the email (signup's phone + country / county / ward).
  final Widget? extra;

  /// Receives the trimmed email (or null when empty, like the RN state).
  final Future<void> Function(BuildContext context, String? email) onSubmit;

  @override
  State<AccountEmailForm> createState() => _AccountEmailFormState();
}

class _AccountEmailFormState extends State<AccountEmailForm> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final e = _email.text.trim();
    try {
      await widget.onSubmit(context, e.isEmpty ? null : e);
    } catch (err) {
      debugPrint('$err');
      if (mounted) await showUkoAlert(context, 'Error', 'Unexpected error. Try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: w * 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  SizedBox(width: 100, height: 200, child: Image.asset(widget.image, fit: BoxFit.contain)),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.1),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Input Email',
                      hintStyle: TextStyle(color: Colors.white),
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                    ),
                  ),
                ),
              ),
              if (widget.extra != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(w * 0.1, 12, w * 0.1, 12),
                  child: widget.extra,
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.1, vertical: w * 0.01),
                  child: SizedBox(
                    width: w * 0.2,
                    height: 30,
                    child: Material(
                      color: UkoColors.slate, // bg-slate-400
                      borderRadius: BorderRadius.circular(2),
                      child: InkWell(
                        onTap: _loading ? null : _submit,
                        child: Center(
                          child: FittedBox(
                            child: Text(_loading ? widget.loadingLabel : widget.buttonLabel,
                                style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.1),
                child: const SizedBox(
                  width: double.infinity,
                  child: Text('An account number will be sent to your email',
                      textAlign: TextAlign.justify, style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
