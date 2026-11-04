import 'dart:io';

import '../identity.dart';
import 'launch_command.dart';

/// Manages `~/.config/autostart/dev.dosss.portly.desktop`.
///
/// Written directly rather than through launch_at_startup so the entry has
/// the real app name, icon and `Exec=portly --hidden`.
class AutostartService {
  AutostartService({
    this._configHome,
    String? executable,
    Map<String, String>? env,
  }) : _env = env ?? Platform.environment,
       _executable = executable ?? Platform.resolvedExecutable;

  final Map<String, String> _env;
  final String _executable;
  final String? _configHome;

  File get file {
    final config =
        _configHome ?? _env['XDG_CONFIG_HOME'] ?? '${_env['HOME']}/.config';
    return File('$config/autostart/$applicationId.desktop');
  }

  bool get isEnabled => file.existsSync();

  Future<void> setEnabled(bool enabled, {bool hidden = true}) async {
    if (!enabled) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(desktopEntry(hidden: hidden));
  }

  /// The command autostart should run.
  String get launchCommand =>
      launchCommandFor(env: _env, executable: _executable);

  String desktopEntry({required bool hidden}) =>
      '''
[Desktop Entry]
Type=Application
Name=$appName
Comment=$tagline
Exec=$launchCommand${hidden ? ' --hidden' : ''}
Icon=$iconName
Terminal=false
StartupNotify=false
StartupWMClass=$applicationId
X-GNOME-Autostart-enabled=true
''';
}
