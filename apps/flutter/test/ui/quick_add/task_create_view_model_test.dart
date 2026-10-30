import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/files/files_repository_contract.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/ui/tasks/view_models/task_create_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/task_description_field.dart';
import 'package:flutter/services.dart';

class _Files implements FilesRepositoryContract {
  final picks = <XFile>[];
  final uploads = <String>[];
  int retries = 0;
  bool fail = false;
  bool reserveBeforeFailure = true;
  FileUploadState? pending;
  @override
  Future<XFile?> pickFile() async => picks.removeAt(0);
  @override
  Stream<FileUploadState?> watchUpload(FileTarget target) =>
      Stream.value(pending);
  @override
  Future<void> upload(FileTarget target, XFile file) async {
    uploads.add(file.name);
    if (fail) {
      pending = reserveBeforeFailure ? FileUploadState(name: file.name) : null;
      throw const FileFailure('upload_failed');
    }
    pending = null;
  }

  @override
  Future<void> retry(FileTarget target) async {
    retries++;
    if (fail) throw const FileFailure('upload_failed');
    pending = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RejectAssignment extends DriftOutboxService {
  _RejectAssignment(super.db);
  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) {
    if (type == 'task.assign') throw StateError('Assignment queue unavailable');
    return super.enqueue(
      type: type,
      payload: payload,
      clientId: clientId,
      availableAt: availableAt,
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late TaskCreateViewModel model;
  late _Files files;
  late DriftTaskRepository tasks;
  late QuickAddUseCase service;
  late String projectId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    final outbox = DriftOutboxService(db);
    final projects = DriftProjectRepository(db, outbox);
    projectId = (await projects.createProject('Team')).getOrThrow();
    await (db.update(db.projects)..where((r) => r.id.equals(projectId))).write(
      const ProjectsCompanion(scopeId: Value('team')),
    );
    await db
        .into(db.sharedScopes)
        .insert(
          SharedScopesCompanion.insert(
            id: 'team',
            dataJson: jsonEncode({
              'id': 'team',
              'rootProjectId': projectId,
              'ownerId': 'owner',
              'role': 'administrator',
              'members': [
                {'userId': 'anna', 'role': 'administrator'},
                {'userId': 'mike', 'role': 'member'},
                {'userId': 'reader', 'role': 'observer'},
              ],
            }),
          ),
        );
    await db.delete(db.syncCommands).go();
    tasks = DriftTaskRepository(db, outbox);
    service = QuickAddUseCase(
      parser: const QuickAddParser(),
      taskRepository: tasks,
      projectRepository: projects,
    );
    files = _Files();
    container = ProviderContainer(
      overrides: [
        quickAddUseCaseProvider.overrideWithValue(service),
        filesRepositoryProvider.overrideWithValue(files),
      ],
    );
    final provider = taskCreateViewModelProvider(Object());
    container.listen(provider, (_, _) {});
    model = container.read(provider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pick(String name) async {
    files.picks.add(
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name, path: name),
    );
    await model.pickFile();
  }

  test(
    'title project tokens resolve the correct team and new-project caption',
    () async {
      final now = DateTime.utc(2026);
      final contextContainer = ProviderContainer(
        overrides: [
          quickAddParserProvider.overrideWithValue(const QuickAddParser()),
          projectsProvider.overrideWith(
            (ref) => Stream.value([
              ProjectItem(
                id: projectId,
                userId: 'owner',
                name: 'Team',
                scopeId: 'team',
                orderKey: '1',
                createdAt: now,
                updatedAt: now,
              ),
            ]),
          ),
          sharedScopesProvider.overrideWith(
            (ref) => Stream.value([
              SharedScope.fromJson({
                'id': 'team',
                'rootProjectId': projectId,
                'ownerId': 'owner',
                'role': 'administrator',
              }),
            ]),
          ),
        ],
      );
      addTearDown(contextContainer.dispose);
      final query = taskCreateContextViewModelProvider((
        text: 'Ship #Team',
        projectId: null,
        defaultDate: null,
      ));
      contextContainer.listen(query, (_, _) {});
      await pumpEventQueue();
      final target = contextContainer.read(query);
      expect(target.ready, isTrue);
      expect(target.project!.id, projectId);
      expect(target.scope!.id, 'team');
      final personal = contextContainer.read(
        taskCreateContextViewModelProvider((
          text: 'Ship #Fresh',
          projectId: projectId,
          defaultDate: null,
        )),
      );
      expect(personal.project, isNull);
      expect(personal.scope, isNull);
      expect(personal.projectName, 'Fresh');
    },
  );

  test(
    'creation writes multiple assignees and ordered sync commands atomically',
    () async {
      model.setAssignees('team', {'mike', 'anna'});
      final id = await model.submit(
        text: 'Ship tomorrow p1',
        description: 'Keep this\n- Check sync',
        projectId: projectId,
        scopeId: 'team',
      );
      expect(id, isNotNull);
      final task = (await db.select(db.tasks).get()).single;
      expect(jsonDecode(task.assigneeIdsJson), ['anna', 'mike']);
      expect(task.description, 'Keep this\n- Check sync');
      final commands = await (db.select(
        db.syncCommands,
      )..orderBy([(r) => OrderingTerm.asc(r.rowId)])).get();
      expect(
        commands.indexWhere((c) => c.type == 'task.create'),
        lessThan(commands.indexWhere((c) => c.type == 'task.assign')),
      );
      final assign = commands.singleWhere((c) => c.type == 'task.assign');
      expect(jsonDecode(assign.payloadJson)['add'], ['anna', 'mike']);
    },
  );

  test(
    'observers and users outside the scope cannot be assigned on creation',
    () async {
      for (final id in ['reader', 'outsider']) {
        final result = await tasks.createTask(
          CreateTaskInput(
            content: 'Private',
            projectId: projectId,
            assigneeIds: [id],
          ),
        );
        expect(result, isA<Failure<String>>());
        expect(await db.select(db.tasks).get(), isEmpty);
        expect(await db.select(db.syncCommands).get(), isEmpty);
      }
      final personal = await tasks.createTask(
        CreateTaskInput(content: 'Personal', assigneeIds: ['anna']),
      );
      expect(personal, isA<Failure<String>>());
    },
  );

  test(
    'assignment failure rolls back both task and preceding commands',
    () async {
      final repository = DriftTaskRepository(db, _RejectAssignment(db));
      final result = await repository.createTask(
        CreateTaskInput(
          content: 'Ship',
          projectId: projectId,
          assigneeIds: ['anna'],
        ),
      );
      expect(result, isA<Failure<String>>());
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.syncCommands).get(), isEmpty);
    },
  );

  test('changing to a personal project drops stale team assignments', () async {
    model.setAssignees('team', {'anna'});
    final id = await model.submit(text: 'Personal', description: 'Draft');
    expect(id, isNotNull);
    expect((await db.select(db.tasks).get()).single.assigneeIdsJson, '[]');
  });

  test(
    'upload failure retains the task identity and retries without duplicating it',
    () async {
      await pick('notes.md');
      await pick('sketch.png');
      files.fail = true;
      expect(await model.submit(text: 'Ship', description: 'Draft'), isNull);
      final id = model.state.taskId;
      expect(id, isNotNull);
      expect(model.state.files, hasLength(2));
      expect(model.state.error, isA<FileFailure>());
      files.fail = false;
      expect(await model.submit(text: 'Ship', description: 'Draft'), id);
      expect(files.retries, 1);
      expect(files.uploads, ['notes.md', 'sketch.png']);
      expect(await db.select(db.tasks).get(), hasLength(1));
      expect(model.state.files, isEmpty);
    },
  );

  test(
    'failure before reservation retries an upload instead of silently skipping the file',
    () async {
      await pick('notes.md');
      files
        ..fail = true
        ..reserveBeforeFailure = false;
      expect(await model.submit(text: 'Ship', description: ''), isNull);
      files.fail = false;
      expect(await model.submit(text: 'Ship', description: ''), isNotNull);
      expect(files.uploads, ['notes.md', 'notes.md']);
      expect(files.retries, 0);
    },
  );

  test(
    'a pending file can be removed after failure to finish the saved task',
    () async {
      await pick('notes.md');
      files.fail = true;
      await model.submit(text: 'Ship', description: 'Draft');
      final id = model.state.taskId;
      model.removeFile(model.state.files.single);
      expect(await model.submit(text: 'Ship', description: 'Draft'), id);
      expect(await db.select(db.tasks).get(), hasLength(1));
    },
  );

  test('formatting retains surrounding text and a usable selection', () {
    final value = const TextEditingValue(
      text: 'Check sync today',
      selection: TextSelection(baseOffset: 6, extentOffset: 10),
    );
    final bold = formatTaskDescription(value, '**', '**');
    expect(bold.text, 'Check **sync** today');
    expect(bold.selection.textInside(bold.text), 'sync');
    final list = formatTaskDescription(
      const TextEditingValue(
        text: 'First\nSecond',
        selection: TextSelection(baseOffset: 0, extentOffset: 12),
      ),
      '- ',
      '',
    );
    expect(list.text, '- First\n- Second');
  });
}
