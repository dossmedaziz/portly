import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../providers/actions.dart';
import '../../providers/providers.dart';
import 'kill_flow.dart';

/// Column layout shared by the header and the rows.
const _columns = <(String, int)>[
  ('Port', 9),
  ('Proto', 7),
  ('Address', 16),
  ('Process', 16),
  ('PID', 9),
  ('User', 11),
  ('Command', 32),
];
// Three 48 px icon buttons.
const _actionsWidth = 144.0;

class PortTable extends ConsumerWidget {
  const PortTable({super.key, required this.entries});

  final List<PortEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _HeaderRow(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) => _PortRow(entry: entries[i]),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends ConsumerWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    Widget sortable(String label, SortColumn column, int flex) {
      final active = filter.sort == column;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => ref.read(filterProvider.notifier).sortBy(column),
          child: Row(
            children: [
              Text(label, style: style),
              Icon(
                active
                    ? (filter.ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: 14,
                color: active ? null : style?.color?.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          for (final (label, flex) in _columns)
            switch (label) {
              'Port' => sortable(label, SortColumn.port, flex),
              'Process' => sortable(label, SortColumn.process, flex),
              _ => Expanded(
                flex: flex,
                child: Text(label, style: style),
              ),
            },
          SizedBox(
            width: _actionsWidth,
            child: Text('Actions', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _PortRow extends ConsumerWidget {
  const _PortRow({required this.entry});

  final PortEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final actions = ref.read(actionsProvider);
    final elevated = entry.needsElevation(uid);
    final canElevate = ref.watch(sandboxProvider).canElevate;

    Widget cell(int index, Widget child) =>
        Expanded(flex: _columns[index].$2, child: child);
    Widget text(String? value, {TextStyle? style}) => Text(
      value ?? '—',
      overflow: TextOverflow.ellipsis,
      style: value == null ? TextStyle(color: muted) : style,
    );

    final address = entry.interface == null
        ? entry.address
        : '${entry.address}%${entry.interface}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          cell(
            0,
            Row(
              children: [
                Text(
                  '${entry.port}',
                  style: mono?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (elevated) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: entry.restricted
                        ? 'Owned by ${entry.user ?? 'another user'} — process hidden'
                        : canElevate
                        ? 'Owned by ${entry.user ?? 'another user'} — needs your password to stop'
                        : 'Owned by ${entry.user ?? 'another user'} — stop it with sudo',
                    child: Icon(Icons.lock_outline, size: 14, color: muted),
                  ),
                ],
              ],
            ),
          ),
          cell(1, _ProtoBadge(entry.protocol)),
          cell(
            2,
            Tooltip(
              message: address,
              child: text(address, style: mono),
            ),
          ),
          cell(
            3,
            text(
              entry.displayName,
              style: entry.processName == null
                  ? TextStyle(color: muted, fontStyle: FontStyle.italic)
                  : null,
            ),
          ),
          cell(4, text(entry.pid?.toString(), style: mono)),
          cell(5, text(entry.user)),
          cell(
            6,
            entry.command == null
                ? text(null)
                : Tooltip(
                    message: entry.command!,
                    waitDuration: const Duration(milliseconds: 400),
                    child: text(
                      entry.command,
                      style: mono?.copyWith(fontSize: 12, color: muted),
                    ),
                  ),
          ),
          SizedBox(
            width: _actionsWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (entry.isBrowsable)
                  IconButton(
                    tooltip: 'Open http://localhost:${entry.port}',
                    icon: const Icon(Icons.open_in_browser, size: 20),
                    onPressed: () => actions.openInBrowser(entry.port),
                  ),
                IconButton(
                  tooltip: !elevated
                      ? 'Stop (SIGTERM)'
                      : canElevate
                      ? 'Stop (asks for password)'
                      : 'How to stop (needs sudo)',
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => killWithConfirmation(context, ref, entry),
                ),
                _MoreMenu(entry: entry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.entry});

  final PortEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(actionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    void copy(String what, String value) {
      actions.copy(value);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Copied $what'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    return PopupMenuButton<VoidCallback>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => killWithConfirmation(context, ref, entry, force: true),
          enabled: entry.pid != null,
          child: const ListTile(
            leading: Icon(Icons.dangerous_outlined),
            title: Text('Force kill (SIGKILL)'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => copy('port', '${entry.port}'),
          child: const ListTile(
            leading: Icon(Icons.tag),
            title: Text('Copy port'),
            dense: true,
          ),
        ),
        if (entry.pid != null)
          PopupMenuItem(
            value: () => copy('PID', '${entry.pid}'),
            child: const ListTile(
              leading: Icon(Icons.numbers),
              title: Text('Copy PID'),
              dense: true,
            ),
          ),
        PopupMenuItem(
          value: () => copy('address', '${entry.address}:${entry.port}'),
          child: const ListTile(
            leading: Icon(Icons.lan_outlined),
            title: Text('Copy address'),
            dense: true,
          ),
        ),
        if (entry.command != null)
          PopupMenuItem(
            value: () => copy('command', entry.command!),
            child: const ListTile(
              leading: Icon(Icons.terminal),
              title: Text('Copy command'),
              dense: true,
            ),
          ),
      ],
    );
  }
}

class _ProtoBadge extends StatelessWidget {
  const _ProtoBadge(this.protocol);

  final Protocol protocol;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tcp = protocol == Protocol.tcp;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tcp ? scheme.primaryContainer : scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          protocol.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tcp ? scheme.onPrimaryContainer : scheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}
