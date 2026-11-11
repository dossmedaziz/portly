import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../identity.dart';
import '../providers/providers.dart';
import 'about_dialog.dart';
import 'settings_page.dart';
import 'widgets/kill_flow.dart';
import 'widgets/port_table.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset('assets/icons/portly_128.png', width: 28, height: 28),
            const SizedBox(width: 10),
            const Text(appName),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
          IconButton(
            tooltip: 'About $appName',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showPortlyAbout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(),
          _PortLookup(),
          Divider(height: 1),
          Expanded(child: _Body()),
        ],
      ),
    );
  }
}

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar();

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  final _search = TextEditingController();
  bool _elevating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _elevatedScan() async {
    setState(() => _elevating = true);
    final error = await ref.read(portsProvider.notifier).elevatedScan();
    if (!mounted) return;
    setState(() => _elevating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Elevated scan complete — hidden processes revealed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final updated = ref.watch(portsProvider.select((s) => s.updated));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Filter by port, process, PID, command',
                border: const OutlineInputBorder(),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          notifier.set(filter.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (q) => notifier.set(filter.copyWith(query: q)),
            ),
          ),
          FilterChip(
            label: const Text('TCP'),
            selected: filter.tcp,
            onSelected: (v) => notifier.set(filter.copyWith(tcp: v)),
          ),
          FilterChip(
            label: const Text('UDP'),
            selected: filter.udp,
            onSelected: (v) => notifier.set(filter.copyWith(udp: v)),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Mine only')),
              ButtonSegment(value: false, label: Text('All')),
            ],
            selected: {filter.mineOnly},
            onSelectionChanged: (s) =>
                notifier.set(filter.copyWith(mineOnly: s.first)),
          ),
          IconButton.filledTonal(
            tooltip: 'Refresh now',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(portsProvider.notifier).refresh(),
          ),
          // pkexec is not available inside the snap.
          if (ref.watch(sandboxProvider).canElevate)
            OutlinedButton.icon(
              onPressed: _elevating ? null : _elevatedScan,
              icon: _elevating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Elevated scan'),
            ),
          if (updated != null) _LastUpdated(updated),
        ],
      ),
    );
  }
}

class _LastUpdated extends StatelessWidget {
  const _LastUpdated(this.time);

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    return Text(
      'Updated ${two(time.hour)}:${two(time.minute)}:${two(time.second)}',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// "Find what's using port X".
class _PortLookup extends ConsumerStatefulWidget {
  const _PortLookup();

  @override
  ConsumerState<_PortLookup> createState() => _PortLookupState();
}

class _PortLookupState extends ConsumerState<_PortLookup> {
  int? _port;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final port = _port;
    final matches = port == null
        ? const <PortEntry>[]
        : entriesOnPort(
            ref.watch(portsProvider.select((s) => s.entries)),
            port,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.travel_explore),
                hintText: "What's using port…",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              onChanged: (v) {
                final p = int.tryParse(v);
                setState(
                  () => _port = (p != null && p > 0 && p <= 65535) ? p : null,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          if (port != null)
            Expanded(
              child: matches.isEmpty
                  ? Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text('Port $port is free'),
                      ],
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final e in matches)
                          InputChip(
                            avatar: Icon(
                              e.restricted ? Icons.lock_outline : Icons.memory,
                              size: 16,
                            ),
                            label: Text(
                              '${e.protocol.label} ${e.address} · '
                              '${e.displayName ?? 'hidden'}'
                              '${e.pid == null ? '' : ' (${e.pid})'}',
                            ),
                            deleteIcon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 18,
                            ),
                            deleteButtonTooltipMessage: 'Stop',
                            onDeleted: () =>
                                killWithConfirmation(context, ref, e),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(portsProvider);
    final visible = ref.watch(visiblePortsProvider);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.entries.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not list ports',
        body:
            '${state.error}\n\nPortly needs `ss` (package iproute2) '
            'or a readable /proc/net.',
        action: FilledButton.icon(
          onPressed: () => ref.read(portsProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (state.entries.isEmpty) {
      return const _Message(
        icon: Icons.power_off_outlined,
        title: 'Nothing is listening',
        body: 'No TCP or UDP sockets are open right now.',
      );
    }
    if (visible.isEmpty) {
      return _Message(
        icon: Icons.filter_alt_off_outlined,
        title: 'No ports match',
        body: 'Try clearing the search or switching to “All”.',
        action: TextButton(
          onPressed: () =>
              ref.read(filterProvider.notifier).set(const PortFilter()),
          child: const Text('Reset filters'),
        ),
      );
    }
    return Column(
      children: [
        const _PermissionBanner(),
        if (state.source == ScanSource.procNet)
          const MaterialBanner(
            content: Text(
              '`ss` was not found — reading /proc/net directly. '
              'Install iproute2 for full results.',
            ),
            leading: Icon(Icons.info_outline),
            actions: [SizedBox.shrink()],
          ),
        Expanded(child: PortTable(entries: visible)),
      ],
    );
  }
}

/// In the snap, until process-control is connected: how to allow stopping
/// processes.
class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sandbox = ref.watch(sandboxProvider);
    if (!sandbox.isSnap) return const SizedBox.shrink();
    if (ref.watch(canSignalProvider).value ?? true) {
      return const SizedBox.shrink();
    }
    final command = sandbox.connectProcessControl;
    return MaterialBanner(
      leading: const Icon(Icons.key_outlined),
      content: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text:
                  'To stop processes from Portly, allow it once in a '
                  'terminal:  ',
            ),
            TextSpan(
              text: command,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: command));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Command copied')));
          },
          child: const Text('Copy command'),
        ),
        TextButton(
          onPressed: () => ref.invalidate(canSignalProvider),
          child: const Text('Check again'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
