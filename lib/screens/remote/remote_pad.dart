import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../services/remote.dart';

/// The phone as the TV's remote control (movies PRD #12): swipe on the pad to move the TV's focus, tap it
/// to select, or use the D-pad and the back / home / play-pause keys. Every press is a `KEY` event into the
/// user's signed remote room (services/remote.dart); the TV app turns it into the same key its own remote
/// would send (tv/uko lib/remote/remote_keys.dart).
class RemotePadScreen extends StatefulWidget {
  const RemotePadScreen({super.key});

  @override
  State<RemotePadScreen> createState() => _RemotePadScreenState();
}

class _RemotePadScreenState extends State<RemotePadScreen> {
  final RemoteService _remote = RemoteService.instance;
  bool? _signedIn;
  Offset _drag = Offset.zero;
  String? _lastKey;

  /// how far a swipe must travel before it counts as a direction, in logical pixels
  static const _swipeDistance = 28.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await Prefs.user;
    final signedIn = user != null && user.isNotEmpty;
    if (signedIn) await _remote.joinRoom();
    if (mounted) setState(() => _signedIn = signedIn);
  }

  Future<void> _send(String key) async {
    HapticFeedback.selectionClick();
    final sent = await _remote.key(key);
    if (!mounted) return;
    setState(() => _lastKey = sent ? key : null);
    if (!sent) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_remote.connected
              ? "Can't reach your TV's remote room. Check your connection, then open this screen again."
              : 'Turn the remote ON first.'),
        ));
    }
  }

  void _endSwipe() {
    final d = _drag;
    _drag = Offset.zero;
    if (d.distance < _swipeDistance) return;
    if (d.dx.abs() > d.dy.abs()) {
      _send(d.dx > 0 ? 'right' : 'left');
    } else {
      _send(d.dy > 0 ? 'down' : 'up');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    return Scaffold(
      backgroundColor: UkoColors.background,
      appBar: AppBar(title: const Text('TV Remote')),
      body: SafeArea(
        child: signedIn == null
            ? const Center(child: CircularProgressIndicator())
            : !signedIn
                ? _signInFirst(context)
                : ListenableBuilder(listenable: _remote, builder: (context, _) => _pad(context)),
      ),
    );
  }

  Widget _signInFirst(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Sign in to use your phone as the TV remote', textAlign: TextAlign.center, style: ukoHeading(fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Nav.push(context, Routes.signIn), child: const Text('Sign in')),
          ]),
        ),
      );

  Widget _pad(BuildContext context) {
    final on = _remote.connected;
    return LayoutBuilder(builder: (context, box) {
      final padSize = (box.maxWidth - 48).clamp(200.0, 360.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(children: [
          // the same ON/OFF as the tab bar's centre button
          Container(
            decoration: BoxDecoration(
              color: UkoColors.card,
              border: Border.all(color: UkoColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SwitchListTile(
              value: on,
              onChanged: (_) => _remote.toggle(),
              activeThumbColor: UkoColors.yellow,
              title: Text('Remote ${on ? 'ON' : 'OFF'}'),
              subtitle: Text(
                on
                    ? (_remote.signedRoom
                        ? 'Controlling the TV signed in to your account'
                        : 'Connected the old way - navigation works, the touchpad needs the updated TV app')
                    : 'Turn on to control the TV signed in to your account',
                style: const TextStyle(color: UkoColors.muted, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: on ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !on,
              child: Column(children: [
                _touchpad(padSize),
                const SizedBox(height: 20),
                _dpad(),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _roundKey('back', Icons.arrow_back, 'Back'),
                  _roundKey('home', Icons.home_outlined, 'Home'),
                  _roundKey('playpause', Icons.play_arrow_outlined, 'Play / pause'),
                ]),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _touchpad(double size) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _send('select'),
        onPanStart: (_) => _drag = Offset.zero,
        onPanUpdate: (d) => _drag += d.delta,
        onPanEnd: (_) => _endSwipe(),
        child: Container(
          width: size,
          height: size * 0.75,
          decoration: BoxDecoration(
            color: UkoColors.card,
            border: Border.all(color: UkoColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.touch_app_outlined, color: UkoColors.muted, size: 32),
            const SizedBox(height: 8),
            const Text('Swipe to move · tap to select', style: TextStyle(color: UkoColors.muted)),
            if (_lastKey != null) ...[
              const SizedBox(height: 6),
              Text(_lastKey!, style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
            ],
          ]),
        ),
      );

  Widget _dpad() {
    Widget arrow(String key, IconData icon) => _squareKey(key, icon, key);
    return Column(children: [
      arrow('up', Icons.keyboard_arrow_up),
      Row(mainAxisSize: MainAxisSize.min, children: [
        arrow('left', Icons.keyboard_arrow_left),
        Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 72,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: UkoColors.yellow,
                foregroundColor: Colors.black,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _send('select'),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        arrow('right', Icons.keyboard_arrow_right),
      ]),
      arrow('down', Icons.keyboard_arrow_down),
    ]);
  }

  Widget _squareKey(String key, IconData icon, String label) => Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 60,
          height: 60,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => _send(key),
            child: Icon(icon, size: 30, semanticLabel: label),
          ),
        ),
      );

  Widget _roundKey(String key, IconData icon, String label) => Column(children: [
        SizedBox(
          width: 56,
          height: 56,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
            onPressed: () => _send(key),
            child: Icon(icon, semanticLabel: label),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: UkoColors.muted, fontSize: 11)),
      ]);
}
