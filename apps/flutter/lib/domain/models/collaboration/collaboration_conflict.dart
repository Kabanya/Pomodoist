import 'dart:convert';

/// A failed shared edit without persistence row details.
final class CollaborationConflict {
  const CollaborationConflict({
    required this.id,
    required this.scopeId,
    required this.type,
    required this.clientId,
    required this.lastError,
    required this.baseRevision,
  });
  final String id;
  final String scopeId;
  final String type;
  final String? clientId;
  final String? lastError;
  final int baseRevision;

  Map<String, dynamic>? get _detail {
    final value = lastError;
    if (value == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  String get entityType => _detail?['entityType']?.toString() ?? type;

  String get entityId => _detail?['entityId']?.toString() ?? clientId ?? '';

  /// The server revision the remote update carried when this command failed.
  int get serverRevision =>
      (_detail?['serverRevision'] as num?)?.toInt() ?? baseRevision;

  String get label => '$entityType · $entityId';
}
