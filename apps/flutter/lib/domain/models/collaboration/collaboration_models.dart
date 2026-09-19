import 'dart:convert';

class SharedScope {
  SharedScope.fromJson(Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get rootProjectId => data['rootProjectId'] as String;
  String get ownerId => data['ownerId'] as String;
  String get role => data['role'] as String? ?? 'observer';
  bool get canEdit => role == 'administrator' || role == 'member';
  bool get canManage => role == 'administrator';
  bool canDeleteRoot(String? userId) => canManage && ownerId == userId;
  bool get historyUnlimited => data['historyUnlimited'] == true;
  String? get publicToken => data['publicToken'] as String?;
  DateTime? get graceEndsAt =>
      DateTime.tryParse(data['graceEndsAt'] as String? ?? '');
  DateTime? historyCutoff(DateTime now) =>
      historyUnlimited || (graceEndsAt?.isAfter(now.toUtc()) ?? false)
      ? null
      : now.toUtc().subtract(const Duration(days: 365));
  List<Map<String, dynamic>> get members => collaborationMaps(data['members']);
}

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
