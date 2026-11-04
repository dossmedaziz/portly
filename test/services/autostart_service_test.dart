import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/services/autostart_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('portly_auto'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('installed build writes Exec=portly --hidden', () async {
    final service = AutostartService(
      configHome: dir.path,
      executable: '/usr/share/portly/portly',
      env: const {},
    );
    await service.setEnabled(true);
    expect(service.file.path, '${dir.path}/autostart/dev.dosss.portly.desktop');
    final text = service.file.readAsStringSync();
    expect(text, contains('Name=Portly\n'));
    expect(text, contains('Exec=portly --hidden\n'));
    expect(text, contains('Icon=portly\n'));
    expect(text, contains('StartupWMClass=dev.dosss.portly\n'));
    expect(service.isEnabled, isTrue);

    await service.setEnabled(false);
    expect(service.isEnabled, isFalse);
  });

  test('AppImage and dev builds use absolute paths', () {
    expect(
      AutostartService(
        executable: '/tmp/.mount_x/portly',
        env: const {'APPIMAGE': '/home/me/Apps/Portly-1.0.0-x86_64.AppImage'},
      ).launchCommand,
      '/home/me/Apps/Portly-1.0.0-x86_64.AppImage',
    );
    expect(
      AutostartService(
        executable:
            '/home/me/My Code/portly/build/linux/x64/release/bundle/portly',
        env: const {},
      ).launchCommand,
      '"/home/me/My Code/portly/build/linux/x64/release/bundle/portly"',
    );
  });

  test('visible start omits --hidden', () {
    final entry = AutostartService(
      executable: '/usr/bin/portly',
      env: const {},
    ).desktopEntry(hidden: false);
    expect(entry, contains('Exec=portly\n'));
  });
}
