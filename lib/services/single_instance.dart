import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ensures one Portly per session through a Unix socket at
/// `$XDG_RUNTIME_DIR/portly.sock`.
///
/// The first instance listens on the socket. A later instance connects,
/// sends `show`, and exits, and the first instance brings its window back.
class SingleInstance {
  SingleInstance({String? socketPath})
    : socketPath = socketPath ?? defaultSocketPath();

  final String socketPath;
  ServerSocket? _server;

  static String defaultSocketPath() {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final dir = (runtime != null && runtime.isNotEmpty)
        ? runtime
        : '${Directory.systemTemp.path}/portly-${Platform.environment['USER'] ?? 'user'}';
    return '$dir/portly.sock';
  }

  InternetAddress get _address =>
      InternetAddress(socketPath, type: InternetAddressType.unix);

  /// Returns true if this process is the primary instance. Otherwise the
  /// running instance has been asked to show itself and the caller should exit.
  Future<bool> acquire({
    required void Function(String command) onCommand,
  }) async {
    if (await _notifyExisting('show')) return false;

    // No one answered: any socket file left over is stale.
    final file = File(socketPath);
    if (_exists) file.deleteSync();
    await file.parent.create(recursive: true);

    try {
      _server = await ServerSocket.bind(_address, 0);
    } on SocketException {
      // Lost a race with another instance starting at the same moment.
      return !(await _notifyExisting('show'));
    }
    _server!.listen((client) {
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onCommand, onError: (_) {}, cancelOnError: true);
    });
    return true;
  }

  // File.existsSync() is false for sockets, so check the entry type instead.
  bool get _exists =>
      FileSystemEntity.typeSync(socketPath, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<bool> _notifyExisting(String command) async {
    if (!_exists) return false;
    try {
      final socket = await Socket.connect(
        _address,
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.writeln(command);
      await socket.flush();
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> release() async {
    await _server?.close();
    _server = null;
    try {
      File(socketPath).deleteSync();
    } on FileSystemException {
      // already gone
    }
  }
}
