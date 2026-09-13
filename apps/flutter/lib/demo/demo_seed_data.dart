import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/db/app_database.dart';

const _demoProductProjectId = 'demo-project-product';
const _demoLearningProjectId = 'demo-project-learning';
const _demoPersonalProjectId = 'demo-project-personal';
const _demoResearchProjectId = 'demo-project-research';
const _demoMaintenanceProjectId = 'demo-project-maintenance';

const _demoLabelDeepWorkId = 'demo-label-deep-work';
const _demoLabelCodingId = 'demo-label-coding';
const _demoLabelReviewId = 'demo-label-review';
const _demoLabelWritingId = 'demo-label-writing';
const _demoLabelErrandsId = 'demo-label-errands';
const _demoLabelPlanningId = 'demo-label-planning';
const _demoLabelCalendarId = 'demo-label-calendar';
const _demoLabelDesignId = 'demo-label-design';
const _demoLabelDocsId = 'demo-label-docs';
const _demoLabelAdminId = 'demo-label-admin';
const _demoLabelBugId = 'demo-label-bug';
const _demoLabelBlockedId = 'demo-label-blocked';

const _demoUserEmail = 'emily.parker@example.com';
const _demoUserDisplayName = 'Emily Parker';

extension AppDemoSeedData on AppDatabase {
  Future<void> ensureDemoSeedData() async {
    await ensureSeedData();

    final nowLocal = DateTime.now();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final nowUtc = DateTime.now().toUtc();

    final completedTodayAt = _localTime(today, 16).toUtc();
    final completedEarlyTodayAt = _localTime(today, 11, 10).toUtc();
    final completedMiddayTodayAt = _localTime(today, 13, 20).toUtc();
    final completedLateTodayAt = _localTime(today, 17, 5).toUtc();
    final completedYesterdayAt = _localTime(yesterday, 18, 15).toUtc();
    final completedEarlyYesterdayAt = _localTime(yesterday, 12, 45).toUtc();
    final completedLateYesterdayAt = _localTime(yesterday, 19, 10).toUtc();
    final focusStartToday = _localTime(today, 9, 30).toUtc();
    final focusStartYesterday = _localTime(yesterday, 15).toUtc();
    final secondFocusStartToday = _localTime(today, 10, 5).toUtc();
    final thirdFocusStartToday = _localTime(today, 12, 40).toUtc();
    final fourthFocusStartToday = _localTime(today, 15, 10).toUtc();
    final secondFocusStartYesterday = _localTime(yesterday, 16, 20).toUtc();

    await transaction(() async {
      await _updateDemoUser(nowUtc);
      await _upsertProjects(nowUtc);
      await _upsertLabels(nowUtc);
      await _upsertTasks(
        nowUtc: nowUtc,
        today: today,
        yesterday: yesterday,
        tomorrow: tomorrow,
        nextWeek: nextWeek,
        completedTodayAt: completedTodayAt,
        completedEarlyTodayAt: completedEarlyTodayAt,
        completedMiddayTodayAt: completedMiddayTodayAt,
        completedLateTodayAt: completedLateTodayAt,
        completedYesterdayAt: completedYesterdayAt,
        completedEarlyYesterdayAt: completedEarlyYesterdayAt,
        completedLateYesterdayAt: completedLateYesterdayAt,
      );
      await _upsertTaskLabels(nowUtc);
      await _upsertFocusHistory(
        nowUtc: nowUtc,
        focusStartToday: focusStartToday,
        focusStartYesterday: focusStartYesterday,
        secondFocusStartToday: secondFocusStartToday,
        thirdFocusStartToday: thirdFocusStartToday,
        fourthFocusStartToday: fourthFocusStartToday,
        secondFocusStartYesterday: secondFocusStartYesterday,
      );
      await _upsertCompletions(
        nowUtc: nowUtc,
        completedTodayAt: completedTodayAt,
        completedEarlyTodayAt: completedEarlyTodayAt,
        completedMiddayTodayAt: completedMiddayTodayAt,
        completedLateTodayAt: completedLateTodayAt,
        completedYesterdayAt: completedYesterdayAt,
        completedEarlyYesterdayAt: completedEarlyYesterdayAt,
        completedLateYesterdayAt: completedLateYesterdayAt,
      );
    });
  }

