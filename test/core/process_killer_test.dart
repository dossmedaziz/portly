import 'package:flutter_test/flutter_test.dart';
import 'package:portly/core/command_runner.dart';
import 'package:portly/core/process_killer.dart';

import '../fakes.dart';

void main() {
  late Set<int> alive;
  late FakeRunner runner;
  late List<Duration> slept;

  ProcessKiller killer({
    CommandResult Function(String, List<String>)? handler,
  }) {
    runner = FakeRunner(
      handler ??
          (exe, args) {
            // Simulate a process that obeys the signal.
            alive.remove(int.parse(args.last));
            return ok();
          },
    );
    return ProcessKiller(
      runner: runner,
      isAlive: alive.contains,
      ownPid: 999,
      sleep: (d) async => slept.add(d),
    );
  }

  setUp(() {
    alive = {1234};
    slept = [];
  });

  test('SIGTERM via kill for own processes', () async {
    final result = await killer().terminate(1234);
    expect(result.outcome, KillOutcome.terminated);
    expect(runner.calls.single, ['kill', '-TERM', '1234']);
  });

  test('pkexec for restricted processes', () async {
    final result = await killer().terminate(1234, elevated: true);
    expect(result.success, isTrue);
    expect(runner.calls.single, ['pkexec', 'kill', '-TERM', '1234']);
  });

  test('stillRunning after the 3 s grace period', () async {
    final k = killer(handler: (_, _) => ok()); // ignores SIGTERM
    final result = await k.terminate(1234);
    expect(result.outcome, KillOutcome.stillRunning);
    final total = slept.fold(Duration.zero, (a, b) => a + b);
    expect(total, const Duration(seconds: 3));
  });

  test('process exiting during the grace period', () async {
    var polls = 0;
    final k = ProcessKiller(
      runner: FakeRunner((_, _) => ok()),
      isAlive: (_) => ++polls < 5,
      ownPid: 999,
      sleep: (_) async {},
    );
    expect((await k.terminate(1234)).outcome, KillOutcome.terminated);
  });

  test('force kill sends SIGKILL', () async {
    final result = await killer().forceKill(1234, elevated: true);
    expect(result.success, isTrue);
    expect(runner.calls.single, ['pkexec', 'kill', '-KILL', '1234']);
  });

  for (final code in [126, 127]) {
    test('pkexec exit $code is a cancellation', () async {
      final k = killer(handler: (_, _) => failed(code));
      final result = await k.terminate(1234, elevated: true);
      expect(result.outcome, KillOutcome.cancelled);
    });
  }

  test('kill failure carries stderr', () async {
    final k = killer(
      handler: (_, _) => failed(1, 'kill: (1234) - Operation not permitted\n'),
    );
    final result = await k.terminate(1234);
    expect(result.outcome, KillOutcome.failed);
    expect(result.message, contains('Operation not permitted'));
  });

  test('missing kill binary is a failure, not a crash', () async {
    final k = killer(handler: (exe, _) => throw CommandNotFound(exe));
    expect((await k.terminate(1234)).outcome, KillOutcome.failed);
  });

  test('never signals PID 1, 0, negatives or Portly itself', () async {
    final k = killer();
    for (final pid in [1, 0, -1, 999]) {
      expect((await k.terminate(pid)).outcome, KillOutcome.refused);
      expect(
        (await k.forceKill(pid, elevated: true)).outcome,
        KillOutcome.refused,
      );
    }
    expect(runner.calls, isEmpty);
  });

  test('system process detection', () {
    for (final name in [
      'systemd',
      'systemd-resolved',
      'sshd',
      'NetworkManager',
      'gdm',
      'gdm-session-worker',
      'cupsd',
      'avahi-daemon',
    ]) {
      expect(isSystemProcess(name), isTrue, reason: name);
    }
    for (final name in ['node', 'python3', 'postgres', null]) {
      expect(isSystemProcess(name), isFalse, reason: '$name');
    }
  });
}
