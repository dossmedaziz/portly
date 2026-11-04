import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/command_runner.dart';
import '../core/models.dart';
import '../core/process_killer.dart';
import '../services/notification_service.dart';
import 'providers.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(
    isEnabled: () => ref.read(settingsProvider).notifications,
  ),
);

final actionsProvider = Provider((ref) => PortActions(ref));

/// User actions shared by the window and the tray menu.
class PortActions {
  PortActions(this._ref);

  final Ref _ref;

  int get _uid => _ref.read(currentUidProvider);

  /// Signals the owner of [entry]: SIGTERM (waits 3 s) or SIGKILL if [force].
  /// Uses pkexec when the process belongs to another user.
  Future<KillResult> kill(PortEntry entry, {bool force = false}) async {
    final pid = entry.pid;
    if (pid == null) {
      return const KillResult(
        KillOutcome.failed,
        'The owning process is hidden. Run an elevated scan first.',
      );
    }
    final killer = _ref.read(killerProvider);
    final elevated = entry.needsElevation(_uid);
    final result = force
        ? await killer.forceKill(pid, elevated: elevated)
        : await killer.terminate(pid, elevated: elevated);

    final label = '${entry.displayName ?? 'PID $pid'} on port ${entry.port}';
    final notifier = _ref.read(notificationServiceProvider);
    switch (result.outcome) {
      case KillOutcome.terminated:
        await notifier.show(
          'Stopped $label',
          'Port ${entry.port} is now free.',
        );
      case KillOutcome.stillRunning:
        await notifier.show(
          '$label is still running',
          'It ignored SIGTERM. You can force kill it from Portly.',
        );
      case KillOutcome.failed || KillOutcome.refused:
        await notifier.show('Could not stop $label', result.message);
      case KillOutcome.cancelled:
        break;
    }
    await _ref.read(portsProvider.notifier).refresh();
    return result;
  }

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> openInBrowser(int port) async {
    try {
      await const ProcessCommandRunner().run('xdg-open', [
        'http://localhost:$port',
      ]);
    } on CommandNotFound {
      // Nothing to open with; ignore.
    }
  }
}
