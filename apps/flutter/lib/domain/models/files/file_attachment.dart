typedef FilePreviewKey = ({String? scopeId, String attachmentId});

class FileTarget {
  const FileTarget({this.projectId, this.taskId})
    : assert((projectId == null) != (taskId == null));
  final String? projectId;
  final String? taskId;
  Map<String, dynamic> toJson() => {
    if (projectId != null) 'projectId': projectId,
    if (taskId != null) 'taskId': taskId,
  };
  @override
  bool operator ==(Object other) =>
      other is FileTarget &&
      other.projectId == projectId &&
      other.taskId == taskId;
  @override
  int get hashCode => Object.hash(projectId, taskId);
}

class FileAttachment {
  const FileAttachment({
    required this.id,
    this.scopeId,
    this.taskId,
    this.projectId,
    required this.name,
    required this.contentType,
    required this.bytes,
    required this.createdAt,
    required this.authorName,
    required this.createdBy,
    this.taskName,
  });
  factory FileAttachment.fromJson(
    Map<String, dynamic> json, {
    String? taskName,
  }) => FileAttachment(
    id: json['id'] as String,
    scopeId: json['scopeId'] as String?,
    taskId: json['taskId'] as String?,
    projectId: json['projectId'] as String?,
    name: json['name'] as String,
    contentType: json['contentType'] as String? ?? 'application/octet-stream',
    bytes: (json['bytes'] as num).toInt(),
    createdAt: json['createdAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt(),
            isUtc: true,
          )
        : DateTime.parse(json['createdAt'] as String),
    authorName: json['authorName'] as String? ?? '',
    createdBy: json['createdBy'] as String? ?? '',
    taskName: taskName,
  );
  final String id, name, contentType, authorName, createdBy;
  final String? scopeId, taskId, projectId, taskName;
  final int bytes;
  final DateTime createdAt;
  FilePreviewKey get previewKey => (scopeId: scopeId, attachmentId: id);
  bool get isImage => const {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/avif',
  }.contains(contentType);
  bool get isDocument =>
      contentType == 'application/pdf' ||
      contentType.startsWith('text/') ||
      contentType.contains('document') ||
      contentType.contains('sheet') ||
      contentType.contains('presentation');
}

class FileCapabilities {
  FileCapabilities.fromJson(Map<String, dynamic> json)
    : canUpload = json['canUpload'] == true,
      canDelete = json['canDelete'] == true,
      reason = json['reason'] as String?,
      maxFileBytes = (json['maxFileBytes'] as num?)?.toInt() ?? 20000000,
      monthlyLimitBytes =
          (json['monthlyLimitBytes'] as num?)?.toInt() ?? 1000000000,
      yearlyLimitBytes =
          (json['yearlyLimitBytes'] as num?)?.toInt() ?? 5000000000,
      monthlyUsedBytes = (json['monthlyUsedBytes'] as num?)?.toInt() ?? 0,
      yearlyUsedBytes = (json['yearlyUsedBytes'] as num?)?.toInt() ?? 0,
      reservedBytes = (json['reservedBytes'] as num?)?.toInt() ?? 0;
  final bool canUpload, canDelete;
  final String? reason;
  final int maxFileBytes,
      monthlyLimitBytes,
      yearlyLimitBytes,
      monthlyUsedBytes,
      yearlyUsedBytes,
      reservedBytes;
}

class FileFailure implements Exception {
  const FileFailure(this.code);
  final String code;
}

class FileUploadState {
  const FileUploadState({
    required this.name,
    this.progress = 0,
    this.finishing = false,
    this.error,
  });
  final String name;
  final double progress;
  final bool finishing;
  final Object? error;
}
