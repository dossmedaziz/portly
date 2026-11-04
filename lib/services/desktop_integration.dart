import 'dart:io';
import 'dart:typed_data';

import '../identity.dart';
import 'launch_command.dart';

/// Loads a bundled asset (rootBundle in the app, a fake in tests).
typedef AssetLoader = Future<Uint8List> Function(String asset);

/// Gives an AppImage or development build its icon in the dock, Alt+Tab
/// and the app grid.
///
/// GNOME on Wayland takes a window's icon from the `.desktop` file named
/// after its app id (`dev.dosss.portly`), not from the window. The .deb
/// installs one system-wide; other builds get a per-user copy in
/// `~/.local/share`, removed again once the .deb is installed.
class DesktopIntegration {
  DesktopIntegration({
    required this._loadAsset,
    Map<String, String>? env,
    String? executable,
  }) : _env = env ?? Platform.environment,
       _executable = executable ?? Platform.resolvedExecutable;

  final AssetLoader _loadAsset;
  final Map<String, String> _env;
  final String _executable;

  /// Marks entries Portly wrote itself, so only those are ever replaced.
  static const marker = 'X-Portly-Local=true';
  static const iconSizes = [128, 256, 512];

  String get _dataHome =>
      _env['XDG_DATA_HOME'] ?? '${_env['HOME']}/.local/share';

  List<String> get _systemDataDirs {
    final dirs = _env['XDG_DATA_DIRS'];
    return (dirs == null || dirs.isEmpty)
        ? const ['/usr/local/share', '/usr/share']
        : dirs.split(':').where((d) => d.isNotEmpty).toList();
  }

  File get desktopFile =>
      File('$_dataHome/applications/$applicationId.desktop');

  File iconFile(int size) =>
      File('$_dataHome/icons/hicolor/${size}x$size/apps/$iconName.png');

  /// A system-wide install (the .deb) already provides the entry and icons.
  bool get isSystemInstalled => _systemDataDirs.any(
    (dir) => File('$dir/applications/$applicationId.desktop').existsSync(),
  );

  String desktopEntry() =>
      '''
[Desktop Entry]
Type=Application
Name=$appName
GenericName=Port Manager
Comment=$tagline
Exec=${launchCommandFor(env: _env, executable: _executable)}
Icon=$iconName
Terminal=false
StartupNotify=true
StartupWMClass=$applicationId
Categories=System;Utility;Network;
Keywords=port;socket;process;kill;network;localhost;
$marker
''';

  /// Installs or refreshes the per-user entry and icons. Returns true if
  /// anything on disk changed.
  Future<bool> ensure() async {
    final local = desktopFile;
    final ours =
        !local.existsSync() || local.readAsStringSync().contains(marker);

    if (isSystemInstalled) {
      // Drop our copy so it does not shadow the packaged one.
      if (local.existsSync() && ours) {
        await local.delete();
        return true;
      }
      return false;
    }
    if (!ours) return false; // the user wrote their own entry

    var changed = false;
    for (final size in iconSizes) {
      final file = iconFile(size);
      if (file.existsSync()) continue;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        await _loadAsset('assets/icons/portly_$size.png'),
      );
      changed = true;
    }

    final entry = desktopEntry();
    if (!local.existsSync() || local.readAsStringSync() != entry) {
      await local.parent.create(recursive: true);
      await local.writeAsString(entry);
      changed = true;
    }
    if (changed) await _refreshDesktopDatabase();
    return changed;
  }

  Future<void> _refreshDesktopDatabase() async {
    try {
      await Process.run('update-desktop-database', [
        '-q',
        '$_dataHome/applications',
      ]);
    } on ProcessException {
      // Optional; GNOME also watches the directory.
    }
  }
}
