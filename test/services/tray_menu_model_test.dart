import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/models.dart';
import 'package:portly/services/tray_menu_model.dart';

PortEntry e(
  int port,
  String? name, {
  int pid = 100,
  int uid = 1000,
  String address = '0.0.0.0',
  Protocol protocol = Protocol.tcp,
}) => PortEntry(
  protocol: protocol,
  state: 'LISTEN',
  address: address,
  port: port,
  uid: uid,
  processes: name == null ? const [] : [SocketProcess(name: name, pid: pid)],
);

void main() {
  TrayMenuModel build(
    List<PortEntry> entries, {
    List<int> favorites = const [],
  }) => buildTrayMenuModel(
    entries: entries,
    currentUid: 1000,
    favorites: favorites,
    startOnLogin: false,
  );

  test('header counts distinct protocol/port pairs', () {
    final m = build([
      e(3000, 'node'),
      e(3000, 'node', address: '::'),
      e(53, null, uid: 0, protocol: Protocol.udp),
    ]);
    expect(m.header, 'Portly — 2 ports listening');
    expect(build([e(1, 'x')]).header, 'Portly — 1 port listening');
  });

  test('lists only own, non-system processes, deduped and capped at 10', () {
    final entries = [
      for (var i = 0; i < 15; i++) e(4000 + i, 'node', pid: 200 + i),
      e(3000, 'node', pid: 1),
      e(3000, 'node', pid: 1, address: '::'),
      e(22, null, uid: 0),
      e(5432, 'postgres', uid: 112, pid: 50),
      e(9999, 'systemd', pid: 2),
    ];
    final m = build(entries);
    expect(m.processes, hasLength(10));
    expect(m.processes.first.label, '3000 · node');
    expect(m.processes.map((p) => p.entry.port), isNot(contains(5432)));
    expect(m.processes.map((p) => p.entry.port), isNot(contains(9999)));
  });

  test('favorites show open/free with owner', () {
    final m = build([e(3000, 'node')], favorites: [3000, 8080]);
    expect(m.favorites[0].label, '3000 — in use by node');
    expect(m.favorites[1].label, '8080 — free');
  });

  test('equal inputs give equal models so the menu is not rebuilt', () {
    final a = build([e(3000, 'node')], favorites: [3000]);
    final b = build([e(3000, 'node')], favorites: [3000]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == build([e(3000, 'node', pid: 7)], favorites: [3000]), isFalse);
    expect(a == build([e(3000, 'node')], favorites: []), isFalse);
  });
}
