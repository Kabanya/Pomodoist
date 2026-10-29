import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/theme_settings_dependencies.dart';
import 'package:pomodoist/data/services/agent_settings/agent_app_settings_runtime.dart';
import 'package:pomodoist/data/services/agent_settings/remote_theme_image.dart';
import 'package:pomodoist/config/agent_app_settings_adapter.dart';

/// Watched only by the main app root, never by the separate Quick Add window.
final agentAppSettingsRuntimeProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final account = ref.watch(accountClientProvider);
  final signedIn = ref.watch(
    accountAuthStateProvider.select((state) => state.value?.signedIn),
  );
  final owner = ref.watch(
    accountAuthStateProvider.select((state) => state.value?.session?.userId),
  );
  if (account == null ||
      signedIn != true ||
      owner == null ||
      account.currentUserId != owner) {
    return;
  }
  bool isCurrent() => ref.mounted && account.currentUserId == owner;
  final device = ref.watch(pomodoistDeviceIdProvider.future);
  final preferences = ref.watch(sharedPreferencesProvider.future);
  final deviceId = await device;
  final prefs = await preferences;
  if (!isCurrent() || prefs == null) return;
  final client = ref.read(accountOverviewSupabaseClientProvider);
  final importer = ref.read(themeImageImportRepositoryProvider);
  final adapter = AgentAppSettingsAdapter(
    ref,
    isCurrent: isCurrent,
    importImage: (uri) async {
      final bytes = await downloadRemoteThemeImage(uri);
      if (!isCurrent()) throw StateError('The account changed.');
      return importer.prepare(XFile.fromData(bytes, name: 'background'));
    },
  );
  final journalKey = 'agent.settings.journal.$owner.$deviceId';
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  final runtime = AgentAppSettingsRuntime(
    deviceId: deviceId,
    instanceId: const Uuid().v4(),
    name:
        '${kIsWeb ? 'Browser' : defaultTargetPlatform.name} · ${deviceId.substring(0, deviceId.length.clamp(0, 8))}',
    platform: platform,
    capabilities: AgentAppSettingsAdapter.capabilitiesFor(
      defaultTargetPlatform,
      isWeb: kIsWeb,
    ),
    isCurrent: isCurrent,
    invoke: (body) async {
      if (!isCurrent()) throw StateError('The account changed.');
      final value = await client
          .schema('api_v1')
          .rpc('pomodoist_app_settings_device', params: {'p_command': body})
          .timeout(const Duration(seconds: 15));
      if (!isCurrent()) throw StateError('The account changed.');
      return Map<String, dynamic>.from(value as Map);
    },
    snapshot: adapter.snapshot,
    apply: adapter.apply,
    readJournal: () async {
      await prefs.reload();
      final saved = prefs.getString(journalKey);
      if (saved == null) {
        return null;
      }
      try {
        return Map<String, dynamic>.from(jsonDecode(saved) as Map);
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      }
    },
    writeJournal: (value) async {
      if (!isCurrent()) throw StateError('The account changed.');
      final saved = value == null
          ? await prefs.remove(journalKey)
          : await prefs.setString(journalKey, jsonEncode(value));
      if (!saved) {
        throw StateError('Could not persist the settings receipt.');
      }
    },
    hints: account.syncHints(appId: AccountAppId.pomodoist).map((_) {}),
  );
  ref.onDispose(runtime.dispose);
  runtime.start();
}, retry: (_, _) => null);
