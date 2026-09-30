import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../routes.dart';
import '../../services/profile.dart';
import '../../services/sales_api.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_location_fields.dart';

/// The signed-in account's phone number and country / county / ward (movies PRD #6): view,
/// complete (accounts made before registration asked) and edit, via GET/POST /profile/android.
/// The phone number's country decides whether this account may play videos (PRD #7). Also the unique
/// username comments are posted under (widgets/comments_section.dart asks for it on a first comment).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _place = PhoneLocationController();
  final _username = TextEditingController();
  UkoLocations? _locations;
  UkoProfile? _profile;
  Map<String, dynamic>? _wallet; // money earned and withdrawable (PRD #28) - null until loaded / on failure
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _place.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait<Object?>([ProfileService.locations(), ProfileService.fetch(force: true)]);
    if (!mounted) return;
    final l = results[0] as UkoLocations?;
    final p = results[1] as UkoProfile?;
    if (l != null) _place.load(p, l);
    _username.text = p?.username ?? '';
    _loadWallet();
    setState(() {
      _locations = l;
      _profile = p;
      _loading = false;
      _error = l == null
          ? 'Could not load the list of countries.'
          : p == null
              ? 'Could not load your profile. You may need to sign in again.'
              : null;
    });
  }

  Future<void> _save() async {
    final l = _locations;
    if (l == null) return;
    // phone and location can each be saved alone; country + county + ward go together
    final invalid = _place.validate(l, requirePhone: false, requireLocation: false);
    if (invalid != null) {
      showUkoAlert(context, 'Error', invalid);
      return;
    }
    final username = cleanUsername(_username.text);
    if (username.isEmpty && _profile?.username != null) {
      showUkoAlert(context, 'Error', 'A username can be changed but not removed');
      return;
    }
    final badName = username.isEmpty ? null : usernameProblem(username);
    if (badName != null) {
      showUkoAlert(context, 'Error', badName);
      return;
    }
    final body = <String, String>{
      if (username.isNotEmpty) 'username': username,
      if (_place.hasPhone) ..._place.phoneBody(),
      if (_place.hasLocation) ..._place.locationBody(),
    };
    if (body.isEmpty) {
      showUkoAlert(context, 'Error', 'Enter a username, your phone number or your location');
      return;
    }
    setState(() => _saving = true);
    final res = await ProfileService.save(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      showUkoAlert(context, 'Error', res.message ?? 'Could not save your profile');
      return;
    }
    final p = res.profile!;
    _place.load(p, l);
    _username.text = p.username ?? '';
    setState(() => _profile = p);
    showUkoSnack(
      context,
      'Saved',
      p.phoneAllowsPlay
          ? 'Your profile is saved.'
          : 'Saved. Playing videos needs a phone number from Africa, Australia or Brazil.',
    );
  }

  /// The account number is only stored hashed, so it can't be shown: a new one is made and
  /// emailed through the same route as the Change Account screen, which retires the old one.
  Future<void> _newAccountNumber(String email) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UkoColors.gray900,
        title: const Text('New account number?', style: TextStyle(color: UkoColors.yellow)),
        content: Text("We'll email a new account number to $email. Your current one will stop working.",
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send it')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _sending = true);
    dynamic res;
    try {
      res = await Http.postJson(Api.change, {'email': email}, headers: const {'Content-Type': 'application/json'});
    } catch (_) {
      res = null;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    final ok = res is Map && res['status'] == true;
    final m = res is Map ? res['message'] : null;
    showUkoAlert(
        context,
        ok ? 'Check your email' : 'Error',
        m is String && m.isNotEmpty
            ? m
            : (ok ? 'A new account number is on its way' : 'Could not send a new account number'));
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: UkoColors.gray400))),
            Expanded(child: Text(value ?? '-', style: const TextStyle(color: Colors.white))),
          ],
        ),
      );

  Widget _summary(UkoProfile p) {
    final place = [p.ward, p.county, p.country].whereType<String>().join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UkoColors.gray900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: UkoColors.gray700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.email != null) ...[
            _row('Account no.', 'Emailed to ${p.email} when you registered'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _sending ? null : () => _newAccountNumber(p.email!),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: UkoColors.yellow),
                child: Text(_sending ? 'Sending...' : 'Email me a new account number'),
              ),
            ),
          ],
          _row('Username', p.username),
          _row('Phone',
              p.telephone == null ? null : '${p.telephone}${p.phoneCountry == null ? '' : ' (${p.phoneCountry})'}'),
          _row('Location', place.isEmpty ? null : place),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(p.phoneAllowsPlay ? Icons.check_circle : Icons.info_outline,
                  size: 18, color: p.phoneAllowsPlay ? UkoColors.green : UkoColors.yellow),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.phoneAllowsPlay
                      ? 'Your phone number lets you play videos.'
                      : 'Add a phone number from Africa, Australia or Brazil to play videos.',
                  style: TextStyle(color: p.phoneAllowsPlay ? Colors.white : UkoColors.yellow, fontSize: 13),
                ),
              ),
            ],
          ),
          if (!p.complete)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Your profile is incomplete - add your phone number and location below.',
                  style: TextStyle(color: UkoColors.gray400, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Future<void> _loadWallet() async {
    final w = await SalesApi.wallet();
    if (mounted) setState(() => _wallet = w['status'] == true ? w : null);
  }

  /// Money earned (offline video sales today) and the M-PESA withdrawal - the wallet screen does the withdrawing.
  Widget _walletCard(Map<String, dynamic> w) {
    num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    final sources = w['earned_by_source'] is Map ? w['earned_by_source'] as Map : const {};
    const labels = {'video_sales': 'Offline video sales', 'reaction_fees': 'Reaction fees'};
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: UkoColors.card,
        border: Border.all(color: UkoColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Wallet', style: TextStyle(color: UkoColors.muted, fontSize: 12, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        Text('KSh ${n(w['balance']).toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final e in sources.entries)
          Text('${labels[e.key] ?? e.key}: KSh ${n(e.value).toStringAsFixed(2)} earned',
              style: const TextStyle(color: UkoColors.muted, fontSize: 13)),
        Text('Withdrawn: KSh ${n(w['withdrawn']).toStringAsFixed(2)}',
            style: const TextStyle(color: UkoColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () async {
            await Nav.push(context, Routes.offlineSales);
            _loadWallet();
          },
          child: const Text('Withdraw to M-PESA / history'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final l = _locations;
    final p = _profile;
    return Scrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text('Your profile', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: UkoColors.yellow)),
            TextButton(onPressed: _load, child: const Text('Retry')),
            const SizedBox(height: 8),
          ],
          if (p != null) ...[_summary(p), const SizedBox(height: 20)],
          if (_wallet != null) ...[_walletCard(_wallet!), const SizedBox(height: 20)],
          if (l != null) ...[
            TextField(
              controller: _username,
              autocorrect: false,
              maxLength: 21,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'e.g. movie_fan254',
                helperText: 'Unique. Your comments are shown under it. 3-20 letters, numbers, _ or .',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            PhoneLocationFields(controller: _place, locations: l),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving || p == null ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: UkoColors.yellow,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(_saving ? 'Saving...' : 'Save', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}
