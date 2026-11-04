import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/command_runner.dart';
import 'package:portly/core/models.dart';
import 'package:portly/core/port_scanner.dart';
import 'package:portly/core/proc_reader.dart';

import '../fakes.dart';

const userLine =
    'tcp LISTEN 0 5 0.0.0.0:8000 0.0.0.0:* users:(("python3",pid=4242,fd=3)) uid:1000 ino:111 sk:1 <->';
const rootLine =
    'tcp LISTEN 0 2048 0.0.0.0:22 0.0.0.0:* ino:222 sk:2 cgroup:/system.slice/ssh.service <->';
const rootLineElevated =
    'tcp LISTEN 0 2048 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=900,fd=3)) ino:222 sk:2 cgroup:/system.slice/ssh.service <->';

void main() {
  late Directory root;
  late ProcReader proc;

  setUp(() {
    root = Directory.systemTemp.createTempSync('portly_scan');
    Directory('${root.path}/self').createSync();
    File('${root.path}/self/status')
        .writeAsStringSync('Name:\tportly\nUid:\t1000\t1000\t1000\t1000\n');
    Directory('${root.path}/4242').createSync();
    File('${root.path}/4242/cmdline')
        .writeAsStringSync('python3\u0000-m\u0000http.server\u00008000\u0000');
    File('${root.path}/passwd').writeAsStringSync(
      'root:x:0:0::/root:/bin/bash\ndosss:x:1000:1000::/home/dosss:/bin/bash\n',
    );
    proc = ProcReader(procRoot: root.path, passwdPath: '${root.path}/passwd');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('scan parses ss and enriches with cmdline and user', () async {
    final runner = FakeRunner((exe, args) => ok('$userLine\n$rootLine\n'));
    final result = await PortScanner(runner: runner, proc: proc).scan();

    expect(runner.calls.single, ['ss', '-tulpneH']);
    expect(result.source, ScanSource.ss);
    final http = result.entries.firstWhere((e) => e.port == 8000);
    expect(http.command, 'python3 -m http.server 8000');
    expect(http.user, 'dosss');
    expect(http.isOwnedBy(1000), isTrue);

    final ssh = result.entries.firstWhere((e) => e.port == 22);
    expect(ssh.restricted, isTrue);
    expect(ssh.user, 'root');
    expect(ssh.needsElevation(1000), isTrue);
  });

  test('ss failure raises ScanException', () async {
    final runner = FakeRunner((_, _) => failed(1, 'boom'));
    expect(
      PortScanner(runner: runner, proc: proc).scan(),
      throwsA(isA<ScanException>()),
    );
  });

  test('falls back to /proc/net when ss is missing', () async {
    Directory('${root.path}/net').createSync();
    const header =
        '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n';
    File('${root.path}/net/tcp').writeAsStringSync(
      '$header   0: 00000000:1F40 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 555 1 0 100 0 0 10 0\n',
    );
    Directory('${root.path}/4242/fd').createSync();
    Link('${root.path}/4242/fd/3').createSync('socket:[555]');
    File('${root.path}/4242/comm').writeAsStringSync('python3\n');

    final runner = FakeRunner((exe, _) => throw CommandNotFound(exe));
    final result = await PortScanner(runner: runner, proc: proc).scan();

    expect(result.source, ScanSource.procNet);
    final e = result.entries.single;
    expect(e.port, 8000);
    expect(e.processName, 'python3');
    expect(e.pid, 4242);
    expect(e.user, 'dosss');
  });

  test(
    'elevated scan reveals root processes and keeps them on later scans',
    () async {
      var elevated = false;
      final runner = FakeRunner((exe, args) {
        if (exe == 'pkexec') {
          elevated = true;
          return ok('$userLine\n$rootLineElevated\n');
        }
        return ok('$userLine\n$rootLine\n');
      });
      final scanner = PortScanner(runner: runner, proc: proc);

      final result = await scanner.elevatedScan();
      expect(elevated, isTrue);
      expect(runner.calls.first, ['pkexec', 'ss', '-tulpneH']);
      final ssh = result.entries.firstWhere((e) => e.port == 22);
      expect(ssh.processName, 'sshd');
      expect(ssh.pid, 900);
      expect(ssh.revealed, isTrue);
      expect(ssh.needsElevation(1000), isTrue);

      final later = await scanner.scan();
      expect(later.entries.firstWhere((e) => e.port == 22).pid, 900);
    },
  );

  test('revealed info is dropped once the socket is gone', () async {
    var phase = 0;
    final runner = FakeRunner((exe, _) {
      if (exe == 'pkexec') return ok(rootLineElevated);
      return ok(phase == 0 ? rootLine : userLine);
    });
    final scanner = PortScanner(runner: runner, proc: proc);
    await scanner.elevatedScan();
    phase = 1;
    await scanner.scan(); // inode 222 gone
    phase = 0;
    final again = await scanner
        .scan(); // same inode back, but stale info dropped
    expect(again.entries.single.restricted, isTrue);
  });

  test('cancelled pkexec prompt', () async {
    final runner = FakeRunner((_, _) => failed(126));
    expect(
      PortScanner(runner: runner, proc: proc).elevatedScan(),
      throwsA(isA<ElevationCancelled>()),
    );
  });
}
