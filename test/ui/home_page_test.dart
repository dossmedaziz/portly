import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/app.dart';
import 'package:portly/core/port_scanner.dart';
import 'package:portly/core/proc_reader.dart';
import 'package:portly/providers/providers.dart';
import 'package:portly/services/autostart_service.dart';
import 'package:portly/services/settings_service.dart';

import '../fakes.dart';

class FakeSettingsService implements SettingsService {
  Settings saved = const Settings();
  @override
  Settings load() => saved;
  @override
  Future<void> save(Settings s) async => saved = s;
}

const ssOutput = '''
tcp LISTEN 0 5 0.0.0.0:8000 0.0.0.0:* users:(("python3",pid=4242,fd=3)) uid:1000 ino:111 sk:1 <->
tcp LISTEN 0 2048 0.0.0.0:22 0.0.0.0:* ino:222 sk:2 cgroup:/system.slice/ssh.socket <->
udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:* uid:103 ino:333 sk:3 cgroup:/system.slice/avahi-daemon.service <->
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('portly_ui'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pumpApp(WidgetTester tester, String output) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(FakeSettingsService()),
        autostartServiceProvider.overrideWithValue(
          AutostartService(configHome: tmp.path, env: const {}),
        ),
        scannerProvider.overrideWithValue(
          PortScanner(
            runner: FakeRunner((_, _) => ok(output)),
            proc: ProcReader(
              procRoot: tmp.path,
              passwdPath: '${tmp.path}/passwd',
            ),
          ),
        ),
        currentUidProvider.overrideWithValue(1000),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const PortlyApp()),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('lists ports, filters, and looks up a port', (tester) async {
    final container = await pumpApp(tester, ssOutput);

    expect(find.text('Portly'), findsOneWidget);
    expect(find.text('8000'), findsOneWidget);
    expect(find.text('python3'), findsOneWidget);
    expect(find.text('ssh.socket'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    // Browser shortcut for both TCP ports on 0.0.0.0, none for UDP.
    expect(find.byIcon(Icons.open_in_browser), findsNWidgets(2));

    await tester.tap(find.text('Mine only'));
    await tester.pump();
    expect(find.text('ssh.socket'), findsNothing);
    expect(find.text('8000'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, "What's using port…"),
      '9999',
    );
    await tester.pump();
    expect(find.text('Port 9999 is free'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, "What's using port…"),
      '8000',
    );
    await tester.pump();
    expect(find.textContaining('python3 (4242)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('kill asks for confirmation and cancel does nothing', (
    tester,
  ) async {
    final container = await pumpApp(tester, ssOutput);
    await tester.tap(find.byTooltip('Stop (SIGTERM)'));
    await tester.pumpAndSettle();
    expect(find.text('Stop python3?'), findsOneWidget);
    expect(find.textContaining('PID 4242'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Stop python3?'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('empty state', (tester) async {
    final container = await pumpApp(tester, '');
    expect(find.text('Nothing is listening'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
