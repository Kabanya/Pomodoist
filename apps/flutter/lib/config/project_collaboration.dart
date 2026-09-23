import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';

/// Collaboration behaviour a [ProjectRepository] needs to delete a shared root
/// through the server scope operation instead of a content command the server
/// rejects.
///
/// Declared here rather than in `account_providers.dart` so that `providers.dart`
/// can read it without importing the account layer, which owns the account
/// client and the sync engine. Wiring the account-backed value is the job of a
/// composition file that is allowed to see both sides; see
/// `collaboration_dependencies.dart`.
class ProjectCollaboration {
  const ProjectCollaboration({this.api, this.synchronize});

  /// Null while the account is unavailable, so deleting a shared root fails
  /// with `unauthenticated` instead of silently issuing a local-only delete.
  final CollaborationApi? api;

  /// Best-effort pull after the server applied a scope delete.
  final Future<void> Function()? synchronize;

  static const ProjectCollaboration none = ProjectCollaboration();
}

final projectCollaborationProvider = Provider<ProjectCollaboration>(
  (ref) => ProjectCollaboration.none,
);
