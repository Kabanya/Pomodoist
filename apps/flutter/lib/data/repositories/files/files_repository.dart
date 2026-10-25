import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/files/files_service.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/repositories/files/files_repository_contract.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';

class FilesRepository implements FilesRepositoryContract {
  FilesRepository({
    required this.db,
    required this.service,
    required this.isSessionCurrent,
  });
  final AppDatabase db;
  final FilesService service;
  final bool Function() isSessionCurrent;
  final _uploads = <FileTarget, _Upload>{};
  final _changes = StreamController<void>.broadcast();
  var _disposed = false;
  void _checkSession() {
    if (_disposed || !isSessionCurrent()) {
      throw const FileFailure('session_changed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _uploads.clear();
    unawaited(_changes.close());
    service.dispose();
  }

  Future<Map<String, dynamic>> _target(FileTarget target) async {
    _checkSession();
    String? scope;
    if (target.taskId case final id?) {
      final task =
          await (db.select(db.tasks)
                ..where((r) => r.id.equals(id) & r.isDeleted.equals(false)))
              .getSingleOrNull();
      if (task == null) throw const FileFailure('not_found');
      scope = task.scopeId;
    } else {
      final project =
          await (db.select(db.projects)..where(
                (r) =>
                    r.id.equals(target.projectId!) & r.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (project == null) throw const FileFailure('not_found');
      scope = project.scopeId;
    }
    _checkSession();
    return {...target.toJson(), 'scopeId': ?scope};
  }

  @override
  Future<FileCapabilities> capabilities(FileTarget target) async {
    final result = await service.call('capabilities', await _target(target));
    _checkSession();
    return FileCapabilities.fromJson(result);
  }

  @override
  Stream<List<FileAttachment>> watch(FileTarget target) => db
      .customSelect(
        '''
    SELECT e.entity_id, e.data_json, t.content AS task_name
    FROM shared_entities e
    LEFT JOIN tasks t ON t.id = json_extract(e.data_json, '\$.taskId')
    LEFT JOIN projects p ON p.id = json_extract(e.data_json, '\$.projectId')
    WHERE e.entity_type = 'attachment' AND e.is_deleted = 0
      AND ((t.id IS NOT NULL AND t.is_deleted = 0 AND e.scope_id = COALESCE(t.scope_id, '_account'))
        OR (p.id IS NOT NULL AND p.is_deleted = 0 AND e.scope_id = COALESCE(p.scope_id, '_account')))
      AND ${target.taskId != null ? 't.id = ?' : '(p.id = ? OR t.project_id = ?)'}
    ORDER BY json_extract(e.data_json, '\$.createdAt') DESC, e.entity_id
  ''',
        variables: [
          Variable.withString(target.taskId ?? target.projectId!),
          if (target.taskId == null) Variable.withString(target.projectId!),
        ],
        readsFrom: {db.sharedEntities, db.tasks, db.projects},
      )
      .watch()
      .map((rows) {
        if (_disposed || !isSessionCurrent()) return [];
        return rows
            .map(
              (row) => FileAttachment.fromJson({
                ...jsonDecode(row.read<String>('data_json'))
                    as Map<String, dynamic>,
                'id': row.read<String>('entity_id'),
              }, taskName: row.readNullable<String>('task_name')),
            )
            .toList();
      });
  @override
  Stream<FileUploadState?> watchUpload(FileTarget target) async* {
    yield _uploads[target]?.state;
    await for (final _ in _changes.stream) {
      yield _uploads[target]?.state;
    }
  }

  @override
  Future<void> pickAndUpload(FileTarget target) async {
    _checkSession();
    final file = await service.pick();
    _checkSession();
    if (file != null) await upload(target, file);
  }

  Future<void> upload(FileTarget target, XFile file) async {
    _checkSession();
    if (_uploads[target]?.busy == true) return;
    final bytes = await file.length();
    if (bytes < 1 || bytes > 20000000) {
      throw const FileFailure('file_too_large');
    }
    final upload = _Upload(file, bytes, const Uuid().v4());
    _uploads[target] = upload;
    await _run(target, upload);
  }

  @override
  Future<void> retry(FileTarget target) async {
    final upload = _uploads[target];
    if (upload != null && !upload.busy) await _run(target, upload);
  }

  void _emit(
    _Upload upload, {
    double progress = 0,
    bool finishing = false,
    Object? error,
  }) {
    _checkSession();
    upload.state = FileUploadState(
      name: upload.file.name,
      progress: progress,
      finishing: finishing,
      error: error,
    );
    _changes.add(null);
  }

  Future<void> _run(FileTarget target, _Upload upload) async {
    _checkSession();
    upload.busy = true;
    try {
      _emit(upload);
      Map<String, dynamic>? result;
      if (upload.attempted && !upload.uploaded) {
        try {
          result = await service.call('finishUpload', {'uploadId': upload.id});
          _checkSession();
          upload.uploaded = true;
        } on FileFailure catch (error) {
          if (error.code != 'P0002' && error.code != 'upload_not_found') {
            rethrow;
          }
        }
      }
      if (!upload.uploaded) {
        final reservation = await service.call('reserveUpload', {
          ...await _target(target),
          'uploadId': upload.id,
          'name': upload.file.name,
          'contentType': service.contentType(upload.file),
          'bytes': upload.bytes,
        });
        _checkSession();
        if (reservation['finished'] != true) {
          upload.attempted = true;
          await service.upload(
            upload.file,
            Uri.parse(reservation['signedUrl'] as String),
            service.contentType(upload.file),
            upload.bytes,
            (progress) => _emit(upload, progress: progress),
          );
          _checkSession();
        }
        upload.uploaded = true;
      }
      _emit(upload, progress: 1, finishing: true);
      result ??= await service.call('finishUpload', {'uploadId': upload.id});
      _checkSession();
      final attachment = Map<String, dynamic>.from(result['attachment'] as Map);
      await db.transaction(() async {
        _checkSession();
        final scope = attachment['scopeId'] as String? ?? '_account';
        final revision = (attachment['serverRevision'] as num?)?.toInt() ?? 0;
        final existing =
            await (db.select(db.sharedEntities)..where(
                  (row) =>
                      row.entityType.equals('attachment') &
                      row.entityId.equals(attachment['id'] as String),
                ))
                .get();
        if (existing.any(
          (row) =>
              row.scopeId != scope ||
              row.serverRevision > revision ||
              row.serverRevision == revision && row.isDeleted,
        )) {
          return;
        }
        await db
            .into(db.sharedEntities)
            .insertOnConflictUpdate(
              SharedEntitiesCompanion.insert(
                scopeId: attachment['scopeId'] as String? ?? '_account',
                entityType: 'attachment',
                entityId: attachment['id'] as String,
                dataJson: jsonEncode(attachment),
                serverRevision: Value(revision),
              ),
            );
        _checkSession();
      });
      _uploads.remove(target);
      _changes.add(null);
    } catch (error) {
      if (!_disposed && isSessionCurrent()) {
        _emit(
          upload,
          progress: upload.uploaded ? 1 : 0,
          finishing: upload.uploaded,
          error: error,
        );
      }
      rethrow;
    } finally {
      upload.busy = false;
    }
  }

  @override
  Future<String> downloadUrl(
    String attachmentId, {
    bool preview = false,
  }) async {
    _checkSession();
    final response = await service.call('download', {
      'attachmentId': attachmentId,
      if (preview) 'preview': true,
    });
    _checkSession();
    return response['url'] as String;
  }

  @override
  Future<void> download(FileAttachment file) async {
    final url = await downloadUrl(file.id);
    _checkSession();
    await service.open(url);
  }

  @override
  Future<void> delete(FileAttachment file) async {
    _checkSession();
    await service.call('deleteAttachment', {'attachmentId': file.id});
    _checkSession();
    await db.transaction(() async {
      _checkSession();
      await (db.update(db.sharedEntities)..where(
            (r) =>
                r.entityType.equals('attachment') & r.entityId.equals(file.id),
          ))
          .write(const SharedEntitiesCompanion(isDeleted: Value(true)));
      _checkSession();
    });
  }
}

class _Upload {
  _Upload(this.file, this.bytes, this.id)
    : state = FileUploadState(name: file.name);
  final XFile file;
  final int bytes;
  final String id;
  bool uploaded = false, attempted = false, busy = false;
  FileUploadState state;
}
