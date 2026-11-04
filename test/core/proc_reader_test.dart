import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/models.dart';
import 'package:portly/core/proc_reader.dart';

void main() {
  test('decodeIpv4Hex', () {
    expect(decodeIpv4Hex('0100007F'), '127.0.0.1');
    expect(decodeIpv4Hex('00000000'), '0.0.0.0');
    expect(decodeIpv4Hex('0D01A8C0'), '192.168.1.13');
    expect(decodeIpv4Hex('xyz'), isNull);
  });

  test('decodeIpv6Hex', () {
    expect(decodeIpv6Hex('00000000000000000000000000000000'), '::');
    expect(decodeIpv6Hex('00000000000000000000000001000000'), '::1');
    expect(
      decodeIpv6Hex('0000000000000000FFFF00000100007F'),
      '::ffff:127.0.0.1',
    );
  });

  test('parseProcNet keeps LISTEN tcp and UNCONN udp', () {
    const tcp = '''
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:13AD 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1006565 1 0000000000000000 100 0 0 10 0
   1: 0100007F:1538 00000000:0000 0A 00000000:00000000 00:00000000 00000000   112        0 27675 1 0000000000000000 100 0 0 10 0
   2: 0D01A8C0:C350 5DB8D822:01BB 01 00000000:00000000 00:00000000 00000000  1000        0 9999 1 0000000000000000 100 0 0 10 0
''';
    final entries = parseProcNet(tcp, Protocol.tcp, ipv6: false);
    expect(entries.map((e) => e.port), [5037, 5432]);
    expect(entries[0].address, '127.0.0.1');
    expect(entries[0].uid, 1000);
    expect(entries[0].inode, 1006565);
    expect(entries[1].uid, 112);

    const udp = '''
   sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode ref pointer drops
 1285: 0D01A8C0:0E76 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 182322 2 0000000000000000 0
''';
    final u = parseProcNet(udp, Protocol.udp, ipv6: false).single;
    expect(u.port, 3702);
    expect(u.state, 'UNCONN');

    const tcp6 = '''
  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000000000000:0016 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 20076 1 0000000000000000 100 0 0 10 0
''';
    final v6 = parseProcNet(tcp6, Protocol.tcp, ipv6: true).single;
    expect(v6.address, '::');
    expect(v6.port, 22);
    expect(v6.uid, 0);
  });

  test('status, passwd and socket link helpers', () {
    expect(
      parseStatusUid('Name:\tx\nUid:\t1000\t1000\t1000\t1000\nGid:\t1\n'),
      1000,
    );
    expect(parseStatusUid('Name:\tx\n'), isNull);
    expect(
      parsePasswd(
        'root:x:0:0::/root:/bin/bash\npostgres:x:112:120::/var/lib/postgresql:/bin/bash\n',
      ),
      {0: 'root', 112: 'postgres'},
    );
    expect(parseSocketLink('socket:[20076]'), 20076);
    expect(parseSocketLink('pipe:[1]'), isNull);
    expect(parseSocketLink('/dev/null'), isNull);
  });

  test('betterProcessName fixes truncated and thread comm names', () {
    expect(
      betterProcessName('jetbrains-toolb', [
        '/etc/jetbrains-toolbox/bin/jetbrains-toolbox',
        '--minimize',
      ]),
      'jetbrains-toolbox',
    );
    expect(
      betterProcessName('MainThread', ['node', '/app/node_modules/.bin/vite']),
      'node',
    );
    expect(
      betterProcessName('python3', ['python3', '-m', 'http.server']),
      'python3',
    );
    expect(betterProcessName('nginx', ['nginx: worker process']), 'nginx');
    expect(betterProcessName('adb', null), 'adb');
  });
}
