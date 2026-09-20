import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/data/services/planning/quick_add_hint.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository_impl.dart';
import 'package:pomodoist/domain/models/planning/quick_add_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'recreating a hint observer does not reload shared hint state',
    () async {
      final store = _MemoryStore()
        ..state = QuickAddHintState(
          createdTaskCount: 10,
          nextRefreshAt: 25,
          retryPending: false,
          recentHints: const [
            QuickAddHint(text: 'Saved task 09:00 #App @coding', locale: 'en'),
          ],
        );
      final container = ProviderContainer(
        overrides: [
          quickAddHintHistoryProvider.overrideWithValue(
            _FakeHistory(taskCount: 0, titles: const []),
          ),
          quickAddHintStoreProvider.overrideWithValue(store),
          quickAddHintGeneratorProvider.overrideWithValue(
            _FakeGenerator('Unused'),
          ),
          billingRepositoryProvider.overrideWithValue(_Billing()),
          billingAccessProvider.overrideWith((_) => const Stream.empty()),
          appLanguageProvider.overrideWithValue(AppLanguage.en),
        ],
      );
      addTearDown(container.dispose);
      final observer = container.listen(quickAddHintStateProvider, (_, _) {});
      addTearDown(observer.close);
      await pumpEventQueue();
      expect(store.reads, 1);
      expect(container.read(quickAddHintStateProvider).createdTaskCount, 10);
      expect(
        container.read(quickAddHintTextProvider),
        'Saved task 09:00 #App @coding',
      );
      container.invalidate(quickAddHintStateProvider);
      await pumpEventQueue();
      expect(store.reads, 1);
    },
  );

  group('quick-add hint refresh thresholds', () {
    test('late generation cannot publish or persist after disposal', () async {
      final generator = _PendingGenerator();
      final store = _MemoryStore();
      final repository = StoredQuickAddHintRepository(
        history: _FakeHistory(taskCount: 10, titles: const ['One']),
        store: store,
        generator: generator,
        locale: () => 'en',
      );
      final snapshots = <QuickAddHintState>[];
      final subscription = repository.watch().listen(snapshots.add);
      addTearDown(subscription.cancel);
      addTearDown(repository.dispose);
      final pending = repository.initialize();
      await generator.started.future;
      final lastState = store.state;
      final count = snapshots.length;
      repository.dispose();
      generator.result.complete('Late task 09:00 #App @coding');
      await pending;
      await repository.recordUserTaskCreated();
      expect(store.state, same(lastState));
      expect(snapshots, hasLength(count));
      expect(repository.state, same(lastState));
    });

    test('hint snapshots own their saved hint list', () {
      final hints = [const QuickAddHint(text: 'Saved', locale: 'en')];
      final state = QuickAddHintState(
        createdTaskCount: 10,
        nextRefreshAt: 25,
        retryPending: false,
        recentHints: hints,
      );
      hints.clear();
      expect(state.recentHints.single.text, 'Saved');
      expect(() => state.recentHints.clear(), throwsUnsupportedError);
    });

    test('use 1, 10, 25, 50, then 50-task intervals', () {
      expect(nextQuickAddHintRefreshAfter(0), 1);
      expect(nextQuickAddHintRefreshAfter(1), 10);
      expect(nextQuickAddHintRefreshAfter(10), 25);
      expect(nextQuickAddHintRefreshAfter(25), 50);
      expect(nextQuickAddHintRefreshAfter(50), 100);
      expect(nextQuickAddHintRefreshAfter(100), 150);
      expect(nextQuickAddHintRefreshAfter(151), 200);
    });

    test('free users use 50-task intervals through one thousand tasks', () {
      expect(firstQuickAddHintRefreshAt(hasActiveEntitlement: false), 1);
      expect(nextQuickAddHintRefreshAfter(0, hasActiveEntitlement: false), 1);
      expect(nextQuickAddHintRefreshAfter(1, hasActiveEntitlement: false), 10);
      expect(
        nextQuickAddHintRefreshAfter(50, hasActiveEntitlement: false),
        100,
      );
      expect(
        nextQuickAddHintRefreshAfter(999, hasActiveEntitlement: false),
        1000,
      );
      expect(
        nextQuickAddHintRefreshAfter(1000, hasActiveEntitlement: false),
        1500,
      );
    });

    test(
      'generates at the first manually created task and schedules the tenth',
      () async {
        final history = _FakeHistory(
          taskCount: 0,
          titles: List<String>.generate(12, (index) => 'Task $index'),
        );
        final generator = _FakeGenerator(
          'Prepare the project brief 09:00 #App @coding',
        );
        final coordinator = StoredQuickAddHintRepository(
          history: history,
          store: _MemoryStore(),
          generator: generator,
          locale: () => 'ru',
        );

        await coordinator.initialize();
        await coordinator.recordUserTaskCreated();

        expect(generator.calls, hasLength(1));
        expect(generator.calls.single.titles, hasLength(10));
        expect(
          generator.calls.single.titles,
          orderedEquals(history.titles.take(10)),
        );
        expect(
          coordinator.state.hintForLocale('ru'),
          'Prepare the project brief 09:00 #App @coding',
        );
        expect(coordinator.state.nextRefreshAt, 10);
        expect(coordinator.state.retryPending, isFalse);
      },
    );

    test(
      'generates immediately for existing history and schedules the next threshold',
      () async {
        final generator = _FakeGenerator(
          'Review current priorities 09:00 #App @planning',
        );
        final coordinator = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 50, titles: const ['One']),
          store: _MemoryStore(),
          generator: generator,
          locale: () => 'ru',
        );

        await coordinator.initialize();

        expect(generator.calls, hasLength(1));
        expect(coordinator.state.nextRefreshAt, 100);
        expect(coordinator.state.hintForLocale('en'), isNull);
      },
    );

    test('uses the free schedule for existing history', () async {
      final generator = _FakeGenerator(
        'Review current priorities 09:00 #App @planning',
      );
      final coordinator = StoredQuickAddHintRepository(
        history: _FakeHistory(taskCount: 100, titles: const ['One']),
        store: _MemoryStore(),
        generator: generator,
        locale: () => 'ru',
        hasActiveEntitlement: () => false,
      );

      await coordinator.initialize();

      expect(generator.calls, hasLength(1));
      expect(coordinator.state.nextRefreshAt, 150);
    });

    test(
      'aligns a stored free user with the new, less frequent schedule',
      () async {
        final store = _MemoryStore()
          ..state = QuickAddHintState(
            createdTaskCount: 120,
            nextRefreshAt: 150,
            retryPending: false,
          );
        final coordinator = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 120, titles: const ['One']),
          store: store,
          generator: _FakeGenerator('Unused'),
          locale: () => 'ru',
          hasActiveEntitlement: () => false,
        );

        await coordinator.initialize();

        expect(coordinator.state.nextRefreshAt, 150);
      },
    );

    test(
      'uses the paid schedule after an upgrade before the next task',
      () async {
        var hasPaidEntitlement = false;
        final generator = _FakeGenerator(
          'Plan the next step 09:00 #App @planning',
        );
        final store = _MemoryStore()
          ..state = QuickAddHintState(
            createdTaskCount: 99,
            nextRefreshAt: 100,
            retryPending: false,
          );
        final coordinator = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 99, titles: const ['One']),
          store: store,
          generator: generator,
          locale: () => 'ru',
          hasActiveEntitlement: () => hasPaidEntitlement,
        );

        await coordinator.initialize();
        hasPaidEntitlement = true;
        await coordinator.recordUserTaskCreated();

        expect(generator.calls, hasLength(1));
        expect(coordinator.state.nextRefreshAt, 150);
      },
    );

    test(
      'recalculates the next threshold immediately after an early upgrade',
      () async {
        var hasPaidEntitlement = false;
        final generator = _FakeGenerator(
          'Plan the next step 09:00 #App @planning',
        );
        final store = _MemoryStore()
          ..state = QuickAddHintState(
            createdTaskCount: 20,
            nextRefreshAt: 50,
            retryPending: false,
          );
        final coordinator = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 20, titles: const ['One']),
          store: store,
          generator: generator,
          locale: () => 'ru',
          hasActiveEntitlement: () => hasPaidEntitlement,
        );

        await coordinator.initialize();
        hasPaidEntitlement = true;
        await coordinator.recordUserTaskCreated();

        expect(generator.calls, isEmpty);
        expect(coordinator.state.nextRefreshAt, 25);
      },
    );

    test(
      'keeps the previous hint and retries a failed threshold on the next launch',
      () async {
        final store = _MemoryStore();
        final first = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 10, titles: const ['First']),
          store: store,
          generator: _FailingGenerator(),
          locale: () => 'ru',
        );

        await first.initialize();
        expect(first.state.retryPending, isTrue);
        expect(first.state.hintForLocale('ru'), isNull);

        final second = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 10, titles: const ['First']),
          store: store,
          generator: _FakeGenerator('Plan the next step 09:00 #App @planning'),
          locale: () => 'ru',
        );

        await second.initialize();
        expect(
          second.state.hintForLocale('ru'),
          'Plan the next step 09:00 #App @planning',
        );
        expect(second.state.nextRefreshAt, 25);
        expect(second.state.retryPending, isFalse);
      },
    );

    test('keeps only the five most recent generated hints', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final coordinator = StoredQuickAddHintRepository(
        history: _FakeHistory(taskCount: 0, titles: const ['One']),
        store: SharedPreferencesQuickAddHintStore(() async => preferences),
        generator: _SequenceGenerator(
          List<String>.generate(
            6,
            (index) => 'Generated hint ${index + 1} 09:00 #App @coding',
          ),
        ),
        locale: () => 'ru',
      );

      await coordinator.initialize();
      for (var index = 0; index < 150; index++) {
        await coordinator.recordUserTaskCreated();
      }

      final stored = preferences.getString('quickAdd.hint.recent');
      expect(stored, isNotNull);
      final hints = (jsonDecode(stored!) as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(
        hints.map((hint) => hint['text']),
        orderedEquals([
          'Generated hint 2 09:00 #App @coding',
          'Generated hint 3 09:00 #App @coding',
          'Generated hint 4 09:00 #App @coding',
          'Generated hint 5 09:00 #App @coding',
          'Generated hint 6 09:00 #App @coding',
        ]),
      );
    });

    test('selects a random saved hint for the current locale', () {
      final state = QuickAddHintState(
        createdTaskCount: 50,
        nextRefreshAt: 100,
        retryPending: false,
        recentHints: const [
          QuickAddHint(text: 'Russian one', locale: 'ru'),
          QuickAddHint(text: 'English 09:00 #App @coding', locale: 'en'),
          QuickAddHint(text: 'Russian two 09:00 #App @coding', locale: 'ru'),
        ],
      );

      expect(
        state.hintForLocale(
          'ru',
          randomIndex: (upperBound) {
            expect(upperBound, 2);
            return 1;
          },
        ),
        'Russian two 09:00 #App @coding',
      );
      expect(state.hintForLocale('de', randomIndex: (_) => 0), isNull);
    });

    test(
      'ignores unavailable history during background initialization',
      () async {
        final coordinator = StoredQuickAddHintRepository(
          history: _UnavailableHistory(),
          store: _MemoryStore(),
          generator: _FakeGenerator('Unused'),
          locale: () => 'ru',
        );

        await coordinator.initialize();

        expect(coordinator.state.createdTaskCount, 0);
        expect(coordinator.state.retryPending, isFalse);
      },
    );
  });

  group('quick-add hint response', () {
    test('accepts a complete ready-to-add hint', () {
      expect(
        decodeQuickAddHintJson(
          '{"hint":"Prepare release tomorrow 14:30 #App @coding"}',
        ),
        'Prepare release tomorrow 14:30 #App @coding',
      );
    });

    test('rejects incomplete, malformed, multiline, and overlong hints', () {
      expect(decodeQuickAddHintJson('{"hint":""}'), isNull);
      expect(decodeQuickAddHintJson('{"hint":"First\\nSecond"}'), isNull);
      expect(decodeQuickAddHintJson('{"hint":"Plan 14:30 #Work"}'), isNull);
      expect(decodeQuickAddHintJson('{"hint":"Plan 14:30 @coding"}'), isNull);
      expect(decodeQuickAddHintJson('{"hint":"Plan #Work @coding"}'), isNull);
      expect(
        decodeQuickAddHintJson('{"hint":"Plan 25:00 #Work @coding"}'),
        isNull,
      );
      expect(
        decodeQuickAddHintJson('{"hint":"Plan 14:30 #Work #App @coding"}'),
        isNull,
      );
      expect(
        decodeQuickAddHintJson('{"hint":"Plan 14:30 #Work @coding @review"}'),
        isNull,
      );
      expect(decodeQuickAddHintJson('{"hint":"${'a' * 121}"}'), isNull);
    });

    test(
      'successful AI generation marks the starter hint as consumed',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final coordinator = StoredQuickAddHintRepository(
          history: _FakeHistory(taskCount: 0, titles: const ['One']),
          store: SharedPreferencesQuickAddHintStore(() async => preferences),
          generator: _FakeGenerator('Plan next step 09:00 #App @coding'),
          locale: () => 'ru',
        );

        await coordinator.initialize();
        await coordinator.recordUserTaskCreated();

        expect(preferences.getBool('quickAdd.hint.starterConsumed'), isTrue);
      },
    );

    test('drops cached hints that are not ready-to-add', () async {
      SharedPreferences.setMockInitialValues({
        'quickAdd.hint.createdTaskCount': 10,
        'quickAdd.hint.nextRefreshAt': 25,
        'quickAdd.hint.recent':
            '[{"text":"Plan the weekly review","locale":"ru"}]',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesQuickAddHintStore(() async => preferences);

      final state = await store.read();

      expect(state!.recentHints, isEmpty);
    });
  });

  test('DeepSeek request sends only the ten most recent task titles', () {
    final request = buildDeepSeekQuickAddHintRequest(
      recentTaskTitles: List<String>.generate(12, (index) => 'Title $index'),
      locale: 'ru',
    );
    final messages = request['messages']! as List<Map<String, String>>;
    final systemContent = messages.first['content']!;
    final userContent = messages.last['content']!;

    expect(request['model'], deepSeekQuickAddHintModel);
    expect(userContent, contains('Locale: ru'));
    expect(userContent, contains('- Title 0'));
    expect(userContent, contains('- Title 9'));
    expect(userContent, isNot(contains('Title 10')));
    expect(userContent, isNot(contains('description')));
    expect(systemContent, contains('#project'));
    expect(systemContent, contains('@label'));
    expect(systemContent, contains('HH:mm'));
  });
}

