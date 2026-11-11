import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/command_runner.dart';
import 'package:portly/core/models.dart';
import 'package:portly/core/sandbox.dart';

import '../fakes.dart';

PortEntry e(
  int port, {
  String? cgroup,
  List<SocketProcess> processes = const [],
  Protocol protocol = Protocol.tcp,
}) => PortEntry(
  protocol: protocol,
  state: 'LISTEN',
  address: '0.0.0.0',
  port: port,
  processes: processes,
  uid: 0,
  cgroup: cgroup,
);

void main() {
  test('detects the snap from SNAP_NAME', () {
    expect(Sandbox.detect(const {}).isSnap, isFalse);
    expect(Sandbox.detect(const {'SNAP_NAME': ''}).isSnap, isFalse);
    final snap = Sandbox.detect(const {'SNAP_NAME': 'portly'});
    expect(snap.isSnap, isTrue);
    expect(snap.canElevate, isFalse);
    expect(snap.connectProcessControl, 'snap connect portly:process-control');
    expect(const Sandbox.none().canElevate, isTrue);
  });

  test('canSignal asks snapctl only inside a snap', () async {
    final yes = FakeRunner((_, _) => ok());
    expect(await const Sandbox.none().canSignal(yes), isTrue);
    expect(yes.calls, isEmpty);

    const snap = Sandbox(snapName: 'portly');
    expect(await snap.canSignal(yes), isTrue);
    expect(yes.calls.single, ['snapctl', 'is-connected', 'process-control']);
    expect(await snap.canSignal(FakeRunner((_, _) => failed(1))), isFalse);
    expect(
      await snap.canSignal(FakeRunner((exe, _) => throw CommandNotFound(exe))),
      isFalse,
    );
  });

  test('sudoStopCommand prefers the unit, then the PID, then a lookup', () {
    expect(
      sudoStopCommand(e(22, cgroup: '/system.slice/ssh.socket')),
      'sudo systemctl stop ssh.socket',
    );
    expect(
      sudoStopCommand(
        e(80, processes: const [SocketProcess(name: 'nginx', pid: 900)]),
      ),
      'sudo kill 900',
    );
    expect(sudoStopCommand(e(631)), "sudo ss -tlpn 'sport = :631'");
    expect(
      sudoStopCommand(e(5353, protocol: Protocol.udp)),
      "sudo ss -ulpn 'sport = :5353'",
    );
    // Never suggest killing PID 1.
    expect(
      sudoStopCommand(
        e(9, processes: const [SocketProcess(name: 'systemd', pid: 1)]),
      ),
      "sudo ss -tlpn 'sport = :9'",
    );
  });
}
