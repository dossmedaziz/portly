import 'models.dart';

final _whitespace = RegExp(r'\s+');
final _user = RegExp(r'\("((?:[^"\\]|\\.)*)",pid=(\d+),fd=\d+\)');
final _uid = RegExp(r'(?:^|\s)uid:(\d+)');
final _inode = RegExp(r'(?:^|\s)ino:(\d+)');
final _cgroup = RegExp(r'(?:^|\s)cgroup:(\S+)');

/// Parses the output of `ss -tulpnH` (optionally with `-e`).
///
/// Lines look like:
/// `tcp LISTEN 0 511 127.0.0.1:6379 0.0.0.0:* users:(("redis",pid=9,fd=6)) uid:112 ino:27362 ...`
List<PortEntry> parseSsOutput(String output) {
  final entries = <PortEntry>[];
  for (final line in output.split('\n')) {
    final entry = parseSsLine(line);
    if (entry != null) entries.add(entry);
  }
  return entries;
}

PortEntry? parseSsLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final fields = trimmed.split(_whitespace);
  if (fields.length < 6) return null;

  final protocol = switch (fields[0]) {
    'tcp' => Protocol.tcp,
    'udp' => Protocol.udp,
    _ => null,
  };
  if (protocol == null) return null;

  final local = parseSocketAddress(fields[4]);
  if (local == null) return null;

  // Everything after the peer column: users:(...), uid:, ino:, cgroup:, ...
  final extras = fields.skip(6).join(' ');

  final processes = <SocketProcess>[];
  final seenPids = <int>{};
  for (final match in _user.allMatches(extras)) {
    final pid = int.parse(match.group(2)!);
    if (seenPids.add(pid)) {
      processes.add(SocketProcess(name: _unescape(match.group(1)!), pid: pid));
    }
  }

  // `ss -e` omits `uid:` for root-owned sockets, so a missing uid means 0
  // whenever the line has the other extended fields.
  final hasExtended = _inode.hasMatch(extras);
  final uidMatch = _uid.firstMatch(extras);
  final uid = uidMatch != null
      ? int.parse(uidMatch.group(1)!)
      : (hasExtended ? 0 : null);

  return PortEntry(
    protocol: protocol,
    state: fields[1],
    address: local.address,
    interface: local.interface,
    port: local.port,
    processes: processes,
    uid: uid,
    inode: hasExtended ? int.parse(_inode.firstMatch(extras)!.group(1)!) : null,
    cgroup: _cgroup.firstMatch(extras)?.group(1),
  );
}

typedef SocketAddress = ({String address, String? interface, int port});

/// Splits `127.0.0.53%lo:53`, `[::1]:323`, `[fe80::1]%wlo1:546`, `*:5353`.
SocketAddress? parseSocketAddress(String raw) {
  final colon = raw.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(raw.substring(colon + 1));
  if (port == null) return null;

  var host = raw.substring(0, colon);
  String? interface;
  final percent = host.lastIndexOf('%');
  if (percent > 0 && !host.endsWith(']')) {
    interface = host.substring(percent + 1);
    host = host.substring(0, percent);
  }
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return (address: host, interface: interface, port: port);
}

String _unescape(String name) => name.replaceAll(r'\"', '"');
