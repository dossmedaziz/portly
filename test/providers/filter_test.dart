import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/models.dart';
import 'package:portly/providers/providers.dart';

PortEntry e(
  int port,
  String? name, {
  int uid = 1000,
  Protocol protocol = Protocol.tcp,
  String? command,
  int pid = 10,
}) => PortEntry(
  protocol: protocol,
  state: 'LISTEN',
  address: '0.0.0.0',
  port: port,
  uid: uid,
  command: command,
  processes: name == null ? const [] : [SocketProcess(name: name, pid: pid)],
);

void main() {
  final entries = [
    e(8000, 'python3', command: 'python3 -m http.server 8000', pid: 4242),
    e(22, null, uid: 0),
    e(5353, 'avahi', uid: 103, protocol: Protocol.udp),
    e(3000, 'node'),
  ];

  List<int> ports(PortFilter f) =>
      applyFilter(entries, f, 1000).map((x) => x.port).toList();

  test('default: everything sorted by port', () {
    expect(ports(const PortFilter()), [22, 3000, 5353, 8000]);
  });

  test('protocol chips', () {
    expect(ports(const PortFilter(udp: false)), [22, 3000, 8000]);
    expect(ports(const PortFilter(tcp: false)), [5353]);
  });

  test('mine only hides restricted and other users', () {
    expect(ports(const PortFilter(mineOnly: true)), [3000, 8000]);
  });

  test('search by port, process, pid and command', () {
    expect(ports(const PortFilter(query: '80')), [8000]);
    expect(ports(const PortFilter(query: 'NODE')), [3000]);
    expect(ports(const PortFilter(query: '4242')), [8000]);
    expect(ports(const PortFilter(query: 'http.server')), [8000]);
  });

  test('sort by process name puts unknown owners last', () {
    expect(ports(const PortFilter(sort: SortColumn.process)), [
      5353,
      3000,
      8000,
      22,
    ]);
    expect(ports(const PortFilter(sort: SortColumn.port, ascending: false)), [
      8000,
      5353,
      3000,
      22,
    ]);
  });

  test('entriesOnPort', () {
    expect(entriesOnPort(entries, 22), hasLength(1));
    expect(entriesOnPort(entries, 1), isEmpty);
  });
}
