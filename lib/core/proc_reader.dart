import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

/// Reads process and socket information from `/proc` and `/etc/passwd`.
///
/// [procRoot] and [passwdPath] are configurable so tests can point them at a
/// fake directory tree.
class ProcReader {
  ProcReader({this.procRoot = '/proc', this.passwdPath = '/etc/passwd'});

  final String procRoot;
  final String passwdPath;

  Map<int, String>? _userNames;

  /// Arguments of [pid] from `/proc/<pid>/cmdline` (NUL separated).
  List<String>? readArgv(int pid) {
    try {
      final bytes = File('$procRoot/$pid/cmdline').readAsBytesSync();
      final args = utf8
          .decode(bytes, allowMalformed: true)
          .split('\u0000')
          .where((a) => a.isNotEmpty)
          .toList();
      return args.isEmpty ? null : args;
    } on FileSystemException {
      return null;
    }
  }

  /// Full command line of [pid], arguments joined with spaces.
  String? readCmdline(int pid) => readArgv(pid)?.join(' ');

  /// Real uid of [pid] from the `Uid:` line of `/proc/<pid>/status`.
  int? readUid(int pid) {
    try {
      return parseStatusUid(File('$procRoot/$pid/status').readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  String? readComm(int pid) {
    try {
      return File('$procRoot/$pid/comm').readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  bool isAlive(int pid) => Directory('$procRoot/$pid').existsSync();

  /// The uid Portly runs as.
  int currentUid() => readUidFromStatus('$procRoot/self/status') ?? -1;

  int? readUidFromStatus(String path) {
    try {
      return parseStatusUid(File(path).readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  String? userName(int uid) {
    _userNames ??= _loadPasswd();
    return _userNames![uid];
  }

  Map<int, String> _loadPasswd() {
    try {
      return parsePasswd(File(passwdPath).readAsStringSync());
    } on FileSystemException {
      return {};
    }
  }

  /// Fallback scanner used when `ss` is missing.
  ///
  /// Reads `/proc/net/{tcp,tcp6,udp,udp6}` and maps socket inodes to PIDs by
  /// walking `/proc/*/fd` (only our own processes are visible).
  List<PortEntry> scanProcNet() {
    final entries = <PortEntry>[];
    var readAny = false;
    for (final (file, protocol, v6) in const [
      ('tcp', Protocol.tcp, false),
      ('tcp6', Protocol.tcp, true),
      ('udp', Protocol.udp, false),
      ('udp6', Protocol.udp, true),
    ]) {
      try {
        final text = File('$procRoot/net/$file').readAsStringSync();
        readAny = true;
        entries.addAll(parseProcNet(text, protocol, ipv6: v6));
      } on FileSystemException {
        continue;
      }
    }
    if (!readAny) {
      throw const ScanException('Neither `ss` nor /proc/net is available.');
    }

    final owners = socketOwners();
    return [
      for (final entry in entries)
        if (owners[entry.inode] case final pids?)
          entry.copyWith(
            processes: [
              for (final pid in pids)
                SocketProcess(name: readComm(pid) ?? '?', pid: pid),
            ],
          )
        else
          entry,
    ];
  }

  /// Maps socket inode → PIDs holding it, for every readable `/proc/<pid>/fd`.
  Map<int, List<int>> socketOwners() {
    final owners = <int, List<int>>{};
    final List<FileSystemEntity> procs;
    try {
      procs = Directory(procRoot).listSync(followLinks: false);
    } on FileSystemException {
      return owners;
    }
    for (final proc in procs) {
      final pid = int.tryParse(
        proc.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      );
      if (pid == null) continue;
      try {
        for (final fd in Directory(
          '${proc.path}/fd',
        ).listSync(followLinks: false)) {
          if (fd is! Link) continue;
          final inode = parseSocketLink(fd.targetSync());
          if (inode == null) continue;
          final list = owners.putIfAbsent(inode, () => []);
          if (!list.contains(pid)) list.add(pid);
        }
      } on FileSystemException {
        continue; // another user's process
      }
    }
    return owners;
  }
}

int? parseStatusUid(String status) {
  for (final line in status.split('\n')) {
    if (line.startsWith('Uid:')) {
      final parts = line.substring(4).trim().split(RegExp(r'\s+'));
      return int.tryParse(parts.first);
    }
  }
  return null;
}

Map<int, String> parsePasswd(String text) {
  final names = <int, String>{};
  for (final line in text.split('\n')) {
    final parts = line.split(':');
    if (parts.length < 3) continue;
    final uid = int.tryParse(parts[2]);
    if (uid != null) names.putIfAbsent(uid, () => parts[0]);
  }
  return names;
}

/// `socket:[12345]` → 12345.
int? parseSocketLink(String target) {
  if (!target.startsWith('socket:[') || !target.endsWith(']')) return null;
  return int.tryParse(target.substring(8, target.length - 1));
}

const _tcpListen = '0A';
const _udpUnconnected = '07';

/// Parses one `/proc/net/{tcp,udp}[6]` table, keeping listening TCP sockets
/// and unconnected UDP sockets (what `ss -tul` shows).
List<PortEntry> parseProcNet(
  String text,
  Protocol protocol, {
  required bool ipv6,
}) {
  final entries = <PortEntry>[];
  final lines = text.split('\n');
  for (final line in lines.skip(1)) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 10) continue;
    final state = f[3];
    if (protocol == Protocol.tcp && state != _tcpListen) continue;
    if (protocol == Protocol.udp && state != _udpUnconnected) continue;

    final local = f[1].split(':');
    if (local.length != 2) continue;
    final port = int.tryParse(local[1], radix: 16);
    final address = ipv6 ? decodeIpv6Hex(local[0]) : decodeIpv4Hex(local[0]);
    if (port == null || address == null) continue;

    entries.add(
      PortEntry(
        protocol: protocol,
        state: protocol == Protocol.tcp ? 'LISTEN' : 'UNCONN',
        address: address,
        port: port,
        uid: int.tryParse(f[7]),
        inode: int.tryParse(f[9]),
      ),
    );
  }
  return entries;
}

/// `0100007F` (little-endian) → `127.0.0.1`.
String? decodeIpv4Hex(String hex) {
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ].join('.');
}

/// 32 hex chars, four little-endian 32-bit words → compressed IPv6 text.
String? decodeIpv6Hex(String hex) {
  if (hex.length != 32) return null;
  final bytes = <int>[];
  for (var word = 0; word < 4; word++) {
    final chunk = hex.substring(word * 8, word * 8 + 8);
    for (var b = 3; b >= 0; b--) {
      final byte = int.tryParse(chunk.substring(b * 2, b * 2 + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
  }
  // IPv4-mapped (::ffff:a.b.c.d)
  if (bytes.sublist(0, 10).every((b) => b == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff) {
    return '::ffff:${bytes.sublist(12).join('.')}';
  }
  return InternetAddress.fromRawAddress(
    Uint8List.fromList(bytes),
    type: InternetAddressType.IPv6,
  ).address;
}

/// A readable process name.
///
/// `ss` reports the kernel `comm`, which is cut to 15 characters
/// (`jetbrains-toolb`) and is sometimes a thread name (`MainThread` for
/// node). In those cases the basename of `argv[0]` is clearer.
String betterProcessName(String comm, List<String>? argv) {
  if (argv == null || argv.isEmpty) return comm;
  final base = argv.first.split('/').last;
  if (base.isEmpty || base == comm) return comm;
  if (comm.length >= 15 && base.startsWith(comm)) return base;
  if (comm.endsWith('Thread')) return base;
  return comm;
}
