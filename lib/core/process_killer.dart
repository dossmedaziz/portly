import 'dart:io' as io;

import 'command_runner.dart';

enum KillOutcome {
  /// The process exited.
  terminated,

  /// SIGTERM was sent but the process is still alive after the grace period.
  stillRunning,

  /// The user dismissed the pkexec password prompt.
  cancelled,

  /// Portly refuses to signal this PID (PID 1, itself).
  refused,

  /// `kill` failed (permission denied, no such process, ...).
  failed,
}

class KillResult {
  const KillResult(this.outcome, [this.message]);

  final KillOutcome outcome;
  final String? message;

  bool get success => outcome == KillOutcome.terminated;
}

enum KillSignal {
  term('TERM'),
  kill('KILL');

  const KillSignal(this.flag);
  final String flag;
}

/// Names of processes that are part of the running system; killing them
/// needs an extra warning.
const systemProcessPatterns = <String>[
  'systemd*',
  'init',
  'sshd',
  'NetworkManager',
  'gdm*',
  'gnome-shell',
  'gnome-session*',
  'Xorg',
  'Xwayland',
  'dbus*',
  'polkitd',
  'cupsd',
  'cups-browsed',
  'avahi-daemon',
  'wpa_supplicant',
  'pipewire*',
  'wireplumber',
  'pulseaudio',
  'chronyd',
  'snapd',
  'dockerd',
  'containerd',
  'rpcbind',
  'dnsmasq',
];

bool isSystemProcess(String? name) {
  if (name == null) return false;
  for (final pattern in systemProcessPatterns) {
    if (pattern.endsWith('*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      if (name.startsWith(prefix)) return true;
    } else if (name == pattern) {
      return true;
    }
  }
  return false;
}

/// Sends signals to processes, via pkexec when they belong to someone else.
class ProcessKiller {
  ProcessKiller({
    this._runner = const ProcessCommandRunner(),
    required this._isAlive,
    int? ownPid,
    Future<void> Function(Duration)? sleep,
    this.gracePeriod = const Duration(seconds: 3),
    this.pollInterval = const Duration(milliseconds: 100),
  }) : _ownPid = ownPid ?? io.pid,
       _sleep = sleep ?? Future<void>.delayed;

  final CommandRunner _runner;
  final bool Function(int pid) _isAlive;
  final int _ownPid;
  final Future<void> Function(Duration) _sleep;
  final Duration gracePeriod;
  final Duration pollInterval;

  /// Why [pid] must never be signalled, or null if it may be.
  String? refusalReason(int pid) {
    if (pid <= 1) {
      return 'PID $pid is the init process (systemd). If it holds a port, '
          'that is socket activation: stop the .socket unit with systemctl.';
    }
    if (pid == _ownPid) return 'That is Portly itself.';
    return null;
  }

  /// SIGTERM, then wait up to [gracePeriod] for the process to exit.
  Future<KillResult> terminate(int pid, {bool elevated = false}) =>
      _signal(pid, KillSignal.term, elevated: elevated, wait: gracePeriod);

  /// SIGKILL, then a short wait to confirm.
  Future<KillResult> forceKill(int pid, {bool elevated = false}) => _signal(
    pid,
    KillSignal.kill,
    elevated: elevated,
    wait: const Duration(seconds: 1),
  );

  Future<KillResult> _signal(
    int pid,
    KillSignal signal, {
    required bool elevated,
    required Duration wait,
  }) async {
    final refusal = refusalReason(pid);
    if (refusal != null) return KillResult(KillOutcome.refused, refusal);

    final args = ['-${signal.flag}', '$pid'];
    final CommandResult result;
    try {
      result = elevated
          ? await _runner.run('pkexec', ['kill', ...args])
          : await _runner.run('kill', args);
    } on CommandNotFound catch (e) {
      return KillResult(KillOutcome.failed, e.toString());
    }

    if (elevated && isPkexecCancelled(result.exitCode)) {
      return const KillResult(
        KillOutcome.cancelled,
        'Authentication was cancelled.',
      );
    }
    if (!result.ok) {
      final error = result.stderr.trim();
      return KillResult(
        KillOutcome.failed,
        error.isEmpty ? 'kill exited with code ${result.exitCode}' : error,
      );
    }

    var waited = Duration.zero;
    while (_isAlive(pid)) {
      if (waited >= wait) return const KillResult(KillOutcome.stillRunning);
      await _sleep(pollInterval);
      waited += pollInterval;
    }
    return const KillResult(KillOutcome.terminated);
  }
}
