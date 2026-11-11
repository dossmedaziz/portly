import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/command_runner.dart';
import '../core/models.dart';
import '../core/port_scanner.dart';
import '../core/port_watcher.dart';
import '../core/process_killer.dart';
import '../core/sandbox.dart';
import '../services/autostart_service.dart';
import '../services/settings_service.dart';

// ---- Services --------------------------------------------------------------

/// Overridden in main() once shared_preferences is loaded.
final settingsServiceProvider = Provider<SettingsService>(
  (ref) => throw UnimplementedError('settingsServiceProvider not overridden'),
);

final autostartServiceProvider = Provider((ref) => AutostartService());

final scannerProvider = Provider((ref) => PortScanner());

final killerProvider = Provider(
  (ref) => ProcessKiller(isAlive: ref.watch(scannerProvider).proc.isAlive),
);

/// Strict snap or not; decides whether Portly may elevate with pkexec.
final sandboxProvider = Provider<Sandbox>(
  (ref) => Sandbox.detect(Platform.environment),
);

/// Whether Portly may signal processes (in a snap: process-control is
/// connected). Invalidate it to check again.
final canSignalProvider = FutureProvider<bool>(
  (ref) => ref.watch(sandboxProvider).canSignal(const ProcessCommandRunner()),
);

final currentUidProvider = Provider<int>(
  (ref) => ref.watch(scannerProvider).proc.currentUid(),
);

// ---- Settings --------------------------------------------------------------

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final loaded = ref.read(settingsServiceProvider).load();
    // The autostart file is the source of truth for "start on login".
    return loaded.copyWith(
      startOnLogin: ref.read(autostartServiceProvider).isEnabled,
    );
  }

  Future<void> update(Settings next) async {
    final previous = state;
    state = next;
    if (previous.startOnLogin != next.startOnLogin ||
        (next.startOnLogin && previous.startHidden != next.startHidden)) {
      await ref
          .read(autostartServiceProvider)
          .setEnabled(next.startOnLogin, hidden: next.startHidden);
    }
    await ref.read(settingsServiceProvider).save(next);
  }
}

// ---- Ports -----------------------------------------------------------------

class PortsState {
  const PortsState({
    this.entries = const [],
    this.updated,
    this.source,
    this.error,
    this.loading = true,
  });

  final List<PortEntry> entries;
  final DateTime? updated;
  final ScanSource? source;

  /// Last scan error, cleared by the next successful scan.
  final Object? error;
  final bool loading;

  PortsState copyWith({
    List<PortEntry>? entries,
    DateTime? updated,
    ScanSource? source,
    Object? error,
    bool clearError = false,
    bool? loading,
  }) {
    return PortsState(
      entries: entries ?? this.entries,
      updated: updated ?? this.updated,
      source: source ?? this.source,
      error: clearError ? null : (error ?? this.error),
      loading: loading ?? this.loading,
    );
  }
}

final portsProvider = NotifierProvider<PortsNotifier, PortsState>(
  PortsNotifier.new,
);

/// Owns the [PortWatcher] and exposes the latest snapshot.
class PortsNotifier extends Notifier<PortsState> {
  late PortWatcher _watcher;
  final _changes = StreamController<WatchEvent>.broadcast();

  /// Every snapshot with its diff, for the tray and notifications.
  Stream<WatchEvent> get events => _changes.stream;

  @override
  PortsState build() {
    final scanner = ref.read(scannerProvider);
    _watcher = PortWatcher(
      scan: scanner.scan,
      interval: Duration(seconds: ref.read(settingsProvider).refreshSeconds),
    );
    final subs = [
      _watcher.events.listen(_onEvent),
      _watcher.errors.listen((e) {
        state = state.copyWith(error: e, loading: false);
      }),
    ];
    ref.listen(settingsProvider.select((s) => s.refreshSeconds), (_, seconds) {
      _watcher.interval = Duration(seconds: seconds);
    });
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      _watcher.dispose();
      _changes.close();
    });
    _watcher.start();
    return const PortsState();
  }

  void _onEvent(WatchEvent event) {
    final r = event.result;
    state = state.copyWith(
      entries: r.entries,
      updated: r.time,
      source: r.source,
      loading: false,
      clearError: true,
    );
    if (!_changes.isClosed) _changes.add(event);
  }

  Future<void> refresh() => _watcher.refresh();

  /// pkexec scan. Returns an error message, or null on success.
  Future<String?> elevatedScan() async {
    try {
      _watcher.emit(await ref.read(scannerProvider).elevatedScan());
      return null;
    } on ElevationCancelled {
      return 'Elevated scan cancelled.';
    } catch (e) {
      return '$e';
    }
  }
}

