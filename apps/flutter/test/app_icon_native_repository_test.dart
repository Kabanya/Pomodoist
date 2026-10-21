import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/settings/app_icon_repository_native.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pomodoist/app_icon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads native selections and refuses unknown native state', () async {
    final repository = PlatformAppIconRepository();
    for (final choice in AppIconChoice.values) {
      messenger.setMockMethodCallHandler(channel, (_) async => choice.id);
      expect(await repository.read(), choice);
    }
    messenger.setMockMethodCallHandler(channel, (_) async => 'unrecognized');
    await expectLater(repository.read(), throwsStateError);
  });

  test(
    'passes the selected identity and macOS icon bytes to the native host',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final repository = PlatformAppIconRepository();
      await repository.apply(AppIconChoice.classic);
      expect(calls.single.method, 'setIcon');
      final args = calls.single.arguments as Map;
      expect(args['icon'], 'classic');
      if (Platform.isMacOS) {
        expect(args['image'], isA<Uint8List>());
        expect((args['image'] as Uint8List).take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
      }
    },
  );
}
