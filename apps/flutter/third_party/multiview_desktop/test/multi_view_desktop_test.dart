import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  group('MultiViewDesktop', () {
    test('WindowInfo records dialog and modal flags', () {
      const info = (isModal: true, isDialog: true);
      expect(info.isModal, isTrue);
      expect(info.isDialog, isTrue);
    });

    test('CloseMode values match runMultiApp configuration', () {
      final config = MultiAppConfig(
        generalParams: const MultiPlatformParams(
          closeMode: CloseMode.forceSecondary,
          menuItems: [
            TaskbarMenuItem(title: 'Open new window'),
          ],
        ),
      );
      expect(config.generalParams.closeMode, CloseMode.forceSecondary);
      expect(config.generalParams.menuItems, hasLength(1));
      expect(config.generalParams.menuItems.single.title, 'Open new window');
    });

    test('DialogOptions and WindowOptions accept shell overrides', () {
      const shell = ViewShellOverrides(title: 'Settings');
      const windowOpts = WindowOptions(shellOverrides: shell);
      const dialogOpts = DialogOptions(modal: true, shellOverrides: shell);

      expect(windowOpts.shellOverrides?.title, 'Settings');
      expect(dialogOpts.modal, isTrue);
      expect(dialogOpts.shellOverrides?.title, 'Settings');
    });
  });
}
