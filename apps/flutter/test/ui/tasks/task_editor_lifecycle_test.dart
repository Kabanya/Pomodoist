import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a failed draft keeps the editor registered until a retry succeeds',
    () async {
      final repository = _FakeTaskRepository();
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final task = _task('detail', description: 'Original');
      final identity = Object();
      final guard = container.read(taskDetailSaveGuardProvider);
      final editor = container.read(
        taskEditorViewModelProvider(identity).notifier,
      );
      guard.register(
        identity,
        () => editor.saveDescription(task, editor.state.draft),
      );
      addTearDown(() => guard.unregister(identity));

      editor.updateDraft('Edited description');
      repository.failNextUpdate = true;
      expect(await guard.saveAll(), isFalse);
      expect(editor.state.draft, 'Edited description');
      expect(editor.state.failed, isTrue);
      expect(guard.hasRegisteredEditors, isTrue);

      repository.failNextUpdate = false;
      expect(await guard.saveAll(), isTrue);
      expect(editor.state.failed, isFalse);
      expect(editor.state.draft, 'Edited description');
      expect(repository.descriptions, ['Edited description']);
    },
  );

  test('the guard resolves the editor again after provider disposal', () async {
    final repository = _FakeTaskRepository();
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    final task = _task('detail');
    final identity = Object();
    final guard = container.read(taskDetailSaveGuardProvider);
    final listener = container.listen(
      taskEditorViewModelProvider(identity),
      (_, _) {},
      fireImmediately: true,
    );
    guard.register(
      identity,
      () => container
          .read(taskEditorViewModelProvider(identity).notifier)
          .saveDescription(task, 'Retained draft'),
    );

    listener.close();
    await pumpEventQueue();

    expect(await guard.saveAll(), isTrue);
    expect(repository.descriptions, ['Retained draft']);
    guard.unregister(identity);
    expect(guard.hasRegisteredEditors, isFalse);
    expect(await guard.saveAll(), isTrue);
  });

  test(
    'one failing editor blocks navigation for all retained editors',
    () async {
      final guard = TaskDetailSaveGuard();
      var secondSaved = false;
      guard.register('first', () async => false);
      guard.register('second', () async {
        secondSaved = true;
        return true;
      });
      expect(await guard.saveAll(), isFalse);
      expect(secondSaved, isTrue);

      guard.unregister('first');
      expect(await guard.saveAll(), isTrue);
    },
  );
}

ProviderContainer _container({required _FakeTaskRepository repository}) =>
    ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repository),
        accountSessionProvider.overrideWith(
          (ref) => Stream.value((userId: null, generation: 0)),
        ),
      ],
    );

TaskItem _task(String id, {String? description}) => TaskItem(
  id: id,
  userId: 'user',
  content: id,
  description: description,
  projectId: 'inbox',
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeTaskRepository implements TaskRepository {
  bool failNextUpdate = false;
  final List<String> descriptions = [];

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) =>
      Result.capture(() async {
        if (failNextUpdate) {
          throw StateError('offline');
        }
        if (patch.updateDescription) {
          descriptions.add(patch.description ?? '');
        }
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
