import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../core/http.dart';
import '../core/theme.dart';
import '../routes.dart';
import '../services/prefs.dart';
import '../services/region.dart';
import '../services/remote.dart';

/// Port of components/home/drawer.tsx (DrawerMenu). Shows the logo, the
/// user's credit balance (CHECK_USER_CREDITS, refreshed every time the drawer
/// opens), the navigation items and SignOut (SIGNOUT with platform "mobile").
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _DrawerItem {
  const _DrawerItem(this.label, this.route, [this.icon, this.color = Colors.white]);
  final String label;
  final String route;
  final IconData? icon;
  final Color color;
}

class _AppDrawerState extends State<AppDrawer> {
  num _coins = 0.0;
  // earn credit / subscribe: only for signed-in users in Kenya, Brazil or Oceania (services/region.dart)
  bool _showCredits = false;
  static const _creditRoutes = {Routes.creditsEarn, Routes.creditsBuy};

  static final _items = [
    _DrawerItem('Home', Routes.home),
    _DrawerItem('search', Routes.search, Icons.search),
    _DrawerItem('movie category', Routes.moviesDiscover, Icons.movie_outlined),
    _DrawerItem('tv category', Routes.tvDiscover, Icons.slideshow_outlined),
    _DrawerItem('eden movies', Routes.edenMovies, Icons.local_movies_outlined, UkoColors.yellow),
    _DrawerItem('eden series', Routes.edenSeries, Icons.live_tv_outlined, UkoColors.yellow),
    _DrawerItem('earn credit', Routes.creditsEarn, FontAwesomeIcons.coins.data),
    _DrawerItem('subscribe', Routes.creditsBuy, FontAwesomeIcons.coins.data, UkoColors.yellow),
    _DrawerItem('following', Routes.following, Icons.account_circle_outlined),
    _DrawerItem('playlist', Routes.playlist, Icons.play_circle_outline),
    _DrawerItem('profile', Routes.profile, Icons.person_outline),
    _DrawerItem('Tv Login', Routes.tvLogin, Icons.format_clear, UkoColors.green),
    _DrawerItem('TV remote', Routes.remotePad, Icons.settings_remote_outlined, UkoColors.yellow),
    _DrawerItem('reactions', Routes.reactions, Icons.groups_outlined, UkoColors.yellow),
  ];

  @override
  void initState() {
    super.initState();
    _checkCoins();
    _checkCreditAccess();
  }

  Future<void> _checkCreditAccess() async {
    final user = await Prefs.user;
    if (user == null || user.isEmpty) return;
    final allowed = await creditsAllowedHere();
    if (allowed && mounted) setState(() => _showCredits = true);
  }

  Future<void> _checkCoins() async {
    final res = await Http.postJson(Api.checkUserCredits, {'username': await Prefs.user});
    if (res is Map && res['sum'] != null && mounted) {
      setState(() => _coins = res['sum'] is num ? res['sum'] as num : num.tryParse('${res['sum']}') ?? 0);
    }
  }

  /// UKOshop's post-ad page and Eden open in the browser, outside the app.
  Future<void> _openExternal(String url) async {
    Navigator.of(context).pop();
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('could not open $url');
    } catch (e) {
      debugPrint('open $url failed: $e');
    }
  }

  Future<void> _customSignout() async {
    final res = await Http.postJson(Api.signout, {'email': await Prefs.user, 'platform': 'mobile'});
    debugPrint('signout: ${res is Map ? res['message'] : res}');
    if (res is Map && res['status'] == true) {
      await Prefs.removeItem(PrefKeys.user);
      await Prefs.removeItem(PrefKeys.token);
      RemoteService.instance.leaveRoom();
      if (!mounted) return;
      Navigator.of(context).pop();
      Nav.resetTo(context, Routes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.7,
      backgroundColor: UkoColors.gray900,
      shape: const RoundedRectangleBorder(),
      //the web sidebar's gradient and right edge
      child: Container(
        decoration: const BoxDecoration(
          gradient: ukoNavGradient,
          border: Border(right: BorderSide(color: UkoColors.border, width: 3)),
        ),
        padding: const EdgeInsets.only(top: 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Image.asset('assets/images/logo.png', height: 100, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.coins, color: UkoColors.yellow, size: 30),
                  const SizedBox(width: 8),
                  Text('$_coins', style: const TextStyle(color: UkoColors.yellow, fontSize: 30)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in _items)
                    if (_showCredits || !_creditRoutes.contains(item.route))
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        if (item.route == Routes.home) {
                          Nav.switchTab(context, Routes.home);
                        } else {
                          Nav.push(context, item.route);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: UkoColors.gray700)),
                        ),
                        child: Row(
                          children: [
                            if (item.icon != null) ...[
                              Icon(item.icon, size: 30, color: item.color),
                              const SizedBox(width: 8),
                            ],
                            Text(item.label, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: () => _openExternal(Api.shopPostAd),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: UkoColors.gray700)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.storefront_outlined, size: 30, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Post an ad', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ElevatedButton(
                      onPressed: () => _openExternal(Api.eden),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UkoColors.yellow,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('launch film content', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: UkoColors.gray700))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: _customSignout,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('SignOut', style: TextStyle(color: UkoColors.gray400, fontSize: 14)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8, bottom: 8),
                          child: Text('Help & Support', style: TextStyle(color: UkoColors.gray400, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
