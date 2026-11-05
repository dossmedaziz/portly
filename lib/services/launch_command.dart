import '../identity.dart';

/// The command that starts this copy of Portly, for `.desktop` files.
///
/// A snap uses its stable `/snap/bin` launcher (the path inside `/snap`
/// changes with every revision); installed builds (deb, under /usr or /opt)
/// use `portly` from PATH; an AppImage uses its own path; a dev build uses
/// the absolute binary path.
String launchCommandFor({
  required Map<String, String> env,
  required String executable,
}) {
  final snap = env['SNAP_NAME'];
  if (snap != null && snap.isNotEmpty) return '/snap/bin/$snap';
  final appImage = env['APPIMAGE'];
  if (appImage != null && appImage.isNotEmpty) return _quote(appImage);
  if (executable.startsWith('/usr/') || executable.startsWith('/opt/')) {
    return binaryName;
  }
  return _quote(executable);
}

String _quote(String path) =>
    path.contains(' ') ? '"${path.replaceAll('"', r'\"')}"' : path;
