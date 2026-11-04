import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/actions.dart';
import 'providers/providers.dart';
import 'services/app_controller.dart';
import 'services/desktop_integration.dart';
import 'services/settings_service.dart';
import 'services/single_instance.dart';
import 'services/tray_service.dart';
import 'services/window_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startHidden = args.contains('--hidden');

  final window = WindowService();
  final instance = SingleInstance();
  final primary = await instance.acquire(
    onCommand: (command) {
      if (command == 'show') window.show();
    },
  );
  if (!primary) {
    // Portly is already running and has been asked to show its window.
    exit(0);
  }

  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(await SettingsService.create()),
    ],
  );
  window.init(startHidden: startHidden);

  // Dock / Alt+Tab icon for AppImage and dev builds (the .deb ships its own).
  unawaited(
    DesktopIntegration(
      loadAsset: (asset) async =>
          (await rootBundle.load(asset)).buffer.asUint8List(),
    ).ensure().catchError((Object e) {
      debugPrint('Desktop integration skipped: $e');
      return false;
    }),
  );

  final notifications = container.read(notificationServiceProvider);
  await notifications.init();

  late final AppController controller;
  final tray = TrayService(
    TrayActions(
      open: window.show,
      refresh: () => container.read(portsProvider.notifier).refresh(),
      kill: (entry) => controller.killFromTray(entry),
      copy: (text) => container.read(actionsProvider).copy(text),
      setStartOnLogin: (enabled) {
        final settings = container.read(settingsProvider.notifier);
        settings.update(
          container.read(settingsProvider).copyWith(startOnLogin: enabled),
        );
      },
      quit: () async {
        controller.dispose();
        container.dispose();
        await instance.release();
        exit(0);
      },
    ),
  );
  await tray.init(
    devicePixelRatio:
        PlatformDispatcher.instance.displays.firstOrNull?.devicePixelRatio ?? 1,
  );

  controller = AppController(container, tray, notifications)..start();

  runApp(
    UncontrolledProviderScope(container: container, child: const PortlyApp()),
  );

  // Without a tray icon a hidden window could never be reopened.
  if (startHidden && !tray.isAvailable) window.show();
}
