import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
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

Future<void> _pumpBadge(
  WidgetTester tester, {
  required ProjectItem project,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: testAppBuilder,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SharedProjectBadge(project: project)),
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

  testWidgets('renders nothing for a project without a scope', (tester) async {
    await _pumpBadge(tester, project: _project());

    expect(find.byType(Icon), findsNothing);
    expect(tester.getSize(find.byType(SharedProjectBadge)), Size.zero);
  });
}
