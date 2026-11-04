import 'dart:async';

import 'models.dart';

/// What changed between two snapshots.
class PortChanges {
  const PortChanges({this.opened = const [], this.closed = const []});

  final List<PortEntry> opened;
  final List<PortEntry> closed;

  bool get isEmpty => opened.isEmpty && closed.isEmpty;
}

/// Sockets that appeared or disappeared, matched by [PortEntry.key].
PortChanges diffSnapshots(List<PortEntry> previous, List<PortEntry> next) {
  final before = {for (final e in previous) e.key: e};
  final after = {for (final e in next) e.key: e};
  return PortChanges(
    opened: [
      for (final e in next)
        if (!before.containsKey(e.key)) e,
    ],
    closed: [
      for (final e in previous)
        if (!after.containsKey(e.key)) e,
    ],
  );
}

/// A favorite port that switched between free and in use.
class FavoriteChange {
  const FavoriteChange({required this.port, required this.opened, this.owner});

  final int port;
  final bool opened;

  /// Process (or unit) now holding the port, when it opened.
  final String? owner;
}

/// Port-number level changes for [favorites]: a port counts as open while any
/// socket (TCP or UDP, any address) is bound to it.
List<FavoriteChange> favoriteChanges(
  List<PortEntry> previous,
  List<PortEntry> next,
  Iterable<int> favorites,
) {
  final changes = <FavoriteChange>[];
  for (final port in favorites) {
    final was = previous.where((e) => e.port == port);
    final now = next.where((e) => e.port == port);
    if (was.isEmpty && now.isNotEmpty) {
      changes.add(
        FavoriteChange(
          port: port,
          opened: true,
          owner: now.map((e) => e.displayName).nonNulls.firstOrNull,
        ),
      );
    } else if (was.isNotEmpty && now.isEmpty) {
      changes.add(FavoriteChange(port: port, opened: false));
    }
  }
  return changes;
}

class WatchEvent {
  const WatchEvent(this.result, this.changes);
  final ScanResult result;

  /// Null on the first snapshot.
  final PortChanges? changes;
}

/// Polls [scan] every [interval] and emits each snapshot with its diff.
class PortWatcher {
  PortWatcher({required this.scan, required this._interval});

  final Future<ScanResult> Function() scan;
  Duration _interval;
  Timer? _timer;
  List<PortEntry>? _previous;
  bool _busy = false;

  final _events = StreamController<WatchEvent>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  Stream<WatchEvent> get events => _events.stream;
  Stream<Object> get errors => _errors.stream;

  Duration get interval => _interval;

  set interval(Duration value) {
    if (value == _interval) return;
    _interval = value;
    if (_timer != null) start();
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Scans now. Overlapping calls are skipped.
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      emit(await scan());
    } catch (e) {
      if (!_errors.isClosed) _errors.add(e);
    } finally {
      _busy = false;
    }
  }

  /// Feeds an externally obtained snapshot (e.g. an elevated scan).
  void emit(ScanResult result) {
    final previous = _previous;
    _previous = result.entries;
    if (_events.isClosed) return;
    _events.add(
      WatchEvent(
        result,
        previous == null ? null : diffSnapshots(previous, result.entries),
      ),
    );
  }

  Future<void> dispose() async {
    stop();
    await _events.close();
    await _errors.close();
  }
}
