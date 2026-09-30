// Port of mobile/app/(tabs)/home.tsx, with the web app's phone layout
// (web-app/src/components/home.jsx under 800px): a sticky "Mini series |
// Blockbusters" switch. Both tabs are the same full-screen vertical swiper of
// auto-playing videos: Mini series feeds it Eden reels (miniseries.dart);
// Blockbusters feeds it the muted trailers that BLOCKBUSTER (now playing movies)
// and BOX (airing tv) resolve.
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'blockbuster.dart';
import 'box.dart';
import 'miniseries.dart';
import 'trailer_swiper.dart';

enum _HomeTab { eden, blockbuster }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Map<String, dynamic>> _validated = [];

  //phones show one list at a time - Eden mini series or the blockbuster trailers
  _HomeTab _tab = _HomeTab.eden;

  // RN kept this in `clip` state for a player that is commented out.
  void _findClip(String index) {}

  void _mobileValidation(List<Map<String, dynamic>> validData) {
    if (!mounted) return;
    final newItems = validData.where((v) => !_validated.any((p) => p['key'] == v['key'])).toList();
    if (newItems.isEmpty) return;
    setState(() => _validated.addAll(newItems));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Both render nothing (CLIPS returns false in RN); they only feed the swiper,
        // and keep loading while the mini series tab is showing.
        SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              SizedBox(
                height: 250,
                width: double.infinity,
                child: Blockbuster(setClip: _findClip, mobileView: _mobileValidation),
              ),
              SizedBox(
                height: 250,
                width: double.infinity,
                child: Box(setClip: _findClip, mobileView: _mobileValidation),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              children: [
                _TabSwitch(current: _tab, onChanged: (t) => setState(() => _tab = t)),
                Expanded(
                  // like the web, only the open tab is mounted - a hidden player would keep playing
                  child: _tab == _HomeTab.eden
                      ? const MiniSeriesFeed()
                      : _validated.isEmpty
                          ? const LoadingView()
                          : TrailerSwiper(items: List.unmodifiable(_validated)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabSwitch extends StatelessWidget {
  const _TabSwitch({required this.current, required this.onChanged});
  final _HomeTab current;
  final ValueChanged<_HomeTab> onChanged;

  static const _labels = {_HomeTab.eden: 'Mini series', _HomeTab.blockbuster: 'Blockbusters'};

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE60D0D0D), // bg-[#0d0d0d]/90
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final tab in _HomeTab.values) ...[
            if (tab != _HomeTab.values.first) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                selected: tab == current,
                button: true,
                child: OutlinedButton(
                  onPressed: () => onChanged(tab),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: tab == current ? UkoColors.yellow : UkoColors.divider,
                    side: BorderSide(color: tab == current ? UkoColors.yellow : UkoColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  child: Text(_labels[tab]!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
