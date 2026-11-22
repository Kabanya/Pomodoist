import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pomodoist/config/custom_model_settings_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/custom_model_repository_impl.dart';
import 'package:pomodoist/data/services/local/custom_model_key_store.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/settings/view_models/custom_model_settings.dart';
import 'package:pomodoist/ui/settings/widgets/custom_model_settings_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/utils/result.dart';

const first = 'https://example.com/one';
const second = 'https://example.com/two';
CustomModelConfig config(String url, [String smart = 'extra']) =>
    CustomModelConfig(
      enabled: true,
      baseUrl: url,
      normalModel: 'fast',
      smartModel: smart,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CustomModelKeyStore keys;
  late PreferencesService prefs;
  late StoredCustomModelRepository repository;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService(SharedPreferences.getInstance);
    keys = CustomModelKeyStore(sessionOnly: true);
    repository = StoredCustomModelRepository(prefs, keys, 'account-1');
  });

  test(
    'native settings reopen the protected credential after restarting',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final original = StoredCustomModelRepository(
        prefs,
        CustomModelKeyStore(sessionOnly: false),
        'native-user',
      );
      await original.save(config(first), apiKey: 'protected-token');
      final reopened = StoredCustomModelRepository(
        prefs,
        CustomModelKeyStore(sessionOnly: false),
        'native-user',
      );
      expect(await reopened.apiKeyFor(first), 'protected-token');
      await reopened.save(config(second));
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    },
  );

  test(
    'a failed settings write restores the previous credential and address',
    () async {
      await repository.save(config(first), apiKey: 'original-token');
      final failing = StoredCustomModelRepository(
        _FailingPreferences(),
        keys,
        'account-1',
      );
      await expectLater(
        failing.save(config(second), apiKey: 'replacement-token'),
        throwsStateError,
      );
      expect((await repository.load()).baseUrl, first);
      expect(await repository.apiKeyFor(first), 'original-token');
      expect(await repository.apiKeyFor(second), '');
    },
  );

  test(
    'settings survive restart; browser keys survive only in the current session',
    () async {
      expect((await repository.load()).enabled, isFalse);
      await repository.save(config(first), apiKey: 'private-token');
      expect(await repository.apiKeyFor(first), 'private-token');
      final stored = await SharedPreferences.getInstance();
      for (final name in stored.getKeys()) {
        expect(stored.get(name).toString(), isNot(contains('private-token')));
      }
      final reload = StoredCustomModelRepository(
        prefs,
        CustomModelKeyStore(sessionOnly: true),
        'account-1',
      );
      expect((await reload.load()).smartModel, 'extra');
      expect((await reload.load()).hasKey, isFalse);
      expect(await reload.apiKeyFor(first), '');
    },
  );

  test(
    'keys are scoped to the full endpoint and account; replacing the endpoint removes its prior key',
    () async {
      final other = StoredCustomModelRepository(prefs, keys, 'account-2');
      await repository.save(config(first), apiKey: 'old-key');
      await other.save(config(first), apiKey: 'other-key');
      expect(await repository.apiKeyFor(second), '');
      await repository.save(config(second));
      expect(await repository.apiKeyFor(second), '');
      expect(await keys.read('customModel.v1.account-1.credential'), isNull);
      await repository.save(config(first));
      expect(await repository.apiKeyFor(first), '');
      expect(await other.apiKeyFor(first), 'other-key');
    },
  );

  test(
    'queued writes use the most recent endpoint and key; explicit blank deletes the key',
    () async {
      await Future.wait([
        repository.save(config(first), apiKey: 'first-key'),
        repository.save(config(second), apiKey: 'second-key'),
        repository.save(config(second)),
      ]);
      expect(await repository.apiKeyFor(first), '');
      expect(await repository.apiKeyFor(second), 'second-key');
      await repository.save(config(second), apiKey: '');
      expect((await repository.load()).hasKey, isFalse);
    },
  );

  test(
    'connection test uses the saved key only at its own URL and probes each distinct model',
    () async {
      final calls = <(String, String, bool)>[];
      final container = ProviderContainer(
        overrides: [
          customModelRepositoryProvider.overrideWithValue(repository),
          customModelAccessProvider.overrideWith((_) async => true),
          customModelProbeProvider.overrideWithValue(({
            required baseUrl,
            required model,
            required apiKey,
            required locale,
            required smart,
          }) async {
            calls.add((model, apiKey, smart));
            return smart ? ModelCheck.invalidResponse : ModelCheck.success;
          }),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(customModelSettingsProvider.notifier);
      await controller.save(config(first), apiKey: 'private-token');
      expect(await controller.check(config(first), locale: 'en'), {
        'fast': ModelCheck.success,
        'extra': ModelCheck.invalidResponse,
      });
      expect(await controller.check(config(second, 'fast'), locale: 'en'), {
        'fast': ModelCheck.success,
      });
      expect(calls, [
        ('fast', 'private-token', false),
        ('extra', 'private-token', true),
        ('fast', '', false),
      ]);
    },
  );

  test(
    'expired access prevents saving and testing a custom route but allows switching to Pomodoist',
    () async {
      await repository.save(config(first), apiKey: 'private-token');
      final container = ProviderContainer(
        overrides: [
          customModelRepositoryProvider.overrideWithValue(repository),
          customModelAccessProvider.overrideWith((_) async => false),
          customModelProbeProvider.overrideWithValue(
            ({
              required baseUrl,
              required model,
              required apiKey,
              required locale,
              required smart,
            }) async => fail('probe reached'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(customModelSettingsProvider.notifier);
      await expectLater(controller.save(config(first)), throwsStateError);
      await expectLater(
        controller.check(config(first), locale: 'en'),
        throwsStateError,
      );
      await controller.save(config(first).withEnabled(false));
      expect((await repository.load()).enabled, isFalse);
    },
  );

  testWidgets(
    'editing the URL clears the typed key before testing the newly selected server',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customModelOwnerProvider.overrideWithValue('account-1'),
            customModelRepositoryProvider.overrideWithValue(repository),
            customModelAccessProvider.overrideWith((_) async => true),
            customModelProbeProvider.overrideWithValue(({
              required baseUrl,
              required model,
              required apiKey,
              required locale,
              required smart,
            }) async {
              calls.add(apiKey);
              return ModelCheck.success;
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: CustomModelSettingsRow()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Default · Pomodoist'), findsOneWidget);
      await tester.tap(find.text('Custom API or server'));
      await tester.pumpAndSettle();
      expect(
        find.text('Leave this blank to use the standard model in Smart mode.'),
        findsOneWidget,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), first);
      await tester.enterText(fields.at(1), 'fast');
      await tester.enterText(fields.at(3), 'private-token');
      await tester.enterText(fields.at(0), second);
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, isEmpty);
      await tester.ensureVisible(find.text('Test connection'));
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(calls, ['']);
      expect(find.text('Test task received'), findsOneWidget);
    },
  );
}

class _FailingPreferences extends PreferencesService {
  _FailingPreferences() : super(SharedPreferences.getInstance);
  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      Result.error(StateError('Cannot save'), StackTrace.current);
}
