import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

Never _malformed(String field) => throw CollaborationException(
  'invalid_response',
  'Malformed collaboration response: $field',
);

String _requiredId(Object? value, String field) {
  if (value is! String || value.isEmpty) _malformed(field);
  return value;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _time(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

final class CollaborationInvitation {
  CollaborationInvitation({
    required this.id,
    required this.role,
    this.scopeId,
    this.email,
    this.token,
    this.expiresAt,
    this.revokedAt,
    this.acceptedAt,
  });

  factory CollaborationInvitation.fromJson(Map<String, dynamic> data) =>
      CollaborationInvitation(
        id: _requiredId(data['id'], 'invitation.id'),
        role: CollaborationRole.parse(data['role']),
        scopeId: _text(data['scopeId']),
        email: _text(data['email']),
        token: _text(data['token']),
        expiresAt: _time(data['expiresAt']),
        revokedAt: _time(data['revokedAt']),
        acceptedAt: _time(data['acceptedAt']),
      );

  final String id;
  final CollaborationRole role;
  final String? scopeId;
  final String? email;
  final String? token;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime? acceptedAt;

  bool isPending(DateTime now) =>
      revokedAt == null &&
      acceptedAt == null &&
      expiresAt != null &&
      expiresAt!.isAfter(now);
}

final class CollaborationNotification {
  CollaborationNotification({
    required this.id,
    required this.kind,
    this.scopeId,
    this.createdAt,
    this.readAt,
  });

  factory CollaborationNotification.fromJson(Map<String, dynamic> data) =>
      CollaborationNotification(
        id: _requiredId(data['id'], 'notification.id'),
        kind: _text(data['kind']) ?? '',
        scopeId: _text(data['scopeId']),
        createdAt: _time(data['createdAt']),
        readAt: _time(data['readAt']),
      );

  final String id;
  final String kind;
  final String? scopeId;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
}

final class CollaborationComment {
  CollaborationComment({
    required this.id,
    required this.scopeId,
    required this.taskId,
    required this.body,
    this.createdBy,
    this.createdAt,
  });

  factory CollaborationComment.fromJson(Map<String, dynamic> data) =>
      CollaborationComment(
        id: _requiredId(data['id'], 'comment.id'),
        scopeId: _text(data['scopeId']) ?? '',
        taskId: _text(data['taskId']) ?? '',
        body: data['body'] is String
            ? data['body'] as String
            : _malformed('comment.body'),
        createdBy: _text(data['createdBy']),
        createdAt: _time(data['createdAt']),
      );

  final String id;
  final String scopeId;
  final String taskId;
  final String body;
  final String? createdBy;
  final DateTime? createdAt;
}

final class CollaborationFocusContribution {
  CollaborationFocusContribution({
    required this.id,
    required this.type,
    required this.status,
    required this.authorId,
    required this.seconds,
    this.startedAt,
  });

  factory CollaborationFocusContribution.fromJson(Map<String, dynamic> data) =>
      CollaborationFocusContribution(
        id: _requiredId(data['id'], 'focus.id'),
        type: _text(data['type']) ?? 'work',
        status: _text(data['status']) ?? 'completed',
        authorId: (_text(data['createdBy']) ?? _text(data['userId'])) ?? '',
        seconds:
            (data['durationSeconds'] as num?)?.toInt() ??
            (data['plannedSeconds'] as num?)?.toInt() ??
            0,
        startedAt: switch (data['startedAt']) {
          final String text => DateTime.tryParse(text)?.toUtc(),
          final num milliseconds => DateTime.fromMillisecondsSinceEpoch(
            milliseconds.toInt(),
            isUtc: true,
          ),
          _ => null,
        },
      );

  final String id;
  final String type;
  final String status;
  final String authorId;
  final int seconds;
  final DateTime? startedAt;
}

final class CollaborationMembers {
  CollaborationMembers({
    required List<CollaborationMember> members,
    required List<CollaborationInvitation> invitations,
  }) : members = List.unmodifiable(members),
       invitations = List.unmodifiable(invitations);

  factory CollaborationMembers.fromJson(Map<String, dynamic> data) {
    final byUserId = <String, CollaborationMember>{};
    for (final row in collaborationMaps(data['members'])) {
      final member = CollaborationMember.fromJson(row);
      if (byUserId.containsKey(member.userId)) {
        _malformed('duplicate member ${member.userId}');
      }
      byUserId[member.userId] = member;
    }
    return CollaborationMembers(
      members: byUserId.values.toList(growable: false),
      invitations: [
        for (final row in collaborationMaps(data['invitations']))
          CollaborationInvitation.fromJson(row),
      ],
    );
  }

  final List<CollaborationMember> members;
  final List<CollaborationInvitation> invitations;
}

final class CollaborationState {
  CollaborationState({
    required List<CollaborationInvitation> invitations,
    required List<CollaborationNotification> notifications,
    this.personalRevision = 0,
  }) : invitations = List.unmodifiable(invitations),
       notifications = List.unmodifiable(notifications);

  factory CollaborationState.fromJson(Map<String, dynamic> data) =>
      CollaborationState(
        invitations: [
          for (final row in collaborationMaps(data['invitations']))
            CollaborationInvitation.fromJson(row),
        ],
        notifications: [
          for (final row in collaborationMaps(data['notifications']))
            CollaborationNotification.fromJson(row),
        ],
        personalRevision: switch (data['personalRevision']) {
          final num value => value.toInt(),
          _ => 0,
        },
      );

  final List<CollaborationInvitation> invitations;
  final List<CollaborationNotification> notifications;
  final int personalRevision;
}

enum CollaborationEmailDelivery { notRequested, sent, failed }

final class CollaborationInviteOutcome {
  CollaborationInviteOutcome({
    required this.id,
    required this.emailDelivery,
    this.email,
    this.role,
    this.token,
    this.url,
    this.expiresAt,
  });

  factory CollaborationInviteOutcome.fromJson(Map<String, dynamic> data) =>
      CollaborationInviteOutcome(
        id: _requiredId(data['id'], 'invite.id'),
        emailDelivery: switch (data['emailDelivery']) {
          'sent' => CollaborationEmailDelivery.sent,
          'failed' => CollaborationEmailDelivery.failed,
          _ => CollaborationEmailDelivery.notRequested,
        },
        email: _text(data['email']),
        role: data['role'] == null
            ? null
            : CollaborationRole.parse(data['role']),
        token: _text(data['token']),
        url: _text(data['url']),
        expiresAt: _time(data['expiresAt']),
      );

  final String id;
  final CollaborationEmailDelivery emailDelivery;
  final String? email;
  final CollaborationRole? role;
  final String? token;
  final String? url;
  final DateTime? expiresAt;
}
