import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/port_watcher.dart';
import '../providers/actions.dart';
import '../providers/providers.dart';
import 'settings_service.dart';
import 'notification_service.dart';
import 'tray_menu_model.dart';
import 'tray_service.dart';

/// Connects the port watcher to the tray menu and to notifications.
class AppController {
  AppController(this._container, this._tray, this._notifications);

  final ProviderContainer _container;
  final TrayService _tray;
  final NotificationService _notifications;

  StreamSubscription<WatchEvent>? _events;
  ProviderSubscription<Settings>? _settings;
  List<PortEntry> _entries = const [];

  void start() {
    _events = _container.read(portsProvider.notifier).events.listen(_onEvent);
    _settings = _container.listen(settingsProvider, (_, _) => _updateTray());
    _updateTray();
  }

  void _onEvent(WatchEvent event) {
    final previous = _entries;
    _entries = event.result.entries;
    if (event.changes != null) {
      final favorites = _container.read(settingsProvider).favorites;
      for (final change in favoriteChanges(previous, _entries, favorites)) {
        _notifications.favorite(change);
      }
    }
    _updateTray();
  }

  void _updateTray() {
    final settings = _container.read(settingsProvider);
    _tray.update(
      buildTrayMenuModel(
        entries: _entries,
        currentUid: _container.read(currentUidProvider),
        favorites: settings.favorites,
        startOnLogin: settings.startOnLogin,
      ),
    );
  }

  /// Tray "Kill": only offered for the user's own processes, so no dialog.
  Future<void> killFromTray(PortEntry entry) =>
      _container.read(actionsProvider).kill(entry);

  void dispose() {
    _events?.cancel();
    _settings?.close();
  }
}
