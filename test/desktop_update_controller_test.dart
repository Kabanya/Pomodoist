import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/updates/update_contracts.dart';
import 'package:pomodoist/features/updates/update_controller.dart';
import 'package:pomodoist/features/updates/update_release.dart';

UpdateOffer testOffer([String tag = 'v1.1.0']) => UpdateOffer(
  tag: tag, version: UpdateVersion.parse(tag), notes: 'Faster task lists.',
  asset: UpdateAsset(name: 'Pomodoist-x86_64.AppImage', size: 12,
    sha256: 'a' * 64,
    url: Uri.parse('https://github.com/Kabanya/Pomodoist/releases/download/$tag/Pomodoist-x86_64.AppImage')),
);

class MemoryUpdatePreferences implements UpdatePreferences {
  UpdateChannel channel = UpdateChannel.stable;
  Set<String> seen = {};
  bool failWrites = false;
  @override
  Future<SavedUpdatePreferences> load() async =>
      SavedUpdatePreferences(channel: channel, seenTags: {...seen});
  @override
  Future<void> setChannel(UpdateChannel value) async {
    if (failWrites) throw StateError('Storage unavailable');
    channel = value;
  }
  @override
  Future<void> markSeen(Set<String> tags) async {
    if (failWrites) throw StateError('Storage unavailable');
    seen = {...tags};
  }
}

class FakeUpdateSource implements UpdateSource {
  UpdateOffer? offer = testOffer();
  UpdateChannel? lastChannel;
  int calls = 0;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<UpdateOffer?> findUpdate({required UpdateVersion current,
    required UpdateTarget target, required UpdateChannel channel}) async {
    calls++;
    lastChannel = channel;
    await gate?.future;
    if (fail) throw const UpdateFailure('Network unavailable');
    return offer;
  }
  @override
  void dispose() {}
}

class FakeUpdateInstaller implements UpdateInstaller {
  int installs = 0;
  int acknowledgements = 0;
  bool fail = false;
  Completer<void>? gate;
  UpdateProgress? report;
  @override
  UpdateTarget? target = const UpdateTarget(UpdateOS.linux, UpdateArch.x64);
  @override
  String? unavailableReason;
  @override
  Future<String?> acknowledgeStartup() async { acknowledgements++; return null; }
  @override
  Future<void> install(UpdateOffer offer, UpdateProgress progress) async {
    installs++;
    report = progress;
    progress(UpdatePhase.downloading, 0.25);
    await gate?.future;
    if (fail) throw const UpdateFailure('Checksum mismatch');
    progress(UpdatePhase.verifying, null);
    progress(UpdatePhase.installing, null);
  }
  @override
  void dispose() {}
}

DesktopUpdateController testController({FakeUpdateSource? source,
  FakeUpdateInstaller? installer, MemoryUpdatePreferences? preferences,
  bool automaticChecks = false}) => DesktopUpdateController(
    source: source ?? FakeUpdateSource(), installer: installer ?? FakeUpdateInstaller(),
    preferences: preferences ?? MemoryUpdatePreferences(),
    installedVersion: () async => '1.0.0+94', automaticChecks: automaticChecks);

