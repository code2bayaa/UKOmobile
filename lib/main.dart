import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'routes.dart';
import 'services/keys.dart';
import 'services/remote.dart';

/// Port of app/_layout.tsx: providers (keys, remote), dark theme, the root
/// stack, and the socket connection that the RN app opened at import time.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // RN: userInterfaceStyle "dark", orientation "portrait".
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: UkoColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // KeyProvider: fetch safe keys in the background; screens await `ready`.
  KeyService.instance.loadKeys();
  // SOCKETS.connect() + RemoteProvider.
  RemoteService.instance.init();

  runApp(const UkoApp());
}

class UkoApp extends StatelessWidget {
  const UkoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<KeyService>.value(value: KeyService.instance),
        ChangeNotifierProvider<RemoteService>.value(value: RemoteService.instance),
      ],
      child: MaterialApp(
        title: 'UKO',
        debugShowCheckedModeBanner: false,
        theme: buildUkoTheme(),
        darkTheme: buildUkoTheme(),
        themeMode: ThemeMode.dark,
        initialRoute: Routes.signIn,
        onGenerateRoute: onGenerateRoute,
      ),
    );
  }
}
