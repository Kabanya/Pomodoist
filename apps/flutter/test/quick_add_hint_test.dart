import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saved personalized hints never replace the localized syntax example',
    () async {
      SharedPreferences.setMockInitialValues({
        'quickAdd.hint.createdTaskCount': 100,
        'quickAdd.hint.nextRefreshAt': 150,
        'quickAdd.hint.starterConsumed': true,
        'quickAdd.hint.recent':
            '[{"text":"Старая задача 09:00 #App @coding","locale":"ru"}]',
      });
      final container = ProviderContainer(
        overrides: [
          appLanguageProvider.overrideWithValue(AppLanguage.ru),
          appDatabaseProvider.overrideWith(
            (_) => throw StateError('Hints must not read task history'),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(quickAddHintTextProvider),
        'Название задачи завтра p2 #Проект @метка 2p',
      );
      await pumpEventQueue();
      container.invalidate(quickAddHintTextProvider);
      expect(
        container.read(quickAddHintTextProvider),
        'Название задачи завтра p2 #Проект @метка 2p',
      );
    },
  );

  test('the permanent hint follows language changes without task storage', () {
    var language = AppLanguage.en;
    final container = ProviderContainer(
      overrides: [
        appLanguageProvider.overrideWith((_) => language),
        appDatabaseProvider.overrideWith(
          (_) => throw StateError('Hints must not read task history'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(quickAddHintTextProvider),
      'Task name tomorrow p2 #Project @label 2p',
    );
    language = AppLanguage.ru;
    container.invalidate(appLanguageProvider);
    expect(
      container.read(quickAddHintTextProvider),
      'Название задачи завтра p2 #Проект @метка 2p',
    );
  });
}