void main() {
  test('stable is default and showing a release persists its tag', () async {
    final prefs = MemoryUpdatePreferences();
    final source = FakeUpdateSource();
    final controller = testController(source: source, preferences: prefs);
    addTearDown(controller.dispose);
    await controller.check();
    expect(source.lastChannel, UpdateChannel.stable);
    expect(controller.popupVisible, isTrue);
    expect(prefs.seen, {'v1.1.0'});
  });

  test('dismissal does not install or repeat after restart; manual check reopens', () async {
    final prefs = MemoryUpdatePreferences();
    final installer = FakeUpdateInstaller();
    final first = testController(preferences: prefs, installer: installer);
    await first.check();
    first.dismiss();
    await first.check();
    expect(first.popupVisible, isFalse);
    expect(installer.installs, 0);
    first.dispose();
    final restarted = testController(preferences: prefs);
    addTearDown(restarted.dispose);
    await restarted.check();
    expect(restarted.popupVisible, isFalse);
    await restarted.check(manual: true);
    expect(restarted.popupVisible, isTrue);
  });

  test('a distinct release gets its own automatic popup', () async {
    final source = FakeUpdateSource();
    final controller = testController(source: source);
    addTearDown(controller.dispose);
    await controller.check();
    controller.dismiss();
    source.offer = testOffer('v1.2.0');
    await controller.check();
    expect(controller.popupVisible, isTrue);
    expect(controller.offer!.tag, 'v1.2.0');
  });

  test('RC channel persists and is used after restart', () async {
    final prefs = MemoryUpdatePreferences();
    final first = testController(preferences: prefs);
    await first.setChannel(UpdateChannel.rc);
    first.dispose();
    final source = FakeUpdateSource();
    final next = testController(preferences: prefs, source: source);
    addTearDown(next.dispose);
    await next.check();
    expect(source.lastChannel, UpdateChannel.rc);
    expect(next.channel, UpdateChannel.rc);
  });

  test('a failed channel write cannot silently opt into RC', () async {
    final prefs = MemoryUpdatePreferences()..failWrites = true;
    final controller = testController(preferences: prefs);
    addTearDown(controller.dispose);
    await controller.setChannel(UpdateChannel.rc);
    expect(controller.channel, UpdateChannel.stable);
    expect(controller.phase, UpdatePhase.failed);
  });

  test('concurrent checks are coalesced', () async {
    final source = FakeUpdateSource()..gate = Completer<void>();
    final controller = testController(source: source);
    addTearDown(controller.dispose);
    final checking = controller.check();
    await controller.check();
    source.gate!.complete();
    await checking;
    expect(source.calls, 1);
  });

  test('failed download remains retryable and does not repeat installation', () async {
    final installer = FakeUpdateInstaller()..fail = true;
    final controller = testController(installer: installer);
    addTearDown(controller.dispose);
    await controller.check();
    await controller.update();
    expect(controller.phase, UpdatePhase.failed);
    expect(controller.error, contains('Checksum'));
    expect(controller.offer, isNotNull);
    installer.fail = false;
    await controller.update();
    expect(installer.installs, 2);
    expect(controller.phase, UpdatePhase.installing);
  });

  test('duplicate Update clicks cannot start concurrent installers', () async {
    final installer = FakeUpdateInstaller()..gate = Completer<void>();
    final controller = testController(installer: installer);
    addTearDown(controller.dispose);
    await controller.check();
    final updating = controller.update();
    await controller.update();
    expect(installer.installs, 1);
    installer.gate!.complete();
    await updating;
  });

  test('stable channel refuses even an incorrectly injected RC offer', () async {
    final source = FakeUpdateSource()..offer = testOffer('v2.0.0-rc.1');
    final installer = FakeUpdateInstaller();
    final controller = testController(source: source, installer: installer);
    addTearDown(controller.dispose);
    await controller.check();
    await controller.update();
    expect(installer.installs, 0);
  });

  test('offline checks are quiet automatically and visible manually', () async {
    final source = FakeUpdateSource()..fail = true;
    final controller = testController(source: source);
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.phase, UpdatePhase.failed);
    expect(controller.popupVisible, isFalse);
    expect(controller.lastChecked, isNotNull);
    await controller.check(manual: true);
    expect(controller.popupVisible, isTrue);
  });

  test('unsupported platforms do not access the network', () async {
    final source = FakeUpdateSource();
    final installer = FakeUpdateInstaller()..target = null;
    final controller = testController(source: source, installer: installer);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.check(manual: true);
    expect(source.calls, 0);
    expect(controller.isDesktop, isFalse);
  });

  testWidgets('automatic checks start after startup delay and recur', (tester) async {
    final source = FakeUpdateSource();
    final installer = FakeUpdateInstaller();
    final controller = testController(source: source, installer: installer, automaticChecks: true);
    await controller.start();
    expect(installer.acknowledgements, 1);
    expect(source.calls, 0);
    await tester.pump(const Duration(seconds: 11));
    expect(source.calls, 1);
    await tester.pump(const Duration(hours: 6));
    expect(source.calls, 2);
    controller.dispose();
  });
}
