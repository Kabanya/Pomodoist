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

  String get label {
    final Object? value;
    try {
      value = lastError == null ? null : jsonDecode(lastError!);
    } on FormatException {
      return '$type · ${clientId ?? ''}';
    }
    final conflict = value is Map ? value : null;
    return '${conflict?['entityType'] ?? type} · ${conflict?['entityId'] ?? clientId ?? ''}';
  }
}
