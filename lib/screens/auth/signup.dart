import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../services/profile.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_location_fields.dart';
import 'account_form.dart';

/// Port of app/signup.tsx. Registering also asks for a phone number and country / county / ward
/// (movies PRD #6, #21); the user service's /signup/account requires them.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _place = PhoneLocationController();
  UkoLocations? _locations;
  bool _loadingLocations = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    setState(() => _loadingLocations = true);
    final l = await ProfileService.locations();
    if (!mounted) return;
    if (l != null) _place.load(null, l);
    setState(() {
      _locations = l;
      _loadingLocations = false;
    });
  }

  Future<void> _handleSubmit(BuildContext context, String? email) async {
    if (email == null) {
      showUkoAlert(context, 'Error', 'Input email');
      return;
    }
    final locations = _locations;
    if (locations == null) {
      showUkoAlert(context, 'Error', 'Could not load the list of countries. Check your connection and try again.');
      return;
    }
    final invalid = _place.validate(locations);
    if (invalid != null) {
      showUkoAlert(context, 'Error', invalid);
      return;
    }

    final emailJSON = await Http.postJson(Api.emailVerify, {'email': email},
        headers: const {'Content-Type': 'application/json'});
    if (emailJSON is! Map) throw Exception('email verify failed');
    if (truthy(emailJSON['status'])) {
      if (context.mounted) showUkoAlert(context, 'Error', '${emailJSON['message'] ?? ''}');
      return;
    }

    // the server makes the account number and emails it; PRD #22: it also comes back once here,
    // to be saved as a .txt (signing in still needs the code emailed to the account).
    // 400 = bad phone / location, 409 = phone already on another account; both carry a message.
    final res = await Http.postJson(Api.signup, {'email': email, ..._place.phoneBody(), ..._place.locationBody()},
        headers: const {'Content-Type': 'application/json'});
    if (res is! Map) throw Exception('signup failed');
    if (!context.mounted) return;
    if (!truthy(res['status'])) {
      final m = res['message'];
      showUkoAlert(context, 'Error', truthy(m) ? '$m' : 'Registration failed');
      return;
    }
    final m = res['message'];
    var message = truthy(m) ? '$m' : 'Your account number is in your email';
    final account = res['account'];
    if (account is String && account.isNotEmpty) {
      final saved = await _saveAccountNumber(email, account);
      message += saved != null
          ? '\n\nSaved to $saved'
          : '\n\nCould not save the file - your account number is: ${_grouped(account)}';
    }
    if (!context.mounted) return;
    showUkoAlert(context, 'Success', message);
  }

  static String _grouped(String account) =>
      account.replaceAllMapped(RegExp(r'(\d{4})(?=\d)'), (m) => '${m[1]} ');

  /// Writes UKO-account-number.txt to the phone's Download folder (the app's own folder when that
  /// can't be written). Returns the path, or null when nothing could be written.
  Future<String?> _saveAccountNumber(String email, String account) async {
    final text = [
      'UKO account number',
      '',
      'Email:          $email',
      'Account number: ${_grouped(account)}',
      'Created:        ${DateTime.now()}',
      '',
      'Sign in with this number; a code is then emailed to you to finish signing in.',
      'Keep this file private. If someone else gets it, use Change Account No in the app.',
      '',
    ].join('\r\n');
    final folders = <Future<Directory?> Function()>[
      if (Platform.isAndroid) () async => Directory('/storage/emulated/0/Download'),
      getDownloadsDirectory,
      getApplicationDocumentsDirectory,
    ];
    for (final folder in folders) {
      try {
        final dir = await folder();
        if (dir == null || !await dir.exists()) continue;
        final file = File('${dir.path}/UKO-account-number.txt');
        await file.writeAsString(text, flush: true);
        return file.path;
      } catch (e) {
        debugPrint('account number not saved there: $e');
      }
    }
    return null;
  }

  Widget _placeFields() {
    final l = _locations;
    if (l != null) return PhoneLocationFields(controller: _place, locations: l);
    if (_loadingLocations) {
      return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
    }
    return TextButton(
      onPressed: _loadLocations,
      child: const Text('Could not load countries - tap to retry', style: TextStyle(color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) => AccountEmailForm(
        image: 'assets/images/register.png',
        title: 'Register Account',
        buttonLabel: 'Register',
        loadingLabel: 'registering',
        onSubmit: _handleSubmit,
        extra: _placeFields(),
      );
}
