import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/models.dart';
import 'package:portly/core/ss_parser.dart';

// Real `ss -tulpnH` / `ss -tulpneH` output captured on Ubuntu 26.04.
const ipv4Tcp =
    'tcp LISTEN 0      128                           127.0.0.1:5037  0.0.0.0:* users:(("adb",pid=80706,fd=10))            ';
const ipv4TcpExtended =
    'tcp   LISTEN 0      128             127.0.0.1:5037  0.0.0.0:* users:(("adb",pid=80706,fd=10))             uid:1000 ino:1006565 sk:1001 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/ptyxis-spawn-e7b3600e.scope <->';
const rootNoProcess =
    'tcp LISTEN 0      2048                            0.0.0.0:22    0.0.0.0:*                                            ';
const rootExtended =
    'tcp   LISTEN 0      2048              0.0.0.0:22    0.0.0.0:*                                             ino:20074 sk:1003 cgroup:/system.slice/ssh.socket <->';
const otherUserExtended =
    'udp   UNCONN 0      0                               0.0.0.0:5353  0.0.0.0:*                                             uid:103 ino:23774 sk:7 cgroup:/system.slice/avahi-daemon.service <->';
const ipv6Any =
    'tcp   LISTEN 0      511                  [::]:80       [::]:*                                             ino:27363 sk:100d cgroup:/system.slice/nginx.service v6only:1 <->';
const ipv6Scoped =
    'udp UNCONN 0      0      [fe80::b4cf:ef42:426e:14fb]%wlo1:3702     [::]:* users:(("python3",pid=18636,fd=13))        ';
const ipv6Loopback =
    'udp UNCONN 0      0                                 [::1]:323      [::]:*                                            ';
const udpStar =
    'udp UNCONN 0      0                                     *:56223       *:* users:(("python3",pid=18636,fd=12))        ';
const ipv4Scoped =
    'udp UNCONN 0      0                         127.0.0.53%lo:53    0.0.0.0:*                                            ';
const multiProcess =
    'tcp LISTEN 0      511                           0.0.0.0:8080  0.0.0.0:* users:(("nginx",pid=1236,fd=6),("nginx",pid=1235,fd=6),("nginx",pid=1234,fd=6))';
const sameProcessTwoFds =
    'tcp LISTEN 0      4096                          0.0.0.0:3000  0.0.0.0:* users:(("node",pid=4242,fd=21),("node",pid=4242,fd=22))';

