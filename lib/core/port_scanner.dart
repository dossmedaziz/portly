import 'command_runner.dart';
import 'models.dart';
import 'proc_reader.dart';
import 'ss_parser.dart';

/// Arguments for `ss`: TCP+UDP, listening, numeric, with processes, extended
/// info (uid, inode, cgroup) and no header.
const ssArguments = ['-tulpneH'];

/// Thrown when the user dismisses the pkexec password prompt.
class ElevationCancelled implements Exception {
  const ElevationCancelled();
  @override
  String toString() => 'Authentication was cancelled.';
}

class PortScanner {
  PortScanner({
    this._runner = const ProcessCommandRunner(),
    ProcReader? proc,
    DateTime Function()? clock,
  }) : _proc = proc ?? ProcReader(),
       _clock = clock ?? DateTime.now;

  final CommandRunner _runner;
  final ProcReader _proc;
  final DateTime Function() _clock;

  /// Process info learned from the last elevated scan, keyed by socket inode.
  /// Applied to later unprivileged scans while the socket still exists.
  final Map<int, List<SocketProcess>> _revealed = {};

  ProcReader get proc => _proc;

  /// Scans with `ss`, falling back to `/proc/net` if `ss` is missing.
  Future<ScanResult> scan() async {
    List<PortEntry> entries;
    ScanSource source;
    try {
      final result = await _runner.run('ss', ssArguments);
      if (!result.ok) {
        throw ScanException('ss failed: ${result.stderr.trim()}');
      }
      entries = parseSsOutput(result.stdout);
      source = ScanSource.ss;
    } on CommandNotFound {
      entries = _proc.scanProcNet();
      source = ScanSource.procNet;
    }
    entries = _applyRevealed(entries);
    return ScanResult(
      entries: _enrich(entries),
      source: source,
      time: _clock(),
    );
  }

  /// Runs `pkexec ss` once to reveal processes owned by root or other users.
  Future<ScanResult> elevatedScan() async {
    final CommandResult result;
    try {
      result = await _runner.run('pkexec', ['ss', ...ssArguments]);
    } on CommandNotFound {
      throw const ScanException('pkexec is not installed.');
    }
    if (isPkexecCancelled(result.exitCode)) throw const ElevationCancelled();
    if (!result.ok) {
      throw ScanException('Elevated scan failed: ${result.stderr.trim()}');
    }

    final currentUid = _proc.currentUid();
    final entries = parseSsOutput(result.stdout);
    _revealed.clear();
    for (final e in entries) {
      if (e.inode != null && e.processes.isNotEmpty && e.uid != currentUid) {
        _revealed[e.inode!] = e.processes;
      }
    }
    return scan();
  }

  List<PortEntry> _applyRevealed(List<PortEntry> entries) {
    if (_revealed.isEmpty) return entries;
    final live = <int>{};
    final result = [
      for (final e in entries)
        if (e.restricted && _revealed[e.inode] != null)
          e.copyWith(processes: _revealed[e.inode], revealed: true)
        else
          e,
    ];
    for (final e in entries) {
      if (e.inode != null) live.add(e.inode!);
    }
    _revealed.removeWhere((inode, _) => !live.contains(inode));
    return result;
  }

  List<PortEntry> _enrich(List<PortEntry> entries) {
    return [
      for (final e in entries)
        () {
          final pid = e.pid;
          final uid = e.uid ?? (pid == null ? null : _proc.readUid(pid));
          final argv = pid == null ? null : _proc.readArgv(pid);
          return e.copyWith(
            uid: uid,
            user: uid == null ? null : (_proc.userName(uid) ?? '$uid'),
            command: argv?.join(' '),
            processes: [
              for (final p in e.processes)
                SocketProcess(
                  name: p.pid == pid ? betterProcessName(p.name, argv) : p.name,
                  pid: p.pid,
                ),
            ],
          );
        }(),
    ];
  }
}
