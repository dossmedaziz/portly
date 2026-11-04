import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../core/port_watcher.dart';
import '../identity.dart';

/// Desktop notifications through libnotify, gated by the user's setting.
class NotificationService {
  NotificationService({required this.isEnabled});

  final bool Function() isEnabled;
  bool _ready = false;

  Future<void> init() async {
    try {
      await localNotifier.setup(appName: appName);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<void> show(String title, [String? body]) async {
    if (!_ready || !isEnabled()) return;
    try {
      await LocalNotification(title: title, body: body).show();
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  Future<void> favorite(FavoriteChange change) => show(
    change.opened
        ? 'Port ${change.port} is now in use'
              '${change.owner == null ? '' : ' by ${change.owner}'}'
        : 'Port ${change.port} is now free',
  );
}
