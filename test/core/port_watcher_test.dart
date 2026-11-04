import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/models.dart';
import 'package:portly/core/port_watcher.dart';

PortEntry entry(
  int port, {
  Protocol protocol = Protocol.tcp,
  String address = '0.0.0.0',
  String? process,
  int pid = 100,
}) {
  return PortEntry(
    protocol: protocol,
    state: protocol == Protocol.tcp ? 'LISTEN' : 'UNCONN',
    address: address,
    port: port,
    processes: process == null
        ? const []
        : [SocketProcess(name: process, pid: pid)],
  );
}

ScanResult snapshot(List<PortEntry> entries) =>
    ScanResult(entries: entries, source: ScanSource.ss, time: DateTime(2026));

void main() {
  group('diffSnapshots', () {
    test('no changes', () {
      final a = [entry(3000), entry(5432)];
      expect(diffSnapshots(a, [entry(3000), entry(5432)]).isEmpty, isTrue);
    });

    test('opened and closed ports', () {
      final changes = diffSnapshots(
        [entry(3000), entry(5432)],
        [entry(5432), entry(8000, process: 'python3')],
      );
      expect(changes.opened.map((e) => e.port), [8000]);
      expect(changes.closed.map((e) => e.port), [3000]);
    });

    test('same port on another protocol or address is a different socket', () {
      final changes = diffSnapshots(
        [entry(53, address: '127.0.0.1')],
        [
          entry(53, address: '127.0.0.1'),
          entry(53, protocol: Protocol.udp, address: '127.0.0.1'),
          entry(53, address: '::'),
        ],
      );
      expect(changes.opened, hasLength(2));
      expect(changes.closed, isEmpty);
    });

    test('a new pid on the same socket is not an open/close event', () {
      final changes = diffSnapshots(
        [entry(3000, process: 'node', pid: 1)],
        [entry(3000, process: 'node', pid: 2)],
      );
      expect(changes.isEmpty, isTrue);
    });

    test('from empty and to empty', () {
      expect(diffSnapshots([], [entry(1)]).opened, hasLength(1));
      expect(diffSnapshots([entry(1)], []).closed, hasLength(1));
    });
  });

  group('favoriteChanges', () {
    test('reports open with owner and close', () {
      final changes = favoriteChanges(
        [entry(5432)],
        [
          entry(3000, process: 'node'),
          entry(3000, address: '::', process: 'node'),
        ],
        [3000, 5432, 8080],
      );
      expect(changes, hasLength(2));
      expect(changes[0].port, 3000);
      expect(changes[0].opened, isTrue);
      expect(changes[0].owner, 'node');
      expect(changes[1].port, 5432);
      expect(changes[1].opened, isFalse);
    });

    test('an IPv6 twin closing alone keeps the port open', () {
      final changes = favoriteChanges(
        [entry(3000), entry(3000, address: '::')],
        [entry(3000)],
        [3000],
      );
      expect(changes, isEmpty);
    });
  });

  group('PortWatcher', () {
    test('first event has no diff, later events do', () async {
      final scans = [
        [entry(3000)],
        [entry(3000), entry(8000)],
      ];
      var i = 0;
      final watcher = PortWatcher(
        scan: () async => snapshot(scans[i++]),
        interval: const Duration(hours: 1),
      );
      final events = <WatchEvent>[];
      final sub = watcher.events.listen(events.add);

      await watcher.refresh();
      await watcher.refresh();
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events[0].changes, isNull);
      expect(events[1].changes!.opened.single.port, 8000);
      await sub.cancel();
      await watcher.dispose();
    });

    test('overlapping refreshes are skipped and errors are reported', () async {
      final gate = Completer<ScanResult>();
      var calls = 0;
      final watcher = PortWatcher(
        scan: () {
          calls++;
          return gate.future;
        },
        interval: const Duration(hours: 1),
      );
      final errors = <Object>[];
      final sub = watcher.errors.listen(errors.add);

      final first = watcher.refresh();
      await watcher.refresh(); // skipped while busy
      gate.completeError(const ScanException('ss failed'));
      await first;
      await pumpEventQueue();

      expect(calls, 1);
      expect(errors.single, isA<ScanException>());
      await sub.cancel();
      await watcher.dispose();
    });
  });
}
