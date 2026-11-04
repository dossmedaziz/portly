import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/services/single_instance.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('portly_si'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('second instance hands a show command to the first', () async {
    final path = '${dir.path}/portly.sock';
    final received = Completer<String>();
    final first = SingleInstance(socketPath: path);
    expect(await first.acquire(onCommand: received.complete), isTrue);
    expect(
      FileSystemEntity.typeSync(path),
      FileSystemEntityType.unixDomainSock,
    );

    final second = SingleInstance(socketPath: path);
    expect(await second.acquire(onCommand: (_) {}), isFalse);
    expect(await received.future.timeout(const Duration(seconds: 2)), 'show');

    await first.release();
    expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
  });

  test('a stale socket file is replaced', () async {
    final path = '${dir.path}/portly.sock';
    File(path).writeAsStringSync('stale');
    final instance = SingleInstance(socketPath: path);
    expect(await instance.acquire(onCommand: (_) {}), isTrue);
    await instance.release();
  });
}
