import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../identity.dart';

Future<void> showPortlyAbout(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: appName,
    applicationVersion: info.version,
    applicationIcon: Image.asset(
      'assets/icons/portly_128.png',
      width: 64,
      height: 64,
    ),
    applicationLegalese: '$license\n© 2026 dosss',
    children: [const SizedBox(height: 16), const Text(tagline)],
  );
}
