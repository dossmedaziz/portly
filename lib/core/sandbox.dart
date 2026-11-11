import 'command_runner.dart';
import 'models.dart';

/// Where Portly runs, and what that allows.
///
/// The Snap Store build is a strict snap: it cannot run pkexec, so processes
/// of other users are not stopped from inside Portly; it shows the `sudo`
/// command to run instead. Stopping the user's own processes needs the
/// `process-control` interface, which users connect once by hand.
class Sandbox {
  const Sandbox({this.snapName});

  /// Not sandboxed (deb, AppImage, development build).
  const Sandbox.none() : snapName = null;

  factory Sandbox.detect(Map<String, String> env) {
    final name = env['SNAP_NAME'];
    return Sandbox(snapName: (name == null || name.isEmpty) ? null : name);
  }

  final String? snapName;

  bool get isSnap => snapName != null;

  /// pkexec (password prompt, elevated scan) is available.
  bool get canElevate => !isSnap;

  String get connectProcessControl => 'snap connect $snapName:process-control';

  /// Whether Portly may signal processes. Always true outside a snap; in a
  /// snap it asks `snapctl` whether process-control is connected.
  Future<bool> canSignal(CommandRunner runner) async {
    if (!isSnap) return true;
    try {
      final result = await runner.run('snapctl', [
        'is-connected',
        'process-control',
      ]);
      return result.ok;
    } on CommandNotFound {
      return false;
    }
  }
}

/// The command a user can run in a terminal to stop the owner of [entry]
/// when Portly itself cannot (root or other-user processes in a snap).
///
/// A systemd unit is stopped with systemctl, which also covers socket
/// activation (PID 1); a known PID is killed; otherwise the PID is looked up.
String sudoStopCommand(PortEntry entry) {
  final unit = entry.unit;
  if (unit != null) return 'sudo systemctl stop $unit';
  final pid = entry.pid;
  if (pid != null && pid > 1) return 'sudo kill $pid';
  final proto = entry.protocol.name;
  return "sudo ss -${proto[0]}lpn 'sport = :${entry.port}'";
}
