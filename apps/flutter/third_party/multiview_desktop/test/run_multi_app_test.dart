import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  group('MultiAppConfig', () {
    test('defaultParams uses softCascade close mode and dynamic anchor', () {
      final params = MultiPlatformParams.defaultParams();

      expect(params.enableDynamicAnchor, isTrue);
      expect(params.closeMode, CloseMode.softCascade);
      expect(params.menuItems, isEmpty);
    });

    test('MultiPlatformParams stores initial taskbar menu items', () {
      const items = [
        TaskbarMenuItem(title: 'Open new window'),
        TaskbarMenuItem(title: 'Settings'),
      ];

      const params = MultiPlatformParams(menuItems: items);

      expect(params.menuItems, items);
      expect(params.menuItems.first.title, 'Open new window');
    });

    test('MultiAppConfig factory merges platform params', () {
      final config = MultiAppConfig(
        generalParams: const MultiPlatformParams(
          enableDynamicAnchor: false,
          closeMode: CloseMode.destroy,
        ),
      );

      expect(config.generalParams.enableDynamicAnchor, isFalse);
      expect(config.generalParams.closeMode, CloseMode.destroy);
    });

    test('MacosPlatformParams defaults', () {
      final params = MacosPlatformParams.defaultParams();

      expect(params.saveLastWindowToReopen, isTrue);
      expect(params.onTerminate, isNull);
    });
  });

  group('CloseMode', () {
    test('contains all documented strategies', () {
      expect(CloseMode.values, containsAll([
        CloseMode.none,
        CloseMode.softCascade,
        CloseMode.forceSecondary,
        CloseMode.destroy,
      ]));
    });
  });

  group('DialogOptions', () {
    test('stores modal flag and shell overrides', () {
      const options = DialogOptions(
        modal: true,
        title: 'Settings',
        shellOverrides: ViewShellOverrides(title: 'Shell'),
      );

      expect(options.modal, isTrue);
      expect(options.title, 'Settings');
      expect(options.shellOverrides?.title, 'Shell');
    });
  });
}
