import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../routes.dart';
import '../services/remote.dart';
import 'app_drawer.dart';

enum UkoTab { home, movies, tv, people }

/// Port of components/home/tablayout.tsx + app/(tabs)/_layout.tsx.
///
/// Every (tabs) screen gets the same chrome: a header with the ☰ drawer
/// toggle and the screen title, the slide-in drawer, and the bottom tab bar
/// (Home, Movies, [remote ON/OFF], TV Shows, People). Hidden tabs
/// (`href: null` in RN) render inside the same chrome with no tab selected.
class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.title, required this.child, this.currentTab});
  final String title;
  final Widget child;
  final UkoTab? currentTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => InkWell(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            child: const Center(child: Text('☰', style: TextStyle(color: Colors.white, fontSize: 24))),
          ),
        ),
        title: Text(title),
        shape: const Border(bottom: BorderSide(color: UkoColors.border)),
      ),
      drawer: const AppDrawer(),
      drawerScrimColor: Colors.black.withValues(alpha: 0.5),
      body: child,
      bottomNavigationBar: UkoTabBar(current: currentTab),
    );
  }
}

class UkoTabBar extends StatelessWidget {
  const UkoTabBar({super.key, this.current});
  final UkoTab? current;

  /// Tab press: mirror on the TV when remote mode is on (RN only did this for
  /// Movies / TV Shows / People), then navigate.
  Future<void> _go(BuildContext context, UkoTab tab) async {
    switch (tab) {
      case UkoTab.home:
        Nav.switchTab(context, Routes.home);
      case UkoTab.movies:
        RemoteService.instance.route(TvPaths.movies);
        Nav.switchTab(context, Routes.moviesPage);
      case UkoTab.tv:
        RemoteService.instance.route(TvPaths.tv);
        Nav.switchTab(context, Routes.tvPage);
      case UkoTab.people:
        // phone only - the TV app has no People pages to mirror
        Nav.switchTab(context, Routes.peoplePage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: UkoColors.card,
        border: Border(top: BorderSide(color: UkoColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _item(context, UkoTab.home, Icons.home_outlined, 'Home'),
              _item(context, UkoTab.movies, Icons.movie_outlined, 'Movies'),
              const Expanded(child: _RemoteButton()),
              _item(context, UkoTab.tv, Icons.tv_outlined, 'TV Shows'),
              _item(context, UkoTab.people, Icons.auto_awesome_outlined, 'People'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, UkoTab tab, IconData icon, String label) {
    final active = tab == current;
    final color = active ? UkoColors.text : UkoColors.gray400;
    return Expanded(
      child: InkWell(
        onTap: () => _go(context, tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// The centre "remote ON/OFF" tab button (app/(tabs)/movies/action.tsx is an
/// empty screen whose tab button only toggles the remote, never navigates).
class _RemoteButton extends StatelessWidget {
  const _RemoteButton();

  @override
  Widget build(BuildContext context) {
    final remote = RemoteService.instance;
    return ListenableBuilder(
      listenable: remote,
      builder: (context, _) => Transform.translate(
        offset: const Offset(0, -10),
        child: Material(
          color: Colors.black,
          elevation: 6,
          shape: const StadiumBorder(side: BorderSide(color: UkoColors.yellow, width: 2)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: remote.toggle,
            // long-press: the touchpad / D-pad for the TV (movies PRD #12)
            onLongPress: () => Nav.push(context, Routes.remotePad),
            child: SizedBox(
              height: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('remote', style: TextStyle(color: UkoColors.yellow, fontSize: 18)),
                  Text(remote.connected ? 'ON' : 'OFF', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
