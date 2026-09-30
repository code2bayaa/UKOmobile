import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/env.dart';
import '../../services/prefs.dart';
import '../../widgets/common.dart';

/// Port of app/(tabs)/credits/buy.tsx.
///
/// The RN screen is only a WebView on `${HOST}/subscribe/${user}` (dev) /
/// `${HOST_LIVE}/subscribe/${user}` — all the M-PESA / PayPal code in that
/// file is commented out, so the payment flows live on the web page and are
/// not re-implemented natively here.
class BuyCreditsScreen extends StatefulWidget {
  const BuyCreditsScreen({super.key});

  @override
  State<BuyCreditsScreen> createState() => _BuyCreditsScreenState();
}

class _BuyCreditsScreenState extends State<BuyCreditsScreen> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await Prefs.user;
    if (!mounted) return;
    final url = '${Api.host}/subscribe/$user';
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    final uri = Uri.tryParse(url);
    if (uri != null) c.loadRequest(uri);
    setState(() => _controller = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const LoadingView();
    return WebViewWidget(controller: c);
  }
}
