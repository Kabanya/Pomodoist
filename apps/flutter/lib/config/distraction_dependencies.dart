import 'dart:async';
import 'dart:ui' as ui;
import 'package:app_account/app_account.dart' show AccountAppId;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/ai_quota_dependencies.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/shared_focus_effects.dart';
import 'package:pomodoist/data/services/local/focus_adoption_service.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/repositories/distractions/distraction_repository.dart';
import 'package:pomodoist/config/distraction_repository.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/config/distraction_protection_coordinator.dart';
import 'package:pomodoist/data/services/platform/distraction_native_gateway.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

bool get desktopDistractionsAvailable =>
    !kIsWeb &&
    [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ].contains(defaultTargetPlatform);
final liveFocusRepositoryProvider = Provider<LiveFocusRepository>((ref) {
  ref.watch(
    accountAuthStateProvider.select(
      (state) => (state.value?.signedIn, state.value?.session?.userId),
    ),
  );
  final account = ref.watch(accountClientProvider);
  final owner = account?.currentUserId ?? 'local';
  final prefs = ref.watch(sharedPreferencesProvider).value;
  final device = prefs?.getString('distractions.deviceId') ?? const Uuid().v4();
  if (prefs != null) {
    unawaited(prefs.setString('distractions.deviceId', device));
  }
  final repository = LiveFocusRepository(
    local: ref.watch(localFocusRepositoryProvider),
    owner: owner,
    deviceId: device,
    preferences: prefs,
    onServerOwned: ref.watch(serverOwnedFocusRunIdsProvider).add,
    adoptionHistory: (runId, currentId) => exportFocusAdoptionHistory(
      ref.read(appDatabaseProvider),
      runId,
      currentId,
    ),
    onTransition: ref.watch(sharedFocusEffectsProvider(owner)).transition,
    onAdopted: (runId) =>
        acknowledgeAdoptedFocusRun(ref.read(appDatabaseProvider), runId),
    remote: account?.currentUserId == null
        ? null
        : (command) async {
            if (account?.currentUserId != owner) {
              throw StateError('The account session has changed.');
            }
            final client = ref.read(accountOverviewSupabaseClientProvider);
            final value = await client.rpc(
              'pomodoist_focus',
              params: {'p_command': command},
            );
            if (account?.currentUserId != owner) {
              throw StateError('The account session has changed.');
            }
            return Map<String, dynamic>.from(value as Map);
          },
  );
  if (prefs != null) unawaited(repository.start());
  final hints = account?.currentUserId == null
      ? null
      : account
            ?.syncHints(appId: AccountAppId.pomodoist)
            .listen((_) => unawaited(repository.refresh()));
  ref.onDispose(() {
    unawaited(hints?.cancel() ?? Future.value());
    unawaited(repository.dispose());
  });
  return repository;
});

class _ProtectionLifetime {
  Future<void> shutdown = Future.value();
}

final _protectionLifetimeProvider = Provider((ref) => _ProtectionLifetime());

final protectionCoordinatorProvider = FutureProvider<ProtectionCoordinator?>((
  ref,
) async {
  if (!desktopDistractionsAvailable) return null;
  final focus = ref.watch(liveFocusRepositoryProvider);
  final prefs = ref.watch(sharedPreferencesProvider).value;
  if (prefs == null) return null;
  final lifetime = ref.read(_protectionLifetimeProvider);
  await lifetime.shutdown;
  if (!ref.mounted) return null;
  final asset = await rootBundle.load('assets/pomo/focus-still.webp');
  final codec = await ui.instantiateImageCodec(
    asset.buffer.asUint8List(),
    targetWidth: 160,
  );
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  if (!ref.mounted) return null;
  final db = ref.read(appDatabaseProvider);
  final service = ProtectionCoordinator(
    focus: focus,
    native: DistractionNativeGateway(),
    flavor: appFlavor.name,
    preferences: prefs,
    mascotImage: png?.buffer.asUint8List(),
    taskTitle: (id) async => (await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull())?.content,
  );
  final starting = service.start();
  ref.onDispose(() {
    lifetime.shutdown = () async {
      try {
        await starting;
      } on Object {
        /* Cleanup also follows failed startup. */
      }
      await service.dispose();
    }();
  });
  await starting;
  return service;
});

final distractionRepositoryProvider = Provider<DistractionRepository?>((ref) {
  if (!desktopDistractionsAvailable) return null;
  final focus = ref.watch(liveFocusRepositoryProvider);
  ref.watch(protectionCoordinatorProvider);
  final repository = CoordinatedDistractionRepository(
    focus,
    protection: () => ref.read(protectionCoordinatorProvider).value,
    classifyResource: (resource) async {
      final account = ref.read(accountClientProvider);
      if (account?.currentUserId != focus.owner) {
        throw StateError('Sign in to classify resources.');
      }
      final response = await account!.invokeFunction(
        'pomodoist-ai',
        body: {
          'apiVersion': 1,
          'command': {
            'type': 'resource.classify',
            'resource': {
              'kind': resource.kind,
              'id': resource.id,
              'name': resource.name,
              if (resource.json['platform'] != null)
                'platform': resource.json['platform'],
            },
          },
        },
      );
      if (account.currentUserId != focus.owner) {
        throw StateError('The account session has changed.');
      }
      ref.invalidate(aiQuotaRepositoryProvider);
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['ok'] != true || data['assignment'] is! Map) {
        throw StateError('The resource could not be classified.');
      }
      return ResourceAssignment.fromJson(
        Map<String, dynamic>.from(data['assignment']),
      );
    },
  );
  repository.automatic =
      focus.preferences?.getBool('distractions.automatic.${focus.owner}') ==
      true;
  final attempted = <String>{};
  bool classifying = false;
  Future<void> classifyNew() async {
    if (classifying ||
        !repository.automatic ||
        !focus.online ||
        ref.read(accountOverviewProvider).value?.profile.isPro != true) {
      return;
    }
    classifying = true;
    try {
      final known = {
        for (final r in [
          ...?ref.read(protectionCoordinatorProvider).value?.inventory,
          ...focus.assignments,
        ])
          '${r.kind}:${r.id}': r,
      };
      for (final resource in known.values) {
        final key = '${resource.kind}:${resource.id}';
        if (!ref.mounted || !repository.automatic) break;
        if (resource.category != 'unclassified' || !attempted.add(key)) {
          continue;
        }
        try {
          await repository.classify(resource);
        } on Object catch (e) {
          focus.error = e.toString();
          focus.notify();
        }
      }
    } finally {
      classifying = false;
    }
  }

  final subscription = focus.changes.listen((_) => unawaited(classifyNew()));
  ref.listen(accountOverviewProvider, (_, next) => unawaited(classifyNew()));
  ref.onDispose(subscription.cancel);
  unawaited(Future<void>.microtask(classifyNew));
  return repository;
});