// ---- Filtering -------------------------------------------------------------

enum SortColumn { port, process }

class PortFilter {
  const PortFilter({
    this.query = '',
    this.tcp = true,
    this.udp = true,
    this.mineOnly = false,
    this.sort = SortColumn.port,
    this.ascending = true,
  });

  final String query;
  final bool tcp;
  final bool udp;
  final bool mineOnly;
  final SortColumn sort;
  final bool ascending;

  PortFilter copyWith({
    String? query,
    bool? tcp,
    bool? udp,
    bool? mineOnly,
    SortColumn? sort,
    bool? ascending,
  }) {
    return PortFilter(
      query: query ?? this.query,
      tcp: tcp ?? this.tcp,
      udp: udp ?? this.udp,
      mineOnly: mineOnly ?? this.mineOnly,
      sort: sort ?? this.sort,
      ascending: ascending ?? this.ascending,
    );
  }
}

final filterProvider = NotifierProvider<FilterNotifier, PortFilter>(
  FilterNotifier.new,
);

class FilterNotifier extends Notifier<PortFilter> {
  @override
  PortFilter build() => const PortFilter();

  void set(PortFilter filter) => state = filter;

  void sortBy(SortColumn column) {
    state = state.sort == column
        ? state.copyWith(ascending: !state.ascending)
        : state.copyWith(sort: column, ascending: true);
  }
}

final visiblePortsProvider = Provider<List<PortEntry>>((ref) {
  final entries = ref.watch(portsProvider.select((s) => s.entries));
  final filter = ref.watch(filterProvider);
  final uid = ref.watch(currentUidProvider);
  return applyFilter(entries, filter, uid);
});

List<PortEntry> applyFilter(List<PortEntry> entries, PortFilter f, int uid) {
  final q = f.query.trim().toLowerCase();
  final result = entries.where((e) {
    if (e.protocol == Protocol.tcp && !f.tcp) return false;
    if (e.protocol == Protocol.udp && !f.udp) return false;
    if (f.mineOnly && !e.isOwnedBy(uid)) return false;
    if (q.isEmpty) return true;
    return '${e.port}' == q ||
        '${e.port}'.startsWith(q) ||
        (e.pid != null && '${e.pid}' == q) ||
        (e.displayName?.toLowerCase().contains(q) ?? false) ||
        (e.command?.toLowerCase().contains(q) ?? false) ||
        (e.user?.toLowerCase() == q) ||
        e.address.contains(q);
  }).toList();

  int byPort(PortEntry a, PortEntry b) {
    final c = a.port.compareTo(b.port);
    return c != 0 ? c : a.protocol.index.compareTo(b.protocol.index);
  }

  int byName(PortEntry a, PortEntry b) {
    // Unknown owners sort last.
    final an = a.displayName?.toLowerCase() ?? '\u{10FFFF}';
    final bn = b.displayName?.toLowerCase() ?? '\u{10FFFF}';
    final c = an.compareTo(bn);
    return c != 0 ? c : byPort(a, b);
  }

  result.sort(f.sort == SortColumn.port ? byPort : byName);
  return f.ascending ? result : result.reversed.toList();
}

/// Everything bound to [port] right now, for the "what's using port X" box.
List<PortEntry> entriesOnPort(List<PortEntry> entries, int port) =>
    entries.where((e) => e.port == port).toList();

/// Should killing [entry] show the "this is a system service" warning?
bool isSystemEntry(PortEntry entry) =>
    isSystemProcess(entry.processName) ||
    (entry.uid == 0 && entry.unit != null);
