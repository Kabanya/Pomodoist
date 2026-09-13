import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/linux_host_app_id.dart';

void main() {
  test('uses the installed desktop id for the current AppImage', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-app-id-');
    addTearDown(() => root.delete(recursive: true));
    final dataHome = Directory('${root.path}/data');
    final applications = Directory('${dataHome.path}/applications');
    await applications.create(recursive: true);
    final appImage = File('${root.path}/Pomodoist.AppImage');
    await appImage.writeAsString('');
    await File(
      '${applications.path}/appimagekit_123-Pomodoist.desktop',
    ).writeAsString('''
[Desktop Entry]
Exec=${appImage.path} %u
TryExec=${appImage.path}
X-AppImage-Old-Icon=com.finchforge.pomodoist
''');

    final resolver = LinuxHostAppIdResolver(
      environment: {
        'HOME': root.path,
        'XDG_DATA_HOME': dataHome.path,
        'XDG_DATA_DIRS': '/usr/local/share:/usr/share',
        'APPIMAGE': appImage.path,
        'APPDIR': '${root.path}/mount',
      },
    );

    expect(await resolver.resolve(), 'appimagekit_123-Pomodoist');
  });

  test('uses the canonical id for an ordinary installation', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-app-id-');
    addTearDown(() => root.delete(recursive: true));
    final applications = Directory('${root.path}/applications');
    await applications.create(recursive: true);
    await File(
      '${applications.path}/com.finchforge.pomodoist.desktop',
    ).writeAsString('[Desktop Entry]\nName=Pomodoist\n');

    final resolver = LinuxHostAppIdResolver(
      environment: {
        'HOME': root.path,
        'XDG_DATA_HOME': root.path,
        'XDG_DATA_DIRS': '',
      },
    );

    expect(await resolver.resolve(), 'com.finchforge.pomodoist');
  });
}
