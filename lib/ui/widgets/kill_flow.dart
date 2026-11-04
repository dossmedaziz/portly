import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/process_killer.dart';
import '../../providers/actions.dart';
import '../../providers/providers.dart';

/// Confirms and kills the owner of [entry], reporting the outcome in a
/// SnackBar. Hidden owners are revealed with an elevated scan first.
Future<void> killWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  PortEntry entry, {
  bool force = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  var target = entry;
  if (target.pid == null) {
    final reveal = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(
          'Port ${entry.port} is owned by ${entry.user ?? 'another user'}',
        ),
        content: Text(
          'The process behind ${entry.displayName ?? 'this port'} is hidden '
          'from your user. Portly will ask for your password to identify it, '
          'then ask you to confirm before stopping anything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Identify process'),
          ),
        ],
      ),
    );
    if (reveal != true) return;
    final error = await ref.read(portsProvider.notifier).elevatedScan();
    if (error != null) return say(error);
    final found = ref
        .read(portsProvider)
        .entries
        .where((e) => e.key == entry.key)
        .firstOrNull;
    if (found == null) return say('Port ${entry.port} is already free.');
    if (found.pid == null) {
      return say('Still could not identify the owner of port ${entry.port}.');
    }
    target = found;
  }

  final killer = ref.read(killerProvider);
  final refusal = killer.refusalReason(target.pid!);
  if (refusal != null) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.block),
        title: Text('Portly will not stop PID ${target.pid}'),
        content: Text(
          target.unit != null && target.pid == 1
              ? '$refusal\n\nsudo systemctl stop ${target.unit}'
              : refusal,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final confirmed = await _confirm(context, ref, target, force: force);
  if (confirmed != true) return;

  final result = await ref.read(actionsProvider).kill(target, force: force);
  if (!context.mounted) return;
  switch (result.outcome) {
    case KillOutcome.terminated:
      say('${target.displayName} stopped — port ${target.port} is free.');
    case KillOutcome.stillRunning:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${target.displayName} ignored SIGTERM and is still running.',
          ),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Force kill',
            onPressed: () =>
                killWithConfirmation(context, ref, target, force: true),
          ),
        ),
      );
    case KillOutcome.cancelled:
      say('Authentication cancelled — nothing was stopped.');
    case KillOutcome.failed || KillOutcome.refused:
      say(result.message ?? 'Could not stop ${target.displayName}.');
  }
}

Future<bool?> _confirm(
  BuildContext context,
  WidgetRef ref,
  PortEntry entry, {
  required bool force,
}) {
  final uid = ref.read(currentUidProvider);
  final system = isSystemEntry(entry);
  final elevated = entry.needsElevation(uid);
  final theme = Theme.of(context);
  final others = entry.processes.length > 1
      ? ' (and ${entry.processes.length - 1} more sharing the socket)'
      : '';

  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        system ? Icons.warning_amber : Icons.stop_circle_outlined,
        color: system ? theme.colorScheme.error : null,
      ),
      title: Text('${force ? 'Force kill' : 'Stop'} ${entry.displayName}?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PID ${entry.pid}$others · port ${entry.port}/${entry.protocol.name}'
              ' · user ${entry.user ?? '?'}',
            ),
            if (entry.command != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  entry.command!,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              force
                  ? 'SIGKILL ends the process immediately without letting it clean up.'
                  : 'Portly sends SIGTERM and waits up to 3 seconds for it to exit.',
            ),
            if (elevated) ...[
              const SizedBox(height: 8),
              const Text(
                'This process belongs to another user: '
                'you will be asked for your password.',
              ),
            ],
            if (system) ...[
              const SizedBox(height: 8),
              Text(
                'This looks like a system service. Stopping it can break '
                'networking, login or other parts of the desktop.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: system || force
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(force ? 'Force kill' : 'Stop process'),
        ),
      ],
    ),
  );
}
