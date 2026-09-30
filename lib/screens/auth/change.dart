import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../widgets/common.dart';
import 'account_form.dart';

/// Port of app/change.tsx (issue a new account number for an existing email).
class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  Future<void> _handleSubmit(BuildContext context, String? email) async {
    if (email == null) {
      showUkoAlert(context, 'Error', 'Input email');
      return;
    }

    // the server makes the new account number and emails it; it answers the same whether or not
    // the email has an account, so there is nothing to check first
    final res = await Http.postJson(Api.change, {'email': email},
        headers: const {'Content-Type': 'application/json'});
    if (res is! Map) throw Exception('change failed');
    if (!context.mounted) return;
    if (!truthy(res['status'])) {
      final m = res['message'];
      showUkoAlert(context, 'Error', truthy(m) ? '$m' : 'Registration failed');
      return;
    }
    final m = res['message'];
    showUkoAlert(context, 'Check your email', truthy(m) ? '$m' : 'A new account number is on its way');
  }

  @override
  Widget build(BuildContext context) => AccountEmailForm(
        image: 'assets/images/account.png',
        title: 'Change Account',
        buttonLabel: 'Change',
        loadingLabel: 'changing',
        onSubmit: _handleSubmit,
      );
}
