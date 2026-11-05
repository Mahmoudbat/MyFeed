import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'vault/vault_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // cryptography_flutter registers itself, so AES-GCM and PBKDF2 run on the
  // platform's hardware-accelerated implementations.
  await AppSettings.instance.load();
  await VaultSession.instance.init();
  runApp(const MyFeedApp());
}

class MyFeedApp extends StatelessWidget {
  const MyFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyFeed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, centerTitle: true),
      ),
      navigatorObservers: [VaultSession.instance.routeObserver],
      home: const HomeScreen(),
    );
  }
}
