import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/keyboard_shortcuts.dart';
import 'package:pomodoist/app/macos_app_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(macOSAppMenuChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'sync sends every app command with its current label and shortcut',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final controller = MacOSAppMenuController(
        channel: channel,
        platform: TargetPlatform.macOS,
      );
      addTearDown(controller.dispose);
      final labels = {
        for (final command in AppShortcutCommand.values)
          command: 'Label ${command.name}',
      };

      await controller.sync(
        labels: labels,
        bindings: defaultAppShortcutBindings(TargetPlatform.macOS),
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, macOSAppMenuSetCommandsMethod);
      final commands = Map<String, Object?>.from(calls.single.arguments as Map);
      expect(commands.keys, {
        for (final command in AppShortcutCommand.values) command.name,
      });
      expect(commands[AppShortcutCommand.quickAdd.name], {
        'label': 'Label quickAdd',
        'keyLabel': 'N',
        'meta': true,
        'control': false,
        'alt': false,
        'shift': false,
      });
    },
  );

  test(
    'selected callback accepts known commands and ignores malformed input',
    () async {
      final selected = <AppShortcutCommand>[];
      final controller = MacOSAppMenuController(
        channel: channel,
        platform: TargetPlatform.macOS,
        onSelected: selected.add,
      );
      addTearDown(controller.dispose);

      await controller.handleMethodCall(
        const MethodCall(macOSAppMenuSelectedMethod, 'today'),
      );
      await controller.handleMethodCall(
        const MethodCall(macOSAppMenuSelectedMethod, 'not-a-command'),
      );
      await controller.handleMethodCall(
        const MethodCall(macOSAppMenuSelectedMethod, 42),
      );
      await controller.handleMethodCall(const MethodCall('unknown', 'inbox'));

      expect(selected, [AppShortcutCommand.today]);
    },
  );

  test('sync only resends changed menu data', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final controller = MacOSAppMenuController(
      channel: channel,
      platform: TargetPlatform.macOS,
    );
    addTearDown(controller.dispose);
    final labels = {
      for (final command in AppShortcutCommand.values) command: command.name,
    };
    final bindings = defaultAppShortcutBindings(TargetPlatform.macOS);

    await controller.sync(labels: labels, bindings: bindings);
    await controller.sync(labels: labels, bindings: bindings);
    await controller.sync(
      labels: labels,
      bindings: {
        ...bindings,
        AppShortcutCommand.quickAdd: const AppShortcutBinding(
          physicalKeyId: 0x0007000d,
          keyLabel: 'J',
          meta: true,
        ),
      },
    );
    final localizedLabels = {...labels, AppShortcutCommand.today: 'Сегодня'};
    await controller.sync(labels: localizedLabels, bindings: bindings);

    expect(calls, hasLength(3));
    final localizedCommands = Map<String, Object?>.from(
      calls.last.arguments as Map,
    );
    expect(localizedCommands[AppShortcutCommand.today.name], {
      'label': 'Сегодня',
      'keyLabel': '3',
      'meta': true,
      'control': false,
      'alt': false,
      'shift': false,
    });
  });
}
