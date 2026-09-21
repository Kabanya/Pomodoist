import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/data/repositories/updates/update_repository.dart';
import 'package:pomodoist/data/repositories/updates/update_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';
import 'package:pomodoist/ui/updates/view_models/update_view_model.dart';
import 'package:pomodoist/utils/result.dart';

UpdateOffer testOffer([String tag = 'v1.1.0']) => UpdateOffer(
  tag: tag,
  version: UpdateVersion.parse(tag),
  notes: 'Faster task lists.',
  asset: UpdateAsset(
    name: 'Pomodoist-x86_64.AppImage',
    size: 12,
    sha256: 'a' * 64,
    url: Uri.parse(
      'https://github.com/Kabanya/Pomodoist/releases/download/$tag/Pomodoist-x86_64.AppImage',
    ),
  ),
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
  Future<UpdateOffer?> findUpdate({
    required UpdateVersion current,
    required UpdateTarget target,
    required UpdateChannel channel,
  }) async {
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
  Future<String?> acknowledgeStartup() async {
    acknowledgements++;
    return null;
  }

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

DesktopUpdateRepository testController({
  FakeUpdateSource? source,
  FakeUpdateInstaller? installer,
  MemoryUpdatePreferences? preferences,
  bool automaticChecks = false,
  bool officialUpdatesAllowed = true,
}) => DesktopUpdateRepository(
  source: source ?? FakeUpdateSource(),
  installer: installer ?? FakeUpdateInstaller(),
  preferences: preferences ?? MemoryUpdatePreferences(),
  installedVersion: () async => '1.0.0+94',
  automaticChecks: automaticChecks,
  officialUpdatesAllowed: officialUpdatesAllowed,
);

typedef UpdateViewHarness = ({
  ProviderContainer container,
  UpdateViewModel view,
});

UpdateViewHarness updateView(DesktopUpdateRepository repository) {
  final container = ProviderContainer(
    overrides: [updateRepositoryProvider.overrideWithValue(repository)],
  );
  container.listen(updateViewModelProvider, (_, _) {});
  return (
    container: container,
    view: container.read(updateViewModelProvider.notifier),
  );
}

void main() {
  test(
    'official updates are denied by default, including manual actions',
    () async {
      final source = FakeUpdateSource();
      final installer = FakeUpdateInstaller();
      final preferences = MemoryUpdatePreferences();
      final repository = DesktopUpdateRepository(
        source: source,
        installer: installer,
        preferences: preferences,
        installedVersion: () async => '1.0.0',
      );
      addTearDown(repository.dispose);
      await repository.start();
      await repository.check();
      await repository.check(manual: true);
      await repository.setChannel(UpdateChannel.rc);
      await repository.update();
      expect(installer.acknowledgements, 1);
      expect(repository.enabled, isFalse);
      expect(source.calls, 0);
      expect(installer.installs, 0);
      expect(preferences.channel, UpdateChannel.stable);
      expect(preferences.seen, isEmpty);
    },
  );

  test('preferences construction does not require a platform plugin', () {
    expect(
      () => SharedUpdatePreferences(_MemoryPreferencesService()),
      returnsNormally,
    );
  });

  test('stable is default and showing a release persists its tag', () async {
    final prefs = MemoryUpdatePreferences();
    final source = FakeUpdateSource();
    final repository = testController(source: source, preferences: prefs);
    addTearDown(repository.dispose);
    expect(await repository.check(), isNot(UpdateCheckOutcome.skipped));
    expect(source.lastChannel, UpdateChannel.stable);
    expect(repository.state.offer, isNotNull);
    expect(prefs.seen, {'v1.1.0'});
  });

  test(
    'dismissal does not install or repeat after restart; manual check reopens',
    () async {
      final prefs = MemoryUpdatePreferences();
      final installer = FakeUpdateInstaller();
      final first = testController(preferences: prefs, installer: installer);
      final harness = updateView(first);
      addTearDown(harness.container.dispose);
      addTearDown(first.dispose);
      await harness.view.check();
      expect(harness.view.state.popupVisible, isTrue);
      harness.view.dismiss();
      await harness.view.check();
      expect(harness.view.state.popupVisible, isFalse);
      expect(installer.installs, 0);
      first.dispose();
      final restarted = testController(preferences: prefs);
      final restartedHarness = updateView(restarted);
      addTearDown(restartedHarness.container.dispose);
      addTearDown(restarted.dispose);
      await restartedHarness.view.check();
      expect(restartedHarness.view.state.popupVisible, isFalse);
      await restartedHarness.view.check(manual: true);
      expect(restartedHarness.view.state.popupVisible, isTrue);
    },
  );

  test('a distinct release gets its own automatic popup', () async {
    final source = FakeUpdateSource();
    final repository = testController(source: source);
    final harness = updateView(repository);
    addTearDown(harness.container.dispose);
    addTearDown(repository.dispose);
    await harness.view.check();
    harness.view.dismiss();
    source.offer = testOffer('v1.2.0');
    await harness.view.check();
    expect(harness.view.state.popupVisible, isTrue);
    expect(harness.view.state.offer!.tag, 'v1.2.0');
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
    expect(next.state.channel, UpdateChannel.rc);
  });

  test('a failed channel write cannot silently opt into RC', () async {
    final prefs = MemoryUpdatePreferences()..failWrites = true;
    final repository = testController(preferences: prefs);
    addTearDown(repository.dispose);
    await repository.setChannel(UpdateChannel.rc);
    expect(repository.state.channel, UpdateChannel.stable);
    expect(repository.state.phase, UpdatePhase.failed);
  });

  test('concurrent checks are coalesced', () async {
    final source = FakeUpdateSource()..gate = Completer<void>();
    final repository = testController(source: source);
    addTearDown(repository.dispose);
    final checking = repository.check();
    expect(await repository.check(), UpdateCheckOutcome.skipped);
    source.gate!.complete();
    expect(await checking, isNot(UpdateCheckOutcome.skipped));
    expect(source.calls, 1);
  });

  test(
    'failed download remains retryable and does not repeat installation',
    () async {
      final installer = FakeUpdateInstaller()..fail = true;
      final repository = testController(installer: installer);
      addTearDown(repository.dispose);
      await repository.check();
      await repository.update();
      expect(repository.state.phase, UpdatePhase.failed);
      expect(repository.state.error, contains('Checksum'));
      expect(repository.state.offer, isNotNull);
      installer.fail = false;
      await repository.update();
      expect(installer.installs, 2);
      expect(repository.state.phase, UpdatePhase.installing);
    },
  );

  test('duplicate Update clicks cannot start concurrent installers', () async {
    final installer = FakeUpdateInstaller()..gate = Completer<void>();
    final repository = testController(installer: installer);
    addTearDown(repository.dispose);
    await repository.check();
    final updating = repository.update();
    await repository.update();
    expect(installer.installs, 1);
    installer.gate!.complete();
    await updating;
  });

  test(
    'stable channel refuses even an incorrectly injected RC offer',
    () async {
      final source = FakeUpdateSource()..offer = testOffer('v2.0.0-rc.1');
      final installer = FakeUpdateInstaller();
      final repository = testController(source: source, installer: installer);
      addTearDown(repository.dispose);
      await repository.check();
      await repository.update();
      expect(installer.installs, 0);
    },
  );

  test('offline checks are quiet automatically and visible manually', () async {
    final source = FakeUpdateSource()..fail = true;
    final repository = testController(source: source);
    final harness = updateView(repository);
    addTearDown(harness.container.dispose);
    addTearDown(repository.dispose);
    await harness.view.check();
    expect(repository.state.phase, UpdatePhase.failed);
    expect(harness.view.state.popupVisible, isFalse);
    expect(repository.state.lastChecked, isNotNull);
    await harness.view.check(manual: true);
    expect(harness.view.state.popupVisible, isTrue);
  });

  test('unsupported platforms do not access the network', () async {
    final source = FakeUpdateSource();
    final installer = FakeUpdateInstaller()..target = null;
    final repository = testController(source: source, installer: installer);
    addTearDown(repository.dispose);
    await repository.start();
    await repository.check(manual: true);
    expect(source.calls, 0);
    expect(repository.isDesktop, isFalse);
  });

  testWidgets('automatic checks start after startup delay and recur', (
    tester,
  ) async {
    final source = FakeUpdateSource();
    final installer = FakeUpdateInstaller();
    final repository = testController(
      source: source,
      installer: installer,
      automaticChecks: true,
    );
    final harness = updateView(repository);
    addTearDown(harness.container.dispose);
    addTearDown(repository.dispose);
    await harness.view.start();
    expect(installer.acknowledgements, 1);
    expect(source.calls, 0);
    await tester.pump(const Duration(seconds: 11));
    expect(source.calls, 1);
    await tester.pump(const Duration(hours: 6));
    expect(source.calls, 2);
    repository.dispose();
    // The widget binding asserts that no timers are pending before tearDowns
    // run, so the container must be disposed here to cancel the view model's
    // periodic timer. ProviderContainer.dispose is idempotent, so the
    // addTearDown registration above remains a harmless safety net.
    harness.container.dispose();
  });
}

class _MemoryPreferencesService implements PreferencesService {
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async => const Success({});

  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      const Success(null);
}
