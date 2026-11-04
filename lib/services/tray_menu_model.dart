import '../core/models.dart';
import '../core/process_killer.dart';
import '../identity.dart';

const maxTrayProcesses = 10;

/// One "3000 · node" entry in the tray menu.
class TrayProcessItem {
  const TrayProcessItem({required this.entry});

  final PortEntry entry;

  String get label => '${entry.port} · ${entry.displayName}';

  @override
  bool operator ==(Object other) =>
      other is TrayProcessItem &&
      other.entry.key == entry.key &&
      other.entry.pid == entry.pid &&
      other.entry.displayName == entry.displayName;

  @override
  int get hashCode => Object.hash(entry.key, entry.pid, entry.displayName);
}

class TrayFavorite {
  const TrayFavorite(this.port, this.owner, {required this.open});

  final int port;
  final bool open;
  final String? owner;

  String get label => open
      ? '$port — in use${owner == null ? '' : ' by $owner'}'
      : '$port — free';

  @override
  bool operator ==(Object other) =>
      other is TrayFavorite &&
      other.port == port &&
      other.open == open &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(port, open, owner);
}

/// Everything the tray menu shows. Compared by value so the native menu is
/// rebuilt only when something visible changed.
class TrayMenuModel {
  const TrayMenuModel({
    required this.listening,
    required this.processes,
    required this.favorites,
    required this.startOnLogin,
  });

  final int listening;
  final List<TrayProcessItem> processes;
  final List<TrayFavorite> favorites;
  final bool startOnLogin;

  String get header =>
      '$appName — $listening port${listening == 1 ? '' : 's'} listening';

  @override
  bool operator ==(Object other) =>
      other is TrayMenuModel &&
      other.listening == listening &&
      other.startOnLogin == startOnLogin &&
      _eq(other.processes, processes) &&
      _eq(other.favorites, favorites);

  @override
  int get hashCode => Object.hash(
    listening,
    startOnLogin,
    Object.hashAll(processes),
    Object.hashAll(favorites),
  );
}

bool _eq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

TrayMenuModel buildTrayMenuModel({
  required List<PortEntry> entries,
  required int currentUid,
  required List<int> favorites,
  required bool startOnLogin,
}) {
  // One item per (port, process): IPv4 and IPv6 twins collapse together.
  final seen = <String>{};
  final mine = <TrayProcessItem>[];
  final sorted = [...entries]..sort((a, b) => a.port.compareTo(b.port));
  for (final e in sorted) {
    if (!e.isOwnedBy(currentUid) || e.pid == null) continue;
    if (isSystemProcess(e.processName)) continue;
    if (!seen.add('${e.port}|${e.pid}')) continue;
    mine.add(TrayProcessItem(entry: e));
    if (mine.length == maxTrayProcesses) break;
  }

  return TrayMenuModel(
    listening: entries
        .map((e) => '${e.protocol.name}/${e.port}')
        .toSet()
        .length,
    processes: mine,
    favorites: [
      for (final port in favorites)
        () {
          final on = entries.where((e) => e.port == port);
          return TrayFavorite(
            port,
            on.map((e) => e.displayName).nonNulls.firstOrNull,
            open: on.isNotEmpty,
          );
        }(),
    ],
    startOnLogin: startOnLogin,
  );
}
