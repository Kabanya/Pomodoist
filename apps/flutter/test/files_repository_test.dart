import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/data/repositories/files/file_view_preferences_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/files/files_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/files/files_service.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/files/view_models/files_view_model.dart';

Map<String, dynamic> attachment(
  String id, {
  String? taskId,
  String? projectId,
  String? scopeId,
  String type = 'application/pdf',
  int day = 1,
}) => {
  'id': id,
  'taskId': taskId,
  'projectId': projectId,
  'scopeId': scopeId,
  'name': '$id.pdf',
  'contentType': type,
  'bytes': 12,
  'createdAt': '2026-09-${day.toString().padLeft(2, '0')}T12:00:00Z',
  'createdBy': 'actor',
  'authorName': 'Author',
};

class _Service extends FilesService {
  _Service(Future<Map<String, dynamic>> Function(Map<String, dynamic>) invoke)
    : super(invoke: invoke);
  int puts = 0;
  bool failPut = false;
  @override
  Future<void> upload(
    XFile file,
    Uri url,
    String contentType,
    int size,
    void Function(double) progress,
  ) async {
    puts++;
    progress(1);
    if (failPut) {
      failPut = false;
      throw const FileFailure('network');
    }
  }
}

class _ViewPreferences extends FileViewPreferencesRepository {
  _ViewPreferences() : super(PreferencesService(() async => null));
  final firstSave = Completer<void>();
  final writes = <FileViewState>[];
  @override
  Future<FileViewState> load(String projectId) async =>
      (gallery: false, byTask: false);
  @override
  Future<void> save(
    String projectId, {
    required bool gallery,
    required bool byTask,
  }) async {
    writes.add((gallery: gallery, byTask: byTask));
    if (writes.length == 1) await firstSave.future;
  }
}