  Future<void> _updateDemoUser(DateTime now) {
    return (update(users)..where((row) => row.id.equals(localUserId))).write(
      UsersCompanion(
        email: const Value(_demoUserEmail),
        displayName: const Value(_demoUserDisplayName),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _upsertProjects(DateTime now) async {
    await into(projects).insertOnConflictUpdate(
      ProjectsCompanion.insert(
        id: _demoProductProjectId,
        userId: localUserId,
        name: 'Product Launch',
        color: const Value('#F97316'),
        viewStyle: const Value('list'),
        isFavorite: const Value(true),
        isArchived: const Value(false),
        isDeleted: const Value(false),
        orderKey: 'b',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(projects).insertOnConflictUpdate(
      ProjectsCompanion.insert(
        id: _demoLearningProjectId,
        userId: localUserId,
        name: 'Learning',
        color: const Value('#3B82F6'),
        viewStyle: const Value('list'),
        isFavorite: const Value(false),
        isArchived: const Value(false),
        isDeleted: const Value(false),
        orderKey: 'c',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(projects).insertOnConflictUpdate(
      ProjectsCompanion.insert(
        id: _demoPersonalProjectId,
        userId: localUserId,
        name: 'Personal Ops',
        color: const Value('#10B981'),
        viewStyle: const Value('list'),
        isFavorite: const Value(false),
        isArchived: const Value(false),
        isDeleted: const Value(false),
        orderKey: 'd',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(projects).insertOnConflictUpdate(
      ProjectsCompanion.insert(
        id: _demoResearchProjectId,
        userId: localUserId,
        name: 'Research',
        color: const Value('#8B5CF6'),
        viewStyle: const Value('list'),
        isFavorite: const Value(false),
        isArchived: const Value(false),
        isDeleted: const Value(false),
        orderKey: 'e',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(projects).insertOnConflictUpdate(
      ProjectsCompanion.insert(
        id: _demoMaintenanceProjectId,
        userId: localUserId,
        name: 'App Maintenance',
        color: const Value('#14B8A6'),
        viewStyle: const Value('list'),
        isFavorite: const Value(true),
        isArchived: const Value(false),
        isDeleted: const Value(false),
        orderKey: 'f',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _upsertLabels(DateTime now) async {
    await _upsertLabel(
      id: _demoLabelDeepWorkId,
      name: 'deep-work',
      color: '#7C3AED',
      orderKey: 'a',
      now: now,
      isFavorite: true,
    );
    await _upsertLabel(
      id: _demoLabelCodingId,
      name: 'coding',
      color: '#2563EB',
      orderKey: 'b',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelReviewId,
      name: 'review',
      color: '#EA580C',
      orderKey: 'c',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelWritingId,
      name: 'writing',
      color: '#059669',
      orderKey: 'd',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelErrandsId,
      name: 'errands',
      color: '#64748B',
      orderKey: 'e',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelPlanningId,
      name: 'planning',
      color: '#0891B2',
      orderKey: 'f',
      now: now,
      isFavorite: true,
    );
    await _upsertLabel(
      id: _demoLabelCalendarId,
      name: 'calendar',
      color: '#4F46E5',
      orderKey: 'g',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelDesignId,
      name: 'design',
      color: '#DB2777',
      orderKey: 'h',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelDocsId,
      name: 'docs',
      color: '#16A34A',
      orderKey: 'i',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelAdminId,
      name: 'admin',
      color: '#475569',
      orderKey: 'j',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelBugId,
      name: 'bug',
      color: '#DC2626',
      orderKey: 'k',
      now: now,
    );
    await _upsertLabel(
      id: _demoLabelBlockedId,
      name: 'blocked',
      color: '#A16207',
      orderKey: 'l',
      now: now,
    );
  }

  Future<void> _upsertLabel({
    required String id,
    required String name,
    required String color,
    required String orderKey,
    required DateTime now,
    bool isFavorite = false,
  }) {
    return into(labels).insertOnConflictUpdate(
      LabelsCompanion.insert(
        id: id,
        userId: localUserId,
        name: name,
        color: Value(color),
        orderKey: orderKey,
        isFavorite: Value(isFavorite),
        isDeleted: const Value(false),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _upsertTasks({
    required DateTime nowUtc,
    required DateTime today,
    required DateTime yesterday,
    required DateTime tomorrow,
    required DateTime nextWeek,
    required DateTime completedTodayAt,
    required DateTime completedEarlyTodayAt,
    required DateTime completedMiddayTodayAt,
    required DateTime completedLateTodayAt,
    required DateTime completedYesterdayAt,
    required DateTime completedEarlyYesterdayAt,
    required DateTime completedLateYesterdayAt,
  }) async {
    await _upsertTask(
      id: 'demo-task-sync-review',
      content: 'Review Google Calendar sync edge cases',
      description: 'Check timed events, all-day dates, and completion markers.',
      projectId: _demoProductProjectId,
      priority: 1,
      dueJson: _timedJson(_localTime(today, 10), _localTime(today, 11)),
      estimatedFocusIntervals: 2,
      completedFocusIntervals: 1,
      totalFocusSeconds: 25 * 60,
      orderKey: 'demo-001',
      dayOrder: 1,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-weekly-report',
      content: 'Draft weekly focus report',
      description: 'Summarize completed intervals and open focus load.',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-002',
      dayOrder: 2,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-feedback',
      content: 'Respond to integration feedback',
      description: 'Turn the review notes into small follow-up tasks.',
      projectId: _demoProductProjectId,
      priority: 1,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-003',
      dayOrder: 3,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-personal-errand',
      content: 'Buy coffee beans',
      projectId: _demoPersonalProjectId,
      priority: 4,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-004',
      dayOrder: 4,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-sprint-goals',
      content: 'Plan next sprint goals',
      description: 'Pick the three outcomes that matter before adding tickets.',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(tomorrow),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-005',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-quick-add',
      content: 'Refactor quick add parser examples',
      projectId: _demoLearningProjectId,
      priority: 3,
      dueJson: _allDayJson(nextWeek),
      estimatedFocusIntervals: 3,
      orderKey: 'demo-006',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-keyboard-shortcuts',
      content: 'Capture idea: keyboard shortcuts for task triage',
      description: 'Keep this in Inbox until the shortcut model is clearer.',
      projectId: inboxProjectId,
      priority: 4,
      estimatedFocusIntervals: null,
      orderKey: 'demo-007',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-sync-queue-triage',
      content: 'Triage retry failures in sync queue',
      description:
          'Group failures by command type before changing retry rules.',
      projectId: _demoMaintenanceProjectId,
      priority: 1,
      dueJson: _timedJson(_localTime(today, 11, 30), _localTime(today, 12)),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-008',
      dayOrder: 5,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-today-ui-polish',
      content: 'Polish Today screen focus summary',
      description:
          'Make planned load, done count, and focus time easy to scan.',
      projectId: _demoMaintenanceProjectId,
      priority: 2,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-009',
      dayOrder: 6,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-demo-copywriting',
      content: 'Tighten demo copy and labels',
      description: 'Replace placeholder wording with product-like task names.',
      projectId: _demoProductProjectId,
      priority: 3,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-010',
      dayOrder: 7,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-calendar-settings',
      content: 'Verify Google Calendar settings flow',
      description: 'Check disconnected, connected, warning, and error states.',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _timedJson(_localTime(today, 14), _localTime(today, 14, 45)),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-011',
      dayOrder: 8,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-inbox-capture-review',
      content: 'Review Inbox captures from yesterday',
      projectId: inboxProjectId,
      priority: 4,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-012',
      dayOrder: 9,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-household-invoices',
      content: 'Pay home office invoices',
      projectId: _demoPersonalProjectId,
      priority: 3,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-013',
      dayOrder: 10,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-overdue-cleanup',
      content: 'Clean up stale demo records',
      description: 'Confirm deleted rows stay out of regular task queries.',
      projectId: _demoMaintenanceProjectId,
      priority: 2,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-014',
      dayOrder: 11,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-overdue-api-notes',
      content: 'Finish notes on offline sync API',
      projectId: _demoResearchProjectId,
      priority: 1,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-015',
      dayOrder: 12,
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-write-release-notes',
      content: 'Write release notes for demo mode',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(tomorrow),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-016',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-design-focus-widget',
      content: 'Design compact focus widget states',
      projectId: _demoMaintenanceProjectId,
      priority: 3,
      dueJson: _allDayJson(tomorrow),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-017',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-book-dentist',
      content: 'Book dentist appointment',
      projectId: _demoPersonalProjectId,
      priority: 4,
      dueJson: _allDayJson(tomorrow),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-018',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-review-shortcuts',
      content: 'Review keyboard shortcut patterns',
      projectId: _demoLearningProjectId,
      priority: 3,
      dueJson: _allDayJson(tomorrow),
      estimatedFocusIntervals: 1,
      orderKey: 'demo-019',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-research-offline-sync',
      content: 'Research conflict handling for offline edits',
      projectId: _demoResearchProjectId,
      priority: 2,
      dueJson: _allDayJson(nextWeek),
      estimatedFocusIntervals: 3,
      orderKey: 'demo-020',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-read-riverpod',
      content: 'Read Riverpod caching notes',
      projectId: _demoLearningProjectId,
      priority: 3,
      dueJson: _allDayJson(nextWeek),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-021',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-plan-quarter',
      content: 'Outline next quarter outcomes',
      description: 'Keep it to measurable outcomes before creating tasks.',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(nextWeek),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-022',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-clean-test-fixtures',
      content: 'Clean up widget test fixtures',
      projectId: _demoMaintenanceProjectId,
      priority: 3,
      dueJson: _allDayJson(nextWeek),
      estimatedFocusIntervals: 2,
      orderKey: 'demo-023',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-inbox-pricing-idea',
      content: 'Capture idea: focus budget by project',
      description: 'Maybe useful for planning without turning into a report.',
      projectId: inboxProjectId,
      priority: 3,
      orderKey: 'demo-024',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-inbox-desktop-notifications',
      content: 'Check desktop notification permissions',
      projectId: inboxProjectId,
      priority: 2,
      estimatedFocusIntervals: 2,
      orderKey: 'demo-025',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-inbox-db-backup',
      content: 'Decide how local database backups should work',
      projectId: inboxProjectId,
      priority: 4,
      orderKey: 'demo-026',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-ship-demo',
      content: 'Ship demo seed flow',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      completedFocusIntervals: 1,
      totalFocusSeconds: 25 * 60,
      status: 'completed',
      completedAt: completedTodayAt,
      orderKey: 'demo-027',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-drift-notes',
      content: 'Read Drift migration notes',
      projectId: _demoLearningProjectId,
      priority: 3,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 1,
      completedFocusIntervals: 1,
      totalFocusSeconds: 25 * 60,
      status: 'completed',
      completedAt: completedYesterdayAt,
      orderKey: 'demo-028',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-prepare-demo-script',
      content: 'Prepare walkthrough script',
      projectId: _demoProductProjectId,
      priority: 2,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      completedFocusIntervals: 1,
      totalFocusSeconds: 25 * 60,
      status: 'completed',
      completedAt: completedMiddayTodayAt,
      orderKey: 'demo-029',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-fix-calendar-config',
      content: 'Fix calendar config fallback',
      projectId: _demoMaintenanceProjectId,
      priority: 1,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 2,
      completedFocusIntervals: 2,
      totalFocusSeconds: 50 * 60,
      status: 'completed',
      completedAt: completedEarlyTodayAt,
      orderKey: 'demo-030',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-review-pr-checklist',
      content: 'Review PR checklist',
      projectId: _demoProductProjectId,
      priority: 3,
      dueJson: _allDayJson(today),
      estimatedFocusIntervals: 1,
      status: 'completed',
      completedAt: completedLateTodayAt,
      orderKey: 'demo-031',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-archive-old-labels',
      content: 'Archive obsolete label names',
      projectId: _demoPersonalProjectId,
      priority: 4,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 1,
      status: 'completed',
      completedAt: completedEarlyYesterdayAt,
      orderKey: 'demo-032',
      now: nowUtc,
    );
    await _upsertTask(
      id: 'demo-task-sketch-report-cards',
      content: 'Sketch productivity report cards',
      projectId: _demoResearchProjectId,
      priority: 3,
      dueJson: _allDayJson(yesterday),
      estimatedFocusIntervals: 1,
      completedFocusIntervals: 1,
      totalFocusSeconds: 25 * 60,
      status: 'completed',
      completedAt: completedLateYesterdayAt,
      orderKey: 'demo-033',
      now: nowUtc,
    );
  }

  Future<void> _upsertTask({
    required String id,
    required String content,
    required String projectId,
    required int priority,
    required String orderKey,
    required DateTime now,
    String? description,
    String? dueJson,
    int? estimatedFocusIntervals,
    int completedFocusIntervals = 0,
    int totalFocusSeconds = 0,
    int? dayOrder,
    String status = 'open',
    DateTime? completedAt,
  }) {
    return into(tasks).insertOnConflictUpdate(
      TasksCompanion.insert(
        id: id,
        userId: localUserId,
        content: content,
        description: Value(description),
        projectId: projectId,
        sectionId: const Value(null),
        parentId: const Value(null),
        priority: Value(priority),
        dueJson: Value(dueJson),
        deadlineJson: const Value(null),
        durationSeconds: const Value(null),
        status: Value(status),
        estimatedFocusIntervals: Value(estimatedFocusIntervals),
        completedFocusIntervals: Value(completedFocusIntervals),
        totalFocusSeconds: Value(totalFocusSeconds),
        orderKey: orderKey,
        dayOrder: Value(dayOrder),
        isCollapsed: const Value(false),
        isDeleted: const Value(false),
        createdAt: now,
        updatedAt: now,
        completedAt: Value(completedAt),
      ),
    );
  }

  Future<void> _upsertTaskLabels(DateTime now) async {
    await _linkLabels('demo-task-sync-review', [
      _demoLabelDeepWorkId,
      _demoLabelCodingId,
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-weekly-report', [
      _demoLabelWritingId,
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-feedback', [_demoLabelReviewId], now);
    await _linkLabels('demo-task-personal-errand', [_demoLabelErrandsId], now);
    await _linkLabels('demo-task-sprint-goals', [_demoLabelDeepWorkId], now);
    await _linkLabels('demo-task-quick-add', [
      _demoLabelCodingId,
      _demoLabelDeepWorkId,
    ], now);
    await _linkLabels('demo-task-keyboard-shortcuts', [
      _demoLabelWritingId,
    ], now);
    await _linkLabels('demo-task-ship-demo', [
      _demoLabelCodingId,
      _demoLabelDeepWorkId,
    ], now);
    await _linkLabels('demo-task-drift-notes', [_demoLabelCodingId], now);
    await _linkLabels('demo-task-sync-queue-triage', [
      _demoLabelCodingId,
      _demoLabelBugId,
      _demoLabelBlockedId,
    ], now);
    await _linkLabels('demo-task-today-ui-polish', [
      _demoLabelDesignId,
      _demoLabelPlanningId,
    ], now);
    await _linkLabels('demo-task-demo-copywriting', [
      _demoLabelWritingId,
      _demoLabelDocsId,
    ], now);
    await _linkLabels('demo-task-calendar-settings', [
      _demoLabelCalendarId,
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-inbox-capture-review', [
      _demoLabelPlanningId,
    ], now);
    await _linkLabels('demo-task-household-invoices', [
      _demoLabelAdminId,
      _demoLabelErrandsId,
    ], now);
    await _linkLabels('demo-task-overdue-cleanup', [
      _demoLabelBugId,
      _demoLabelCodingId,
    ], now);
    await _linkLabels('demo-task-overdue-api-notes', [
      _demoLabelDocsId,
      _demoLabelBlockedId,
    ], now);
    await _linkLabels('demo-task-write-release-notes', [
      _demoLabelDocsId,
      _demoLabelWritingId,
    ], now);
    await _linkLabels('demo-task-design-focus-widget', [
      _demoLabelDesignId,
      _demoLabelDeepWorkId,
    ], now);
    await _linkLabels('demo-task-book-dentist', [_demoLabelErrandsId], now);
    await _linkLabels('demo-task-review-shortcuts', [
      _demoLabelCodingId,
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-research-offline-sync', [
      _demoLabelDeepWorkId,
      _demoLabelDocsId,
    ], now);
    await _linkLabels('demo-task-read-riverpod', [
      _demoLabelCodingId,
      _demoLabelDocsId,
    ], now);
    await _linkLabels('demo-task-plan-quarter', [
      _demoLabelPlanningId,
      _demoLabelDeepWorkId,
    ], now);
    await _linkLabels('demo-task-clean-test-fixtures', [
      _demoLabelCodingId,
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-inbox-pricing-idea', [
      _demoLabelPlanningId,
    ], now);
    await _linkLabels('demo-task-inbox-desktop-notifications', [
      _demoLabelBugId,
      _demoLabelAdminId,
    ], now);
    await _linkLabels('demo-task-inbox-db-backup', [
      _demoLabelAdminId,
      _demoLabelDocsId,
    ], now);
    await _linkLabels('demo-task-prepare-demo-script', [
      _demoLabelWritingId,
      _demoLabelPlanningId,
    ], now);
    await _linkLabels('demo-task-fix-calendar-config', [
      _demoLabelCalendarId,
      _demoLabelCodingId,
    ], now);
    await _linkLabels('demo-task-review-pr-checklist', [
      _demoLabelReviewId,
    ], now);
    await _linkLabels('demo-task-archive-old-labels', [_demoLabelAdminId], now);
    await _linkLabels('demo-task-sketch-report-cards', [
      _demoLabelDesignId,
      _demoLabelPlanningId,
    ], now);
  }

  Future<void> _linkLabels(
    String taskId,
    List<String> labelIds,
    DateTime now,
  ) async {
    for (final labelId in labelIds) {
      await into(taskLabels).insertOnConflictUpdate(
        TaskLabelsCompanion.insert(
          taskId: taskId,
          labelId: labelId,
          createdAt: now,
        ),
      );
    }
  }

  Future<void> _upsertFocusHistory({
    required DateTime nowUtc,
    required DateTime focusStartToday,
    required DateTime focusStartYesterday,
    required DateTime secondFocusStartToday,
    required DateTime thirdFocusStartToday,
    required DateTime fourthFocusStartToday,
    required DateTime secondFocusStartYesterday,
  }) async {
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-sync-review',
      intervalIdPrefix: 'demo-focus-interval-sync-review',
      taskId: 'demo-task-sync-review',
      projectId: _demoProductProjectId,
      startedAt: focusStartToday,
      completedIntervals: 1,
      now: nowUtc,
    );
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-fix-calendar-config',
      intervalIdPrefix: 'demo-focus-interval-fix-calendar-config',
      taskId: 'demo-task-fix-calendar-config',
      projectId: _demoMaintenanceProjectId,
      startedAt: secondFocusStartToday,
      completedIntervals: 2,
      now: nowUtc,
    );
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-prepare-demo-script',
      intervalIdPrefix: 'demo-focus-interval-prepare-demo-script',
      taskId: 'demo-task-prepare-demo-script',
      projectId: _demoProductProjectId,
      startedAt: thirdFocusStartToday,
      completedIntervals: 1,
      now: nowUtc,
    );
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-ship-demo',
      intervalIdPrefix: 'demo-focus-interval-ship-demo',
      taskId: 'demo-task-ship-demo',
      projectId: _demoProductProjectId,
      startedAt: fourthFocusStartToday,
      completedIntervals: 1,
      now: nowUtc,
    );
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-drift-notes',
      intervalIdPrefix: 'demo-focus-interval-drift-notes',
      taskId: 'demo-task-drift-notes',
      projectId: _demoLearningProjectId,
      startedAt: focusStartYesterday,
      completedIntervals: 1,
      now: nowUtc,
    );
    await _upsertCompletedWorkSession(
      runId: 'demo-focus-run-sketch-report-cards',
      intervalIdPrefix: 'demo-focus-interval-sketch-report-cards',
      taskId: 'demo-task-sketch-report-cards',
      projectId: _demoResearchProjectId,
      startedAt: secondFocusStartYesterday,
      completedIntervals: 1,
      now: nowUtc,
    );
  }

  Future<void> _upsertCompletedWorkSession({
    required String runId,
    required String intervalIdPrefix,
    required String taskId,
    required String projectId,
    required DateTime startedAt,
    required int completedIntervals,
    required DateTime now,
  }) async {
    final endedAt = startedAt.add(
      Duration(
        minutes: (completedIntervals * 25) + (completedIntervals - 1) * 5,
      ),
    );
    await _upsertFocusRun(
      id: runId,
      taskId: taskId,
      projectId: projectId,
      startedAt: startedAt,
      endedAt: endedAt,
      completedWorkIntervals: completedIntervals,
      now: now,
    );
    for (var index = 0; index < completedIntervals; index += 1) {
      final intervalStart = startedAt.add(Duration(minutes: index * 30));
      await _upsertFocusInterval(
        id: '$intervalIdPrefix-work-${index + 1}',
        runId: runId,
        taskId: taskId,
        projectId: projectId,
        startedAt: intervalStart,
        completedAt: intervalStart.add(const Duration(minutes: 25)),
        sequenceNumber: index + 1,
        now: now,
      );
    }
  }

  Future<void> _upsertFocusRun({
    required String id,
    required String taskId,
    required String projectId,
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime now,
    required int completedWorkIntervals,
  }) {
    return into(focusRuns).insertOnConflictUpdate(
      FocusRunsCompanion.insert(
        id: id,
        userId: localUserId,
        taskId: Value(taskId),
        projectId: Value(projectId),
        presetId: defaultPresetId,
        status: 'completed',
        startedAt: startedAt,
        endedAt: Value(endedAt),
        targetWorkIntervals: completedWorkIntervals,
        completedWorkIntervals: Value(completedWorkIntervals),
        note: const Value('Demo focus session'),
        createdAt: now,
        updatedAt: now,
        isDeleted: const Value(false),
      ),
    );
  }

  Future<void> _upsertFocusInterval({
    required String id,
    required String runId,
    required String taskId,
    required String projectId,
    required DateTime startedAt,
    required DateTime completedAt,
    required int sequenceNumber,
    required DateTime now,
  }) {
    return into(focusIntervals).insertOnConflictUpdate(
      FocusIntervalsCompanion.insert(
        id: id,
        runId: runId,
        taskId: Value(taskId),
        projectId: Value(projectId),
        type: 'work',
        status: 'completed',
        plannedSeconds: 25 * 60,
        startedAt: startedAt,
        completedAt: Value(completedAt),
        sequenceNumber: sequenceNumber,
        createdAt: now,
        updatedAt: now,
        isDeleted: const Value(false),
      ),
    );
  }

  Future<void> _upsertCompletions({
    required DateTime nowUtc,
    required DateTime completedTodayAt,
    required DateTime completedEarlyTodayAt,
    required DateTime completedMiddayTodayAt,
    required DateTime completedLateTodayAt,
    required DateTime completedYesterdayAt,
    required DateTime completedEarlyYesterdayAt,
    required DateTime completedLateYesterdayAt,
  }) async {
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-ship-demo',
        taskId: 'demo-task-ship-demo',
        userId: localUserId,
        completedAt: completedTodayAt,
        snapshotJson: Value(
          jsonEncode({'content': 'Ship demo seed flow', 'source': 'demo'}),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-fix-calendar-config',
        taskId: 'demo-task-fix-calendar-config',
        userId: localUserId,
        completedAt: completedEarlyTodayAt,
        snapshotJson: Value(
          jsonEncode({
            'content': 'Fix calendar config fallback',
            'source': 'demo',
          }),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-prepare-demo-script',
        taskId: 'demo-task-prepare-demo-script',
        userId: localUserId,
        completedAt: completedMiddayTodayAt,
        snapshotJson: Value(
          jsonEncode({
            'content': 'Prepare walkthrough script',
            'source': 'demo',
          }),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-review-pr-checklist',
        taskId: 'demo-task-review-pr-checklist',
        userId: localUserId,
        completedAt: completedLateTodayAt,
        snapshotJson: Value(
          jsonEncode({'content': 'Review PR checklist', 'source': 'demo'}),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-drift-notes',
        taskId: 'demo-task-drift-notes',
        userId: localUserId,
        completedAt: completedYesterdayAt,
        snapshotJson: Value(
          jsonEncode({
            'content': 'Read Drift migration notes',
            'source': 'demo',
          }),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-archive-old-labels',
        taskId: 'demo-task-archive-old-labels',
        userId: localUserId,
        completedAt: completedEarlyYesterdayAt,
        snapshotJson: Value(
          jsonEncode({
            'content': 'Archive obsolete label names',
            'source': 'demo',
          }),
        ),
        createdAt: nowUtc,
      ),
    );
    await into(taskCompletions).insertOnConflictUpdate(
      TaskCompletionsCompanion.insert(
        id: 'demo-completion-sketch-report-cards',
        taskId: 'demo-task-sketch-report-cards',
        userId: localUserId,
        completedAt: completedLateYesterdayAt,
        snapshotJson: Value(
          jsonEncode({
            'content': 'Sketch productivity report cards',
            'source': 'demo',
          }),
        ),
        createdAt: nowUtc,
      ),
    );
  }
}

DateTime _localTime(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

String _allDayJson(DateTime date) {
  return jsonEncode({'type': 'allDay', 'date': _formatDate(date)});
}

String _timedJson(DateTime start, DateTime end) {
  return jsonEncode({
    'type': 'timed',
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
  });
}

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
