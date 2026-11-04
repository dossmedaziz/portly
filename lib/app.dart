import 'package:flutter/material.dart';

import 'identity.dart';
import 'ui/home_page.dart';

/// Portly's teal, also used by the app icon.
const _seed = Color(0xFF0E7C86);

class PortlyApp extends StatelessWidget {
  const PortlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        visualDensity: VisualDensity.compact,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.compact,
      ),
      home: const HomePage(),
    );
  }
}