void main() {
  late AppDatabase db;
  late String project, task, childProject;
  late _Service service;
  late FilesRepository repository;
  late bool current;
  late List<Map<String, dynamic>> calls;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) invoke;
  const now = '2026-09-01T12:00:00Z';
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    final queue = DriftOutboxService(db);
    final projects = DriftProjectRepository(db, queue);
    project = (await projects.createProject('Root')).getOrThrow();
    childProject = (await projects.createProject(
      'Child',
      parentId: project,
    )).getOrThrow();
    task = (await DriftTaskRepository(db, queue).createTask(
      CreateTaskInput(content: 'Completed task', projectId: project),
    )).getOrThrow();
    await (db.update(db.tasks)..where((r) => r.id.equals(task))).write(
      const TasksCompanion(status: Value('completed')),
    );
    current = true;
    calls = [];
    invoke = (body) async => switch (body['action']) {
      'reserveUpload' => {
        'uploadId': body['uploadId'],
        'signedUrl': 'https://storage.example/upload',
        'finished': false,
      },
      'finishUpload' => {
        'attachment': attachment('uploaded', projectId: project),
      },
      'capabilities' => {
        'canUpload': false,
        'canDelete': true,
        'reason': 'pro_required',
      },
      'download' => {'url': 'https://storage.example/download'},
      'deleteAttachment' => {'ok': true},
      _ => throw StateError('unknown action'),
    };
    service = _Service((body) {
      calls.add(body);
      return invoke(body);
    });
    repository = FilesRepository(
      db: db,
      service: service,
      isSessionCurrent: () => current,
    );
  });
  tearDown(() async {
    repository.dispose();
    await db.close();
  });
  Future<void> cache(Map<String, dynamic> data) async => db
      .into(db.sharedEntities)
      .insert(
        SharedEntitiesCompanion.insert(
          scopeId: data['scopeId'] as String? ?? '_account',
          entityType: 'attachment',
          entityId: data['id'] as String,
          dataJson: jsonEncode(data),
        ),
      );
  test(
    'project cache includes completed tasks and direct files but no descendants; task moves follow current project',
    () async {
      await cache(attachment('direct', projectId: project));
      await cache(attachment('task', taskId: task));
      await cache(attachment('child', projectId: childProject));
      final target = FileTarget(projectId: project);
      expect((await repository.watch(target).first).map((f) => f.id), [
        'direct',
        'task',
      ]);
      await (db.update(db.tasks)..where((r) => r.id.equals(task))).write(
        TasksCompanion(projectId: Value(childProject)),
      );
      expect((await repository.watch(target).first).map((f) => f.id), [
        'direct',
      ]);
      expect(
        (await repository.watch(FileTarget(projectId: childProject)).first).map(
          (f) => f.id,
        ),
        ['child', 'task'],
      );
      expect(
        (await repository.watch(FileTarget(taskId: task)).first)
            .single
            .taskName,
        'Completed task',
      );
    },
  );
  test(
    'successful upload reserves once, uploads bytes and stores returned canonical metadata',
    () async {
      await repository.upload(
        FileTarget(projectId: project),
        XFile.fromData(
          Uint8List.fromList([1, 2]),
          name: 'test.png',
          path: 'test.png',
        ),
      );
      expect(calls.map((c) => c['action']), ['reserveUpload', 'finishUpload']);
      expect(calls.first['projectId'], project);
      expect(calls.first['contentType'], 'image/png');
      expect(service.puts, 1);
      expect(
        (await repository.watch(FileTarget(projectId: project)).first)
            .single
            .id,
        'uploaded',
      );
    },
  );
  test('finish retry never uploads the same bytes twice', () async {
    final initial = invoke;
    var fail = true;
    invoke = (body) async {
      if (body['action'] == 'finishUpload' && fail) {
        fail = false;
        throw const FileFailure('offline');
      }
      return initial(body);
    };
    final target = FileTarget(projectId: project);
    await expectLater(
      repository.upload(
        target,
        XFile.fromData(Uint8List.fromList([1]), name: 'a.pdf'),
      ),
      throwsA(isA<FileFailure>()),
    );
    expect((await repository.watchUpload(target).first)?.finishing, true);
    await repository.retry(target);
    expect(service.puts, 1);
    expect(calls.where((c) => c['action'] == 'reserveUpload').length, 1);
    expect(calls.where((c) => c['action'] == 'finishUpload').length, 2);
  });
  test(
    'lost PUT response retries finish before considering another upload',
    () async {
      service.failPut = true;
      final target = FileTarget(projectId: project);
      await expectLater(
        repository.upload(
          target,
          XFile.fromData(Uint8List.fromList([1]), name: 'a.pdf'),
        ),
        throwsA(isA<FileFailure>()),
      );
      await repository.retry(target);
      expect(service.puts, 1);
      expect(calls.map((c) => c['action']), ['reserveUpload', 'finishUpload']);
    },
  );
  test(
    'late finish does not overwrite newer metadata or resurrect a tombstone',
    () async {
      final initial = invoke;
      invoke = (body) async {
        if (body['action'] == 'finishUpload') {
          await db
              .into(db.sharedEntities)
              .insert(
                SharedEntitiesCompanion.insert(
                  scopeId: '_account',
                  entityType: 'attachment',
                  entityId: 'uploaded',
                  dataJson: jsonEncode(
                    attachment('uploaded', projectId: project),
                  ),
                  serverRevision: const Value(10),
                  isDeleted: const Value(true),
                ),
              );
          return {
            'attachment': {
              ...attachment('uploaded', projectId: project),
              'serverRevision': 10,
            },
          };
        }
        return initial(body);
      };
      await repository.upload(
        FileTarget(projectId: project),
        XFile.fromData(Uint8List.fromList([1]), name: 'a.pdf'),
      );
      final row = await db.select(db.sharedEntities).getSingle();
      expect(row.isDeleted, true);
      expect(row.serverRevision, 10);
      expect(
        await repository.watch(FileTarget(projectId: project)).first,
        isEmpty,
      );
    },
  );
  test('missing object after a failed PUT permits a new signed PUT', () async {
    service.failPut = true;
    final initial = invoke;
    var absent = true;
    invoke = (body) async {
      if (body['action'] == 'finishUpload' && absent) {
        absent = false;
        throw const FileFailure('P0002');
      }
      return initial(body);
    };
    final target = FileTarget(projectId: project);
    await expectLater(
      repository.upload(
        target,
        XFile.fromData(Uint8List.fromList([1]), name: 'a.pdf'),
      ),
      throwsA(isA<FileFailure>()),
    );
    await repository.retry(target);
    expect(service.puts, 2);
    expect(calls.map((c) => c['action']), [
      'reserveUpload',
      'finishUpload',
      'reserveUpload',
      'finishUpload',
    ]);
  });
  test(
    'late delete after signout leaves local state for account cleanup',
    () async {
      await cache(attachment('kept', projectId: project));
      invoke = (_) async {
        current = false;
        return {'ok': true};
      };
      await expectLater(
        repository.delete(
          FileAttachment.fromJson(attachment('kept', projectId: project)),
        ),
        throwsA(isA<FileFailure>()),
      );
      expect((await db.select(db.sharedEntities).getSingle()).isDeleted, false);
    },
  );
  test('signed upload transport sends bytes, MIME and immutable PUT', () async {
    final transport = FilesService(
      invoke: (_) async => {},
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.bodyBytes, [1, 2, 3]);
        expect(request.headers['content-type'], 'image/png');
        expect(request.headers['x-upsert'], 'false');
        return http.Response('', 200);
      }),
    );
    final progress = <double>[];
    await transport.upload(
      XFile.fromData(Uint8List.fromList([1, 2, 3])),
      Uri.parse('https://storage.example/upload'),
      'image/png',
      3,
      progress.add,
    );
    expect(progress.last, 1);
    transport.dispose();
  });
  test(
    'transport consumes an immediate HTTP failure without waiting for stream close',
    () async {
      final transport = FilesService(
        invoke: (_) async => {},
        client: MockClient.streaming(
          (_, _) async => throw http.ClientException('offline'),
        ),
      );
      await expectLater(
        transport
            .upload(
              XFile.fromData(Uint8List.fromList([1])),
              Uri.parse('https://storage.example/upload'),
              'application/octet-stream',
              1,
              (_) {},
            )
            .timeout(const Duration(seconds: 2)),
        throwsA(isA<http.ClientException>()),
      );
      transport.dispose();
    },
  );
  test('late finish after session changes cannot write metadata', () async {
    final initial = invoke;
    final pending = Completer<Map<String, dynamic>>();
    final finishing = Completer<void>();
    invoke = (body) {
      if (body['action'] == 'finishUpload') {
        finishing.complete();
        return pending.future;
      }
      return initial(body);
    };
    final upload = repository.upload(
      FileTarget(projectId: project),
      XFile.fromData(Uint8List.fromList([1]), name: 'a.pdf'),
    );
    final assertion = expectLater(upload, throwsA(isA<FileFailure>()));
    await finishing.future;
    current = false;
    pending.complete({'attachment': attachment('late', projectId: project)});
    await assertion;
    expect(await db.select(db.sharedEntities).get(), isEmpty);
  });
  test('revoked scope metadata is hidden when target changes scope', () async {
    await cache(attachment('old', taskId: task, scopeId: 'scope-a'));
    expect(await repository.watch(FileTarget(taskId: task)).first, isEmpty);
    await (db.update(db.tasks)..where((r) => r.id.equals(task))).write(
      const TasksCompanion(scopeId: Value('scope-a')),
    );
    expect(
      (await repository.watch(FileTarget(taskId: task)).first).single.id,
      'old',
    );
  });
  test(
    'server capabilities preserve read access after Pro loss and SVG is excluded from image previews',
    () async {
      final capabilities = await repository.capabilities(
        FileTarget(projectId: project),
      );
      expect(capabilities.canUpload, false);
      expect(capabilities.canDelete, true);
      final file = FileAttachment.fromJson(
        attachment('svg', projectId: project, type: 'image/svg+xml'),
      );
      expect(file.isImage, false);
      await repository.downloadUrl(file.id);
      expect(calls.last.containsKey('preview'), false);
    },
  );
  test(
    'preview URLs use the attachment ID and ordinary downloads omit preview',
    () async {
      expect(
        await repository.downloadUrl('image-id', preview: true),
        'https://storage.example/download',
      );
      expect(calls.single, {
        'action': 'download',
        'attachmentId': 'image-id',
        'preview': true,
      });
      await repository.downloadUrl('document-id');
      expect(calls.last, {'action': 'download', 'attachmentId': 'document-id'});
    },
  );
  test(
    'oversize rejected before reservation; delete failure retains metadata',
    () async {
      await expectLater(
        repository.upload(
          FileTarget(projectId: project),
          XFile.fromData(Uint8List(20000001), name: 'big.bin'),
        ),
        throwsA(isA<FileFailure>()),
      );
      expect(calls, isEmpty);
      await cache(attachment('kept', projectId: project));
      invoke = (_) async => throw const FileFailure('forbidden');
      await expectLater(
        repository.delete(
          FileAttachment.fromJson(attachment('kept', projectId: project)),
        ),
        throwsA(isA<FileFailure>()),
      );
      expect((await db.select(db.sharedEntities).get()).length, 1);
    },
  );
  test(
    'projection sorts newest first, direct group first, type and task text filters',
    () {
      final files = [
        FileAttachment.fromJson(
          attachment('old', taskId: 't', day: 1),
          taskName: 'Launch',
        ),
        FileAttachment.fromJson(attachment('direct', projectId: 'p', day: 2)),
        FileAttachment.fromJson(
          attachment('new', taskId: 't', type: 'image/png', day: 3),
          taskName: 'Launch',
        ),
      ];
      expect(projectFileGroups(files).single.files.map((f) => f.id), [
        'new',
        'direct',
        'old',
      ]);
      expect(projectFileGroups(files, byTask: true).map((g) => g.taskId), [
        null,
        't',
      ]);
      expect(
        projectFileGroups(
          files,
          search: 'launch',
          type: FileTypeFilter.images,
        ).single.files.single.id,
        'new',
      );
      expect(
        FileAttachment.fromJson({
          ...attachment('time'),
          'createdAt': DateTime.parse(now).millisecondsSinceEpoch,
        }).createdAt,
        DateTime.parse(now),
      );
    },
  );
  test(
    'rapid view and grouping changes preserve both fields and serialize saves',
    () async {
      final preferences = _ViewPreferences();
      final container = ProviderContainer(
        overrides: [
          fileViewPreferencesRepositoryProvider.overrideWithValue(preferences),
        ],
      );
      final provider = filesViewModelProvider(FileTarget(projectId: project));
      final subscription = container.listen(provider, (_, _) {});
      final model = container.read(provider.notifier);
      final gallery = model.setView(gallery: true);
      final grouping = model.setView(byTask: true);
      expect(container.read(provider), (gallery: true, byTask: true));
      await Future<void>.delayed(Duration.zero);
      expect(preferences.writes, [(gallery: true, byTask: false)]);
      preferences.firstSave.complete();
      await Future.wait([gallery, grouping]);
      expect(preferences.writes.last, (gallery: true, byTask: true));
      subscription.close();
      container.dispose();
    },
  );
}