class _FakeHistory implements QuickAddHintHistory {
  const _FakeHistory({required this.taskCount, required this.titles});

  final int taskCount;
  final List<String> titles;

  @override
  Future<int> countExistingUserTasks() async => taskCount;

  @override
  Future<List<String>> recentTaskTitles({required int limit}) async =>
      titles.take(limit).toList();
}

class _MemoryStore implements QuickAddHintStore {
  QuickAddHintState? state;
  int reads = 0;

  @override
  Future<QuickAddHintState?> read() async {
    reads++;
    return state;
  }

  @override
  Future<void> write(QuickAddHintState value) async {
    state = value;
  }
}

class _Billing implements BillingRepository {
  @override
  BillingAccess get currentAccess => (
    hasActiveEntitlement: false,
    hasLocalStoreKitEntitlement: false,
    loading: false,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UnavailableHistory implements QuickAddHintHistory {
  @override
  Future<int> countExistingUserTasks() {
    throw StateError('Database is closed.');
  }

  @override
  Future<List<String>> recentTaskTitles({required int limit}) {
    throw StateError('Database is closed.');
  }
}

class _FakeGenerator implements QuickAddHintGenerator {
  _FakeGenerator(this.result);

  final String result;
  final calls = <({List<String> titles, String locale})>[];

  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) async {
    calls.add((titles: recentTaskTitles, locale: locale));
    return result;
  }
}

class _FailingGenerator implements QuickAddHintGenerator {
  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) {
    throw const QuickAddHintException('DeepSeek is unavailable.');
  }
}

class _PendingGenerator implements QuickAddHintGenerator {
  final started = Completer<void>();
  final result = Completer<String>();
  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) {
    started.complete();
    return result.future;
  }
}

class _SequenceGenerator implements QuickAddHintGenerator {
  _SequenceGenerator(this._hints);

  final List<String> _hints;
  var _index = 0;

  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) async {
    return _hints[_index++];
  }
}
