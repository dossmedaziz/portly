import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/settings_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _newFavorite = TextEditingController();

  @override
  void dispose() {
    _newFavorite.dispose();
    super.dispose();
  }

  void _update(Settings Function(Settings) change) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.update(change(ref.read(settingsProvider))).catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save settings: $e')));
      }
    });
  }

  void _addFavorite() {
    final port = int.tryParse(_newFavorite.text);
    if (port == null || port < 1 || port > 65535) return;
    _newFavorite.clear();
    _update(
      (s) => s.favorites.contains(port)
          ? s
          : s.copyWith(favorites: [...s.favorites, port]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final entries = ref.watch(portsProvider.select((p) => p.entries));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _Section('Scanning'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Refresh interval'),
            subtitle: Text(
              'Every ${s.refreshSeconds} second${s.refreshSeconds == 1 ? '' : 's'}',
            ),
            trailing: SizedBox(
              width: 260,
              child: Slider(
                value: s.refreshSeconds.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '${s.refreshSeconds}s',
                onChanged: (v) =>
                    _update((s) => s.copyWith(refreshSeconds: v.round())),
              ),
            ),
          ),
          _Section('Startup'),
          SwitchListTile(
            secondary: const Icon(Icons.login),
            title: const Text('Start on login'),
            subtitle: const Text('Adds Portly to ~/.config/autostart'),
            value: s.startOnLogin,
            onChanged: (v) => _update((s) => s.copyWith(startOnLogin: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Start hidden'),
            subtitle: const Text(
              'Launch at login straight to the tray, without a window',
            ),
            value: s.startHidden,
            onChanged: (v) => _update((s) => s.copyWith(startHidden: v)),
          ),
          _Section('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Show notifications'),
            subtitle: const Text(
              'When a favorite port opens or closes, and after a kill',
            ),
            value: s.notifications,
            onChanged: (v) => _update((s) => s.copyWith(notifications: v)),
          ),
          _Section('Favorite ports'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Watched in the tray menu and announced when they open or close.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final port in s.favorites)
                  InputChip(
                    avatar: Icon(
                      Icons.circle,
                      size: 10,
                      color: entries.any((e) => e.port == port)
                          ? Colors.green
                          : theme.colorScheme.outline,
                    ),
                    label: Text('$port'),
                    onDeleted: () => _update(
                      (s) =>
                          s.copyWith(favorites: [...s.favorites]..remove(port)),
                    ),
                  ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _newFavorite,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add port',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _addFavorite,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    onSubmitted: (_) => _addFavorite(),
                  ),
                ),
                TextButton(
                  onPressed: () => _update(
                    (s) => s.copyWith(favorites: defaultFavoritePorts),
                  ),
                  child: const Text('Restore defaults'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
