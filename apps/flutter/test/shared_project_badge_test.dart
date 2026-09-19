import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/ui/collaboration/widgets/shared_project_badge.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'support/test_app.dart';

const _scopeId = 'scope-1';

ProjectItem _project({String? scopeId}) => ProjectItem(
  id: 'project-1',
  userId: localUserId,
  name: 'Shared project',
  scopeId: scopeId,
  orderKey: 'a',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

CollaborationConflict _conflict() => const CollaborationConflict(
  scopeId: _scopeId,
  baseRevision: 1,
  id: 'command-1',
  type: 'task.update',
  clientId: null,
  lastError: null,
);

Future<void> _pumpBadge(
  WidgetTester tester, {
  required ProjectItem project,
  List<CollaborationConflict> conflicts = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scopeConflictsProvider.overrideWith(
          (ref, scopeId) => Stream.value(conflicts),
        ),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SharedProjectBadge(project: project)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadTestAppResources);

  testWidgets('marks a shared project with a users icon', (tester) async {
    await _pumpBadge(tester, project: _project(scopeId: _scopeId));

    final icon = find.byIcon(LucideIcons.users);
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon), const Size(14, 14));
    expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
  });

  testWidgets('swaps to a warning triangle when the scope has conflicts', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      project: _project(scopeId: _scopeId),
      conflicts: [_conflict()],
    );

    final icon = find.byIcon(LucideIcons.triangleAlert);
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon), const Size(14, 14));
    expect(find.byIcon(LucideIcons.users), findsNothing);
  });

  testWidgets('renders nothing for a project without a scope', (tester) async {
    await _pumpBadge(tester, project: _project());

    expect(find.byType(Icon), findsNothing);
    expect(tester.getSize(find.byType(SharedProjectBadge)), Size.zero);
  });
}
