import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/services/desktop_integration.dart';

void main() {
  late Directory tmp;
  late Map<String, String> env;
  final loaded = <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('portly_desktop');
    env = {
      'XDG_DATA_HOME': '${tmp.path}/home',
      'XDG_DATA_DIRS': '${tmp.path}/system',
      'APPIMAGE': '/home/me/Apps/Portly-1.0.0-x86_64.AppImage',
    };
    loaded.clear();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  DesktopIntegration integration() => DesktopIntegration(
    env: env,
    executable: '/tmp/.mount_x/usr/lib/portly/portly',
    loadAsset: (asset) async {
      loaded.add(asset);
      return Uint8List.fromList([1, 2, 3]);
    },
  );

  test('installs icons and a desktop entry for an AppImage', () async {
    final d = integration();
    expect(await d.ensure(), isTrue);

    final entry = d.desktopFile.readAsStringSync();
    expect(
      d.desktopFile.path,
      '${tmp.path}/home/applications/dev.dosss.portly.desktop',
    );
    expect(
      entry,
      contains('Exec=/home/me/Apps/Portly-1.0.0-x86_64.AppImage\n'),
    );
    expect(entry, contains('Icon=portly\n'));
    expect(entry, contains('StartupWMClass=dev.dosss.portly\n'));
    for (final size in DesktopIntegration.iconSizes) {
      expect(d.iconFile(size).existsSync(), isTrue, reason: '$size');
    }
    expect(loaded, hasLength(3));

    // Second launch: nothing to do.
    expect(await d.ensure(), isFalse);
  });

  test('updates Exec when the AppImage moves', () async {
    await integration().ensure();
    env['APPIMAGE'] = '/opt/apps/Portly.AppImage';
    final d = integration();
    expect(await d.ensure(), isTrue);
    expect(
      d.desktopFile.readAsStringSync(),
      contains('Exec=/opt/apps/Portly.AppImage\n'),
    );
  });

  test('leaves a hand-written entry alone', () async {
    final d = integration();
    d.desktopFile
      ..createSync(recursive: true)
      ..writeAsStringSync('[Desktop Entry]\nName=Mine\n');
    expect(await d.ensure(), isFalse);
    expect(d.desktopFile.readAsStringSync(), contains('Name=Mine'));
  });

  test('removes its own copy once the .deb is installed', () async {
    await integration().ensure();
    File('${tmp.path}/system/applications/dev.dosss.portly.desktop')
      ..createSync(recursive: true)
      ..writeAsStringSync('[Desktop Entry]\n');
    final d = integration();
    expect(d.isSystemInstalled, isTrue);
    expect(await d.ensure(), isTrue);
    expect(d.desktopFile.existsSync(), isFalse);
  });
}
