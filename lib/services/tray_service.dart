import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../core/models.dart';
import '../identity.dart';
import 'tray_menu_model.dart';

/// Callbacks the tray menu triggers.
class TrayActions {
  const TrayActions({
    required this.open,
    required this.refresh,
    required this.kill,
    required this.copy,
    required this.setStartOnLogin,
    required this.quit,
  });

  final VoidCallback open;
  final VoidCallback refresh;
  final void Function(PortEntry entry) kill;
  final void Function(String text) copy;
  final void Function(bool enabled) setStartOnLogin;
  final VoidCallback quit;
}

/// The Portly status-notifier icon and its menu.
///
/// On GNOME (AppIndicator extension) clicking the icon always opens the menu;
/// there is no usable click event, so every action lives in the menu.
class TrayService {
  TrayService(this._actions);

  final TrayActions _actions;
  TrayIcon? _icon;
  Menu? _menu;
  TrayMenuModel? _model;

  // Native menu items must stay referenced while attached.
  final List<Object> _keepAlive = [];

  bool get isAvailable => _icon != null;

  Future<void> init({required double devicePixelRatio}) async {
    try {
      final icon = TrayIcon.create();
      if (icon == null) throw StateError('TrayIcon.create() returned null');
      final asset = devicePixelRatio > 1.25
          ? 'assets/icons/portly_tray_32.png'
          : 'assets/icons/portly_tray_22.png';
      icon.icon = ImageAsset.fromAsset(asset);
      icon.setTooltip(appName);
      icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      icon.setVisible(true);
      _icon = icon;
    } catch (e) {
      debugPrint('Tray icon unavailable: $e');
    }
  }

  /// Rebuilds the menu only if [model] differs from what is shown.
  void update(TrayMenuModel model) {
    final icon = _icon;
    if (icon == null || model == _model) return;
    _model = model;

    final old = _menu;
    final oldItems = [..._keepAlive];
    _keepAlive.clear();

    final menu = _newMenu();
    _add(menu, model.header, enabled: false);
    menu.addSeparator();

    if (model.processes.isEmpty) {
      _add(menu, 'No ports opened by you', enabled: false);
    }
    for (final p in model.processes) {
      final sub = _newMenu();
      _add(sub, 'Kill', onClick: () => _actions.kill(p.entry));
      _add(sub, 'Copy port', onClick: () => _actions.copy('${p.entry.port}'));
      _add(sub, 'Copy PID', onClick: () => _actions.copy('${p.entry.pid}'));
      final item = _add(menu, p.label, type: MenuItemType.submenu);
      item.submenu = sub;
    }

    if (model.favorites.isNotEmpty) {
      menu.addSeparator();
      _add(menu, 'Favorites', enabled: false);
      for (final f in model.favorites) {
        _add(menu, '${f.open ? '●' : '○'}  ${f.label}', enabled: false);
      }
    }

    menu.addSeparator();
    _add(menu, 'Open $appName', onClick: _actions.open);
    _add(menu, 'Refresh now', onClick: _actions.refresh);
    final login = _add(menu, 'Start on login', type: MenuItemType.checkbox);
    login.state = model.startOnLogin
        ? MenuItemState.checked
        : MenuItemState.unchecked;
    _listen(login, () => _actions.setStartOnLogin(!model.startOnLogin));
    menu.addSeparator();
    _add(menu, 'Quit $appName', onClick: _actions.quit);

    icon.setContextMenu(menu);
    _menu = menu;

    // Let the panel switch to the new menu before freeing the old one.
    Timer(const Duration(seconds: 1), () {
      for (final o in oldItems) {
        if (o is MenuItem) o.dispose();
      }
      old?.dispose();
    });
  }

  Menu _newMenu() {
    final menu = Menu.create();
    if (menu == null) throw StateError('Menu.create() returned null');
    _keepAlive.add(menu);
    return menu;
  }

  MenuItem _add(
    Menu menu,
    String label, {
    MenuItemType type = MenuItemType.normal,
    bool enabled = true,
    VoidCallback? onClick,
  }) {
    final item = MenuItem.createWithLabelAndType(label, type);
    if (item == null) throw StateError('MenuItem.create failed for $label');
    item.isEnabled = enabled;
    if (onClick != null) _listen(item, onClick);
    menu.addItem(item);
    _keepAlive.add(item);
    return item;
  }

  void _listen(MenuItem item, VoidCallback onClick) {
    item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
  }

  void dispose() {
    _icon?.setVisible(false);
    _icon?.dispose();
    _icon = null;
  }
}
