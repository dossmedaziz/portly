import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import '../identity.dart';

/// The main window: closing hides it to the tray, only "Quit" exits.
class WindowService {
  Window? _window;
  bool _centered = false;

  void init({required bool startHidden}) {
    final manager = WindowManager.instance;
    final window = manager.getCurrent() ?? manager.getAll().firstOrNull;
    if (window == null) return;
    _window = window;

    window.title = appName;
    window.minimumSize = const Size(820, 480).toNative();
    window.addListener((event) {
      if (event is WindowCloseRequestedEvent) {
        event.request.cancel();
        window.hide();
      }
    });
    if (!startHidden) _centerOnce();
  }

  void show() {
    final window = _window;
    if (window == null) return;
    _centerOnce();
    window.show();
    window.focus();
  }

  void hide() => _window?.hide();

  // Wayland does not let clients position windows (and there is no way to
  // place it under the tray icon), so center it once and leave it be.
  void _centerOnce() {
    if (_centered) return;
    _centered = true;
    _window?.center();
  }
}
