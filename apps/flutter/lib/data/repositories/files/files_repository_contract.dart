import 'dart:async';

import 'package:pomodoist/domain/models/files/file_attachment.dart';

abstract interface class FilesRepositoryContract {
  Future<FileCapabilities> capabilities(FileTarget target);
  Stream<List<FileAttachment>> watch(FileTarget target);
  Stream<FileUploadState?> watchUpload(FileTarget target);
  Future<void> pickAndUpload(FileTarget target);
  Future<void> retry(FileTarget target);
  Future<String> downloadUrl(String attachmentId, {bool preview = false});
  Future<void> download(FileAttachment file);
  Future<void> delete(FileAttachment file);
  void dispose();
}
