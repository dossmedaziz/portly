// Renders store / README screenshots of the real UI with sample data.
//
//   flutter test tool/screenshots/store_screenshots_test.dart
//
// Writes docs/screenshots/*.png. Not part of the normal test run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/app.dart';
import 'package:portly/core/port_scanner.dart';
import 'package:portly/core/proc_reader.dart';
import 'package:portly/providers/providers.dart';
import 'package:portly/services/autostart_service.dart';
import 'package:portly/services/settings_service.dart';
import 'package:portly/ui/settings_page.dart';

import '../../test/fakes.dart';

const size = Size(1280, 800);

// A typical developer machine.
const ssOutput = '''
tcp LISTEN 0 511 127.0.0.1:3000 0.0.0.0:* users:(("node",pid=4211,fd=21)) uid:1000 ino:9001 sk:1 <->
tcp LISTEN 0 511 [::1]:5173 [::]:* users:(("node",pid=4388,fd=24)) uid:1000 ino:9002 sk:2 <->
tcp LISTEN 0 5 0.0.0.0:8000 0.0.0.0:* users:(("python3",pid=5120,fd=3)) uid:1000 ino:9003 sk:3 <->
tcp LISTEN 0 100 *:8080 *:* users:(("java",pid=3977,fd=118)) uid:1000 ino:9004 sk:4 <->
tcp LISTEN 0 4096 127.0.0.1:27017 0.0.0.0:* users:(("mongod",pid=3102,fd=12)) uid:1000 ino:9005 sk:5 <->
tcp LISTEN 0 200 127.0.0.1:5432 0.0.0.0:* uid:112 ino:9006 sk:6 cgroup:/system.slice/system-postgresql.slice/postgresql@18-main.service <->
tcp LISTEN 0 511 127.0.0.1:6379 0.0.0.0:* uid:113 ino:9007 sk:7 cgroup:/system.slice/redis-server.service <->
tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* ino:9008 sk:8 cgroup:/system.slice/ssh.socket <->
tcp LISTEN 0 4096 127.0.0.1:631 0.0.0.0:* ino:9009 sk:9 cgroup:/system.slice/cups.service <->
tcp LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:* uid:991 ino:9010 sk:a cgroup:/system.slice/systemd-resolved.service <->
udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:* uid:103 ino:9011 sk:b cgroup:/system.slice/avahi-daemon.service <->
udp UNCONN 0 0 0.0.0.0:41641 0.0.0.0:* users:(("syncthing",pid=2890,fd=17)) uid:1000 ino:9012 sk:c <->
''';

const cmdlines = {
  4211: ['node', '/home/dosss/code/shop/node_modules/.bin/next', 'dev'],
  4388: ['node', '/home/dosss/code/portfolio/node_modules/.bin/vite'],
  5120: ['python3', '-m', 'http.server', '8000'],
  3977: [
    '/usr/lib/jvm/java-21-openjdk-amd64/bin/java',
    '-jar',
    'build/libs/orders-api-0.4.2.jar',
    '--server.port=8080',
  ],
  3102: ['mongod', '--dbpath', '/home/dosss/.local/share/mongodb'],
  2890: ['syncthing', 'serve', '--no-browser'],
};

class _Settings implements SettingsService {
  @override
  Settings load() => const Settings();
  @override
  Future<void> save(Settings s) async {}
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const ubuntu = '/usr/share/fonts/truetype/ubuntu';
  final sdk = File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent;
  final materialFonts = '${sdk.path}/cache/artifacts/material_fonts';
  await family('Roboto', [
    '$ubuntu/Ubuntu-R.ttf',
    '$ubuntu/Ubuntu-M.ttf',
    '$ubuntu/Ubuntu-B.ttf',
    '$ubuntu/Ubuntu-RI.ttf',
  ]);
  await family('monospace', [
    '$ubuntu/UbuntuMono-R.ttf',
    '$ubuntu/UbuntuMono-B.ttf',
  ]);
  await family('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
}

void main() {
  late Directory proc;
  final out = Directory('docs/screenshots')..createSync(recursive: true);
  final boundary = GlobalKey();

  setUpAll(() async {
    await _loadFonts();
    proc = Directory.systemTemp.createTempSync('portly_shots');
    for (final MapEntry(key: pid, value: argv) in cmdlines.entries) {
      Directory('${proc.path}/$pid').createSync();
      File('${proc.path}/$pid/cmdline')
          .writeAsStringSync('${argv.join('\u0000')}\u0000');
    }
    File('${proc.path}/passwd').writeAsStringSync(
      'root:x:0:0::/root:/bin/bash\n'
      'avahi:x:103:110::/run/avahi-daemon:/usr/sbin/nologin\n'
      'postgres:x:112:120::/var/lib/postgresql:/bin/bash\n'
      'redis:x:113:121::/var/lib/redis:/usr/sbin/nologin\n'
      'systemd-resolve:x:991:991::/:/usr/sbin/nologin\n'
      'dosss:x:1000:1000::/home/dosss:/bin/bash\n',
    );
  });
  tearDownAll(() => proc.deleteSync(recursive: true));

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(_Settings()),
        autostartServiceProvider.overrideWithValue(
          AutostartService(configHome: proc.path, env: const {}),
        ),
        scannerProvider.overrideWithValue(
          PortScanner(
            runner: FakeRunner((_, _) => ok(ssOutput)),
            proc: ProcReader(
              procRoot: proc.path,
              passwdPath: '${proc.path}/passwd',
            ),
            clock: () => DateTime(2026, 11, 5, 15, 42, 7),
          ),
        ),
        currentUidProvider.overrideWithValue(1000),
      ],
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: UncontrolledProviderScope(
          container: container,
          child: const PortlyApp(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // Let Image.asset decode the logo.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> save(WidgetTester tester, String name) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('${out.path}/$name.png').writeAsBytesSync(bytes!);
  }

  Future<void> finish(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  }

  testWidgets('main window, light', (tester) async {
    final c = await pump(tester, Brightness.light);
    await save(tester, '1-ports-light');
    await finish(tester, c);
  });

  testWidgets('main window, dark, with port lookup', (tester) async {
    final c = await pump(tester, Brightness.dark);
    await tester.enterText(
      find.widgetWithText(TextField, "What's using port…"),
      '5432',
    );
    await tester.pumpAndSettle();
    await save(tester, '2-lookup-dark');
    await finish(tester, c);
  });

  testWidgets('stop confirmation', (tester) async {
    final c = await pump(tester, Brightness.light);
    await tester.tap(find.byTooltip('Stop (SIGTERM)').at(2)); // python3 on 8000
    await tester.pumpAndSettle();
    await save(tester, '3-stop-dialog');
    await finish(tester, c);
  });

  testWidgets('settings', (tester) async {
    final c = await pump(tester, Brightness.dark);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await save(tester, '4-settings-dark');
    await finish(tester, c);
  });
}
