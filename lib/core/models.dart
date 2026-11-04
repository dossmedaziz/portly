/// Plain data types shared by the scanner, the watcher and the UI.
library;

enum Protocol {
  tcp,
  udp;

  String get label => name.toUpperCase();
}

/// One process holding a socket, as reported by `ss` (`users:((...))`).
class SocketProcess {
  const SocketProcess({required this.name, required this.pid});

  final String name;
  final int pid;

  @override
  bool operator ==(Object other) =>
      other is SocketProcess && other.name == name && other.pid == pid;

  @override
  int get hashCode => Object.hash(name, pid);

  @override
  String toString() => '$name($pid)';
}

/// A listening TCP socket or a bound UDP socket.
class PortEntry {
  const PortEntry({
    required this.protocol,
    required this.state,
    required this.address,
    required this.port,
    this.interface,
    this.processes = const [],
    this.uid,
    this.inode,
    this.cgroup,
    this.user,
    this.command,
    this.revealed = false,
  });

  final Protocol protocol;

  /// Socket state as printed by `ss` (`LISTEN`, `UNCONN`, ...).
  final String state;

  /// Local address without brackets: `0.0.0.0`, `::`, `127.0.0.1`, `*`.
  final String address;

  /// Interface scope (`lo` in `127.0.0.53%lo`), if any.
  final String? interface;

  final int port;

  /// Processes sharing the socket. Empty when the owner is not visible to us.
  final List<SocketProcess> processes;

  /// Owner uid of the socket (from `ss -e` or `/proc/<pid>/status`).
  final int? uid;

  /// Socket inode, used to carry elevated-scan results across refreshes.
  final int? inode;

  /// cgroup path from `ss -e`, e.g. `/system.slice/nginx.service`.
  final String? cgroup;

  /// User name resolved from [uid].
  final String? user;

  /// Full command line from `/proc/<pid>/cmdline`.
  final String? command;

  /// True when the process info came from an elevated (pkexec) scan.
  final bool revealed;

  int? get pid => processes.isEmpty ? null : processes.first.pid;
  String? get processName => processes.isEmpty ? null : processes.first.name;

  /// The owner is not visible to the current user (root or another user).
  bool get restricted => processes.isEmpty;

  /// Processes owned by someone else need pkexec to be signalled.
  bool needsElevation(int currentUid) =>
      restricted || revealed || (uid != null && uid != currentUid);

  bool isOwnedBy(int currentUid) => !needsElevation(currentUid);

  /// The systemd unit name from [cgroup], e.g. `nginx.service`.
  String? get unit {
    final path = cgroup;
    if (path == null) return null;
    final last = path.split('/').last;
    return last.endsWith('.service') || last.endsWith('.socket') ? last : null;
  }

  /// Best label for the owner: process name, systemd unit, or null.
  String? get displayName => processName ?? unit;

  /// Stable identity used to diff snapshots.
  String get key =>
      '${protocol.name}|$address${interface == null ? '' : '%$interface'}|$port';

  /// Reachable over HTTP from this machine.
  bool get isBrowsable =>
      protocol == Protocol.tcp &&
      const {
        '0.0.0.0',
        '127.0.0.1',
        '::',
        '::1',
        '*',
        'localhost',
      }.contains(address);

  PortEntry copyWith({
    List<SocketProcess>? processes,
    int? uid,
    String? user,
    String? command,
    bool? revealed,
  }) {
    return PortEntry(
      protocol: protocol,
      state: state,
      address: address,
      interface: interface,
      port: port,
      processes: processes ?? this.processes,
      uid: uid ?? this.uid,
      inode: inode,
      cgroup: cgroup,
      user: user ?? this.user,
      command: command ?? this.command,
      revealed: revealed ?? this.revealed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PortEntry &&
      other.key == key &&
      other.state == state &&
      other.uid == uid &&
      other.inode == inode &&
      other.user == user &&
      other.command == command &&
      _listEquals(other.processes, processes);

  @override
  int get hashCode => Object.hash(key, state, uid, inode, pid);

  @override
  String toString() => 'PortEntry($key ${processes.join(',')} uid=$uid)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum ScanSource { ss, procNet }

class ScanResult {
  const ScanResult({
    required this.entries,
    required this.source,
    required this.time,
  });

  final List<PortEntry> entries;
  final ScanSource source;
  final DateTime time;
}

/// Raised when neither `ss` nor `/proc/net` could be read.
class ScanException implements Exception {
  const ScanException(this.message);
  final String message;
  @override
  String toString() => message;
}