void main() {
  group('parseSsLine', () {
    test('IPv4 TCP with process', () {
      final e = parseSsLine(ipv4Tcp)!;
      expect(e.protocol, Protocol.tcp);
      expect(e.state, 'LISTEN');
      expect(e.address, '127.0.0.1');
      expect(e.port, 5037);
      expect(e.pid, 80706);
      expect(e.processName, 'adb');
      expect(e.restricted, isFalse);
      expect(e.uid, isNull, reason: 'no -e fields');
    });

    test('extended fields: uid, inode, cgroup', () {
      final e = parseSsLine(ipv4TcpExtended)!;
      expect(e.uid, 1000);
      expect(e.inode, 1006565);
      expect(e.cgroup, startsWith('/user.slice/'));
      expect(e.unit, isNull);
    });

    test('root-owned socket without visible process is restricted', () {
      final e = parseSsLine(rootNoProcess)!;
      expect(e.restricted, isTrue);
      expect(e.pid, isNull);
      expect(e.processName, isNull);
      expect(e.port, 22);
    });

    test('extended root socket: missing uid means 0, unit from cgroup', () {
      final e = parseSsLine(rootExtended)!;
      expect(e.uid, 0);
      expect(e.inode, 20074);
      expect(e.unit, 'ssh.socket');
      expect(e.displayName, 'ssh.socket');
      expect(e.needsElevation(1000), isTrue);
    });

    test('other user UDP socket', () {
      final e = parseSsLine(otherUserExtended)!;
      expect(e.protocol, Protocol.udp);
      expect(e.state, 'UNCONN');
      expect(e.uid, 103);
      expect(e.unit, 'avahi-daemon.service');
      expect(e.restricted, isTrue);
    });

    test('IPv6 wildcard [::]', () {
      final e = parseSsLine(ipv6Any)!;
      expect(e.address, '::');
      expect(e.port, 80);
      expect(e.isBrowsable, isTrue);
    });

    test('IPv6 link-local with interface scope', () {
      final e = parseSsLine(ipv6Scoped)!;
      expect(e.address, 'fe80::b4cf:ef42:426e:14fb');
      expect(e.interface, 'wlo1');
      expect(e.port, 3702);
      expect(e.processName, 'python3');
    });

    test('IPv6 loopback without process', () {
      final e = parseSsLine(ipv6Loopback)!;
      expect(e.address, '::1');
      expect(e.port, 323);
      expect(e.restricted, isTrue);
    });

    test('UDP on * wildcard', () {
      final e = parseSsLine(udpStar)!;
      expect(e.address, '*');
      expect(e.port, 56223);
      expect(e.isBrowsable, isFalse, reason: 'UDP is never browsable');
    });

    test('IPv4 with interface scope', () {
      final e = parseSsLine(ipv4Scoped)!;
      expect(e.address, '127.0.0.53');
      expect(e.interface, 'lo');
      expect(e.port, 53);
    });

    test('multiple processes in users:(...)', () {
      final e = parseSsLine(multiProcess)!;
      expect(e.processes.map((p) => p.pid), [1236, 1235, 1234]);
      expect(e.processes.every((p) => p.name == 'nginx'), isTrue);
      expect(e.pid, 1236);
    });

    test('same pid on several fds is listed once', () {
      final e = parseSsLine(sameProcessTwoFds)!;
      expect(e.processes, [const SocketProcess(name: 'node', pid: 4242)]);
    });

    test('process names with spaces and escaped quotes', () {
      final e = parseSsLine(
        r'tcp LISTEN 0 10 127.0.0.1:9000 0.0.0.0:* users:(("Web Content",pid=7,fd=3),("a\"b",pid=8,fd=4))',
      )!;
      expect(e.processes.map((p) => p.name), ['Web Content', 'a"b']);
    });

    test('rejects blank, header and malformed lines', () {
      expect(parseSsLine(''), isNull);
      expect(parseSsLine('   '), isNull);
      expect(
        parseSsLine(
          'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port',
        ),
        isNull,
      );
      expect(parseSsLine('tcp LISTEN 0 128 nonsense 0.0.0.0:*'), isNull);
      expect(parseSsLine('raw UNCONN 0 0 0.0.0.0:1 0.0.0.0:*'), isNull);
    });
  });

  test('parseSsOutput parses every line of a full dump', () {
    final entries = parseSsOutput(
      [
        ipv4Tcp,
        rootNoProcess,
        ipv6Scoped,
        udpStar,
        multiProcess,
        '',
      ].join('\n'),
    );
    expect(entries, hasLength(5));
    expect(entries.map((e) => e.port), [5037, 22, 3702, 56223, 8080]);
  });

  group('parseSocketAddress', () {
    test('variants', () {
      expect(parseSocketAddress('0.0.0.0:8000'), (
        address: '0.0.0.0',
        interface: null,
        port: 8000,
      ));
      expect(parseSocketAddress('[::]:8080'), (
        address: '::',
        interface: null,
        port: 8080,
      ));
      expect(parseSocketAddress('*:5353'), (
        address: '*',
        interface: null,
        port: 5353,
      ));
      expect(parseSocketAddress('[ff02::c]%wlo1:3702'), (
        address: 'ff02::c',
        interface: 'wlo1',
        port: 3702,
      ));
      expect(parseSocketAddress('0.0.0.0:*'), isNull);
    });
  });
}
