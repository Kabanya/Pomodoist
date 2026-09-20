import 'dart:convert';

enum CollaborationRole {
  administrator,
  member,
  observer;

  static CollaborationRole parse(Object? value) => switch (value) {
    'administrator' => CollaborationRole.administrator,
    'member' => CollaborationRole.member,
    'observer' => CollaborationRole.observer,
    _ => throw const CollaborationException(
      'invalid_response',
      'Unknown collaboration role.',
    ),
  };

  bool get canEdit => this != CollaborationRole.observer;

  bool get canManage => this == CollaborationRole.administrator;
}

class CollaborationMember {
  const CollaborationMember({
    required this.userId,
    required this.role,
    this.displayName,
  });

  factory CollaborationMember.fromJson(Map<String, dynamic> data) {
    final userId = data['userId'];
    if (userId is! String || userId.isEmpty) {
      throw const CollaborationException(
        'invalid_response',
        'A collaboration member is missing its user id.',
      );
    }
    final name = data['displayName'];
    return CollaborationMember(
      userId: userId,
      role: CollaborationRole.parse(data['role']),
      displayName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : null,
    );
  }

  final String userId;
  final CollaborationRole role;
  final String? displayName;
}

class SharedScope {
  SharedScope.fromJson(Map<String, dynamic> data)
    : data = _immutableJson(data) as Map<String, dynamic>,
      role = _parseRole(data['role']),
      members = _parseMembers(data['members']);
  final Map<String, dynamic> data;
  final CollaborationRole role;
  final List<CollaborationMember> members;
  String get id => data['id'] as String;
  String get rootProjectId => data['rootProjectId'] as String;
  String get ownerId => data['ownerId'] as String;
  bool get canEdit => role.canEdit;
  bool get canManage => role.canManage;
  bool canDeleteRoot(String? userId) => canManage && ownerId == userId;
  bool get historyUnlimited => data['historyUnlimited'] == true;
  String? get publicToken => data['publicToken'] as String?;
  DateTime? get graceEndsAt =>
      DateTime.tryParse(data['graceEndsAt'] as String? ?? '');
  DateTime? historyCutoff(DateTime now) =>
      historyUnlimited || (graceEndsAt?.isAfter(now.toUtc()) ?? false)
      ? null
      : now.toUtc().subtract(const Duration(days: 365));
}

CollaborationRole _parseRole(Object? value) =>
    value == null ? CollaborationRole.observer : CollaborationRole.parse(value);

List<CollaborationMember> _parseMembers(Object? value) => List.unmodifiable([
  if (value is List)
    for (final item in value)
      if (item is Map)
        CollaborationMember.fromJson(Map<String, dynamic>.from(item)),
]);

List<Map<String, dynamic>> collaborationMaps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];

List<String> collaborationIds(String json) =>
    (jsonDecode(json) as List).whereType<String>().toList();

class CollaborationException implements Exception {
  const CollaborationException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => message ?? code;
}

Object? _immutableJson(Object? value) => switch (value) {
  Map value => Map<String, dynamic>.unmodifiable({
    for (final entry in value.entries)
      entry.key as String: _immutableJson(entry.value),
  }),
  List value => List<Object?>.unmodifiable(value.map(_immutableJson)),
  _ => value,
};
