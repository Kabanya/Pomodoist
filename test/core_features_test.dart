import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/app_language.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/audio/focus_sound_player.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/demo/demo_seed_data.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:pomodoist/core/sync/pomodoist_retention.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/core/time/timer_engine.dart';
import 'package:pomodoist/features/filters/domain/filter_parser.dart';
import 'package:pomodoist/features/focus/data/focus_repository_impl.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/productivity/data/achievement_repository_impl.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/data/productivity_repository_impl.dart';
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/data/kanban_transition_coordinator.dart';
import 'package:pomodoist/features/tasks/domain/project_colors.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('timer engine', () {
    test('calculates remaining time from timestamps while running', () {
      final startedAt = DateTime.utc(2026, 4, 27, 10);
      final now = startedAt.add(const Duration(minutes: 7));

      final remaining = calculateRemaining(
        now: now,
        startedAt: startedAt,
        plannedSeconds: 25 * 60,
        pausedTotalSeconds: 0,
      );

      expect(remaining, const Duration(minutes: 18));
    });

    test('uses pausedAt instead of now while paused', () {
      final startedAt = DateTime.utc(2026, 4, 27, 10);
      final pausedAt = startedAt.add(const Duration(minutes: 5));
      final now = startedAt.add(const Duration(hours: 1));

      final remaining = calculateRemaining(
        now: now,
        startedAt: startedAt,
        plannedSeconds: 25 * 60,
        pausedTotalSeconds: 0,
        pausedAt: pausedAt,
      );

      expect(remaining, const Duration(minutes: 20));
    });
  });

  group('quick add parser', () {
    test('extracts RU/EN task metadata and focus estimates', () {
      final parsed = const QuickAddParser().parse(
        'Написать sync engine завтра p1 #App @coding 4p',
        now: DateTime(2026, 4, 27, 12),
      );

      expect(parsed.content, 'Написать sync engine');
      expect(parsed.project, 'App');
      expect(parsed.labels, ['coding']);
      expect(parsed.priority, 1);
      expect(parsed.dueDate, DateTime(2026, 4, 28));
      expect(parsed.estimatedFocusIntervals, 4);
    });

    test('parses quoted project and label metadata', () {
      final parsed = const QuickAddParser().parse(
        'Prepare notes #"Product Launch" @"Deep Work"',
      );

      expect(parsed.content, 'Prepare notes');
      expect(parsed.project, 'Product Launch');
      expect(parsed.labels, ['Deep Work']);
    });

    test('supports focus words after a number', () {
      final parsed = const QuickAddParser().parse(
        'Написать статью @writing 3 фокуса',
      );

      expect(parsed.content, 'Написать статью');
      expect(parsed.labels, ['writing']);
      expect(parsed.estimatedFocusIntervals, 3);
    });

    test('parses timed calendar blocks', () {
      final parsed = const QuickAddParser().parse(
        'Планирование завтра 14:00 45m',
        now: DateTime(2026, 4, 27, 12),
      );

      expect(parsed.content, 'Планирование');
      expect(parsed.schedule, isNotNull);
      expect(parsed.schedule!.isTimed, isTrue);
      expect(parsed.schedule!.start!.toLocal().hour, 14);
      expect(parsed.schedule!.duration, const Duration(minutes: 45));
    });

    test('parses an exact timed range', () {
      final parsed = const QuickAddParser().parse(
        'Встреча 17:30-17:45',
        now: DateTime(2026, 4, 27, 12),
      );

      expect(parsed.content, 'Встреча');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 4, 27, 17, 30));
      expect(parsed.schedule!.end!.toLocal(), DateTime(2026, 4, 27, 17, 45));
    });

    test('parses an en-dash range that ends on the next day', () {
      final parsed = const QuickAddParser().parse(
        'Дежурство 23:45–00:15',
        now: DateTime(2026, 4, 27, 12),
      );

      expect(parsed.content, 'Дежурство');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 4, 27, 23, 45));
      expect(parsed.schedule!.end!.toLocal(), DateTime(2026, 4, 28, 0, 15));
    });

    test('uses 30 minutes for timed blocks without explicit duration', () {
      final parsed = const QuickAddParser().parse(
        'Созвон завтра 19:00',
        now: DateTime(2026, 4, 27, 12),
      );

      expect(parsed.content, 'Созвон');
      expect(parsed.schedule, isNotNull);
      expect(parsed.schedule!.duration, const Duration(minutes: 30));
    });

    test('uses default date for bare input without marking it explicit', () {
      final parsed = const QuickAddParser().parse(
        'Plan roadmap',
        now: DateTime(2026, 5, 1, 12),
        defaultDate: DateTime(2026, 5, 4, 18),
      );

      expect(parsed.dueDate, isNull);
      expect(parsed.schedule, TaskSchedule.allDay(DateTime(2026, 5, 4)));
    });

    test('uses default date for a time-only block', () {
      final parsed = const QuickAddParser().parse(
        'Plan roadmap 14:30 45m',
        now: DateTime(2026, 5, 1, 12),
        defaultDate: DateTime(2026, 5, 4, 18),
      );

      expect(parsed.dueDate, isNull);
      expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 5, 4, 14, 30));
      expect(parsed.schedule!.duration, const Duration(minutes: 45));
    });

    test('explicit relative and ISO dates override the default date', () {
      final relative = const QuickAddParser().parse(
        'Plan roadmap tomorrow 14:30',
        now: DateTime(2026, 5, 1, 12),
        defaultDate: DateTime(2026, 5, 9),
      );
      final iso = const QuickAddParser().parse(
        'Plan roadmap 2026-05-06 11:30',
        now: DateTime(2026, 5, 1, 12),
        defaultDate: DateTime(2026, 5, 9),
      );

      expect(relative.dueDate, DateTime(2026, 5, 2));
      expect(relative.schedule!.start!.toLocal(), DateTime(2026, 5, 2, 14, 30));
      expect(iso.dueDate, DateTime(2026, 5, 6));
      expect(iso.schedule!.start!.toLocal(), DateTime(2026, 5, 6, 11, 30));
    });

    test('omitting default date preserves unscheduled and today behavior', () {
      final bare = const QuickAddParser().parse(
        'Plan roadmap',
        now: DateTime(2026, 5, 1, 12),
      );
      final timed = const QuickAddParser().parse(
        'Plan roadmap 14:30',
        now: DateTime(2026, 5, 1, 12),
      );

      expect(bare.dueDate, isNull);
      expect(bare.schedule, isNull);
      expect(timed.dueDate, isNull);
      expect(timed.schedule!.start!.toLocal(), DateTime(2026, 5, 1, 14, 30));
    });

    test('serializes recurrence and calculates next occurrences', () {
      const recurrence = TaskRecurrence(
        interval: 2,
        unit: TaskRecurrenceUnit.week,
        seriesId: 'series-1',
      );
      final schedule = TaskSchedule.timed(
        start: DateTime(2026, 5, 1, 10),
        end: DateTime(2026, 5, 1, 11),
        recurrence: recurrence,
      );
      final parsed = TaskSchedule.fromJsonString(schedule.toJsonString());

      expect(parsed!.recurrence, recurrence);
      expect(parsed.recurrenceSeriesId, isNull);
      expect(
        parsed.nextOccurrenceAfter(DateTime(2026, 5, 20, 12)).start!.toLocal(),
        DateTime(2026, 5, 29, 10),
      );
      expect(
        TaskSchedule.allDay(
          DateTime(2026, 1, 31),
          recurrence: const TaskRecurrence(
            interval: 1,
            unit: TaskRecurrenceUnit.month,
            seriesId: 'month-end',
          ),
        ).nextOccurrence().date,
        DateTime(2026, 2, 28),
      );

      final inactive = TaskSchedule.fromJsonString(
        TaskSchedule.allDay(
          DateTime(2026, 5, 1),
          recurrenceSeriesId: 'series-1',
        ).toJsonString(),
      );
      expect(inactive!.recurrence, isNull);
      expect(inactive.recurrenceSeriesId, 'series-1');
      expect(inactive.isRecurringOccurrence, isTrue);
    });

    test('parses localized today and tomorrow words', () {
      final today = DateTime(2026, 5, 1);
      final cases = [
        ('today', today),
        ('tomorrow', today.add(const Duration(days: 1))),
        ('сегодня', today),
        ('завтра', today.add(const Duration(days: 1))),
        ('Heute', today),
        ('Morgen', today.add(const Duration(days: 1))),
        ('Hoy', today),
        ('Mañana', today.add(const Duration(days: 1))),
        ("Aujourd'hui", today),
        ('Demain', today.add(const Duration(days: 1))),
        ('اليوم', today),
        ('غدا', today.add(const Duration(days: 1))),
        ('今天', today),
        ('明天', today.add(const Duration(days: 1))),
      ];

      for (final (word, expectedDate) in cases) {
        final parsed = const QuickAddParser().parse(
          'localized $word 10:30',
          now: DateTime(2026, 5, 1, 12),
        );

        expect(parsed.content, 'localized', reason: word);
        expect(parsed.schedule, isNotNull, reason: word);
        expect(parsed.schedule!.displayDate, expectedDate, reason: word);
        expect(parsed.schedule!.start!.toLocal().hour, 10, reason: word);
        expect(parsed.schedule!.start!.toLocal().minute, 30, reason: word);
      }
    });

    test('parses Russian voice-style quick add command', () {
      final parsed = const QuickAddParser().parse(
        'созвон завтра p1 #Work @calls 2p',
        now: DateTime(2026, 5, 1, 12),
      );

      expect(parsed.content, 'созвон');
      expect(parsed.dueDate, DateTime(2026, 5, 2));
      expect(parsed.priority, 1);
      expect(parsed.project, 'Work');
      expect(parsed.labels, ['calls']);
      expect(parsed.estimatedFocusIntervals, 2);
    });

    test('parses all quick-add priority tokens', () {
      for (final priority in [1, 2, 3, 4]) {
        final parsed = const QuickAddParser().parse('task p$priority');

        expect(parsed.content, 'task');
        expect(parsed.priority, priority);
      }
    });

    test('parses English voice-style timed block', () {
      final parsed = const QuickAddParser().parse(
        'review roadmap today 10:30 45m',
        now: DateTime(2026, 5, 1, 12),
      );

      expect(parsed.content, 'review roadmap');
      expect(parsed.schedule, isNotNull);
      expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 5, 1, 10, 30));
      expect(parsed.schedule!.duration, const Duration(minutes: 45));
    });

    test('parses model ISO date timed block', () {
      final parsed = const QuickAddParser().parse(
        'Написать отчет 2026-05-06 11:30 2h',
        now: DateTime(2026, 5, 1, 12),
      );

      expect(parsed.content, 'Написать отчет');
      expect(parsed.schedule, isNotNull);
      expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 5, 6, 11, 30));
      expect(parsed.schedule!.duration, const Duration(hours: 2));
    });

    test('parses English AM/PM in any case and strips it from the title', () {
      final parsed = const QuickAddParser().parse(
        'Call client 04/05/2027 at 5:30 p.M.',
        now: DateTime(2026, 7, 10, 12),
      );

      expect(parsed.content, 'Call client');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 17, 30));
    });

    test('treats a past numeric day/month date as the next occurrence', () {
      final parsed = const QuickAddParser().parse(
        'Plan review 04.05 9 AM',
        now: DateTime(2026, 7, 10, 12),
      );

      expect(parsed.content, 'Plan review');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 9));
    });

    test('converts noon, midnight, and AM/PM ranges correctly', () {
      final midnight = const QuickAddParser().parse(
        'Night shift 04/05/2027 12 AM',
        now: DateTime(2026, 7, 10, 12),
      );
      final noon = const QuickAddParser().parse(
        'Lunch 04/05/2027 12 PM',
        now: DateTime(2026, 7, 10, 12),
      );
      final range = const QuickAddParser().parse(
        'Workshop 04/05/2027 5 PM - 6:30 PM',
        now: DateTime(2026, 7, 10, 12),
      );

      expect(midnight.schedule!.start!.toLocal(), DateTime(2027, 5, 4));
      expect(noon.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 12));
      expect(range.content, 'Workshop');
      expect(range.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 17));
      expect(range.schedule!.end!.toLocal(), DateTime(2027, 5, 4, 18, 30));
    });

    test('parses representative localized written date and time forms', () {
      final cases = <({String input, String content, DateTime expected})>[
        (
          input: 'Созвон 4.05.2027 в 5 вечера',
          content: 'Созвон',
          expected: DateTime(2027, 5, 4, 17),
        ),
        (
          input: 'Anruf am 4.05.2027 um 5 Uhr nachmittags',
          content: 'Anruf',
          expected: DateTime(2027, 5, 4, 17),
        ),
        (
          input: 'Llamada el 4/05/2027 a las 5:30 p. m.',
          content: 'Llamada',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
        (
          input: 'Appel le 4 mai 2027 à 17h30',
          content: 'Appel',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
        (
          input: 'اتصال ٤/٥/٢٠٢٧ الساعة ٥:٣٠ م',
          content: 'اتصال',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
        (
          input: '通话 2027年5月4日 下午5点30分',
          content: '通话',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
      ];

      for (final item in cases) {
        final parsed = const QuickAddParser().parse(
          item.input,
          now: DateTime(2026, 7, 10, 12),
        );

        expect(parsed.content, item.content, reason: item.input);
        expect(parsed.schedule, isNotNull, reason: item.input);
        expect(
          parsed.schedule!.start!.toLocal(),
          item.expected,
          reason: item.input,
        );
      }
    });

    test('keeps invalid localized date and time text unscheduled', () {
      final parsed = const QuickAddParser().parse(
        'Call client 31/02/2027 at 13 PM',
        now: DateTime(2026, 7, 10, 12),
      );

      expect(parsed.content, 'Call client 31/02/2027 at 13 PM');
      expect(parsed.schedule, isNull);
    });
  });

  group('focus estimates', () {
    test('calculates timed task focus targets from presets', () {
      expect(
        estimateFocusIntervalsForDuration(
          duration: const Duration(hours: 1),
          preset: _testPreset(
            id: defaultPresetId,
            workMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
          ),
        ),
        2,
      );
      expect(
        estimateFocusIntervalsForDuration(
          duration: const Duration(hours: 1),
          preset: _testPreset(
            id: deepWorkPresetId,
            workMinutes: 50,
            shortBreakMinutes: 10,
            longBreakMinutes: 25,
          ),
        ),
        1,
      );
      expect(
        estimateFocusIntervalsForDuration(
          duration: const Duration(hours: 1),
          preset: _testPreset(
            id: flowPresetId,
            workMinutes: 45,
            shortBreakMinutes: 8,
            longBreakMinutes: 20,
          ),
        ),
        1,
      );
    });

    test('keeps one focus minimum once work duration fits', () {
      final preset = _testPreset(
        id: defaultPresetId,
        workMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
      );

      expect(
        estimateFocusIntervalsForDuration(
          duration: const Duration(minutes: 25),
          preset: preset,
        ),
        1,
      );
      expect(
        estimateFocusIntervalsForDuration(
          duration: const Duration(minutes: 24),
          preset: preset,
        ),
        0,
      );
    });
  });

  group('task decomposer', () {
    test('decodes structured DeepSeek task JSON from chat response', () {
      final tasks = decodeDeepSeekTaskResponse({
        'choices': [
          {
            'message': {
              'content':
                  '```json\n{"tasks":[{"quickAdd":"Купить кофе today 09:00 30m","description":"Взять зерна для встречи"},{"text":"Позвонить врачу tomorrow"}]}\n```',
            },
          },
        ],
      });

      expect(tasks.map((task) => task.quickAdd), [
        'Купить кофе today 09:00 30m',
        'Позвонить врачу tomorrow',
      ]);
      expect(tasks.first.description, 'Взять зерна для встречи');
      expect(tasks.last.description, isNull);
    });

    test('keeps compatibility with legacy DeepSeek string task JSON', () {
      final tasks = decodeTaskJsonContent(
        '{"tasks":["Купить кофе today 09:00 30m","Позвонить врачу tomorrow"]}',
      );

      expect(tasks.map((task) => task.quickAdd), [
        'Купить кофе today 09:00 30m',
        'Позвонить врачу tomorrow',
      ]);
      expect(tasks.first.description, isNull);
      expect(tasks.last.description, isNull);
    });

    test('preserves model priority tokens inferred from spoken importance', () {
      final tasks = decodeTaskJsonContent(
        '{"tasks":[{"quickAdd":"Починить оплату p1"},{"quickAdd":"Подготовить отчет p2"},{"quickAdd":"Разобрать заметки p3"},{"quickAdd":"Почистить backlog p4"}]}',
      );

      expect(tasks.map((task) => task.quickAdd), [
        'Починить оплату p1',
        'Подготовить отчет p2',
        'Разобрать заметки p3',
        'Почистить backlog p4',
      ]);
    });

    test('decodes nested DeepSeek subtasks', () {
      final tasks = decodeTaskJsonContent(
        '{"tasks":[{"quickAdd":"Запустить проект #Work","subtasks":[{"quickAdd":"Написать бриф tomorrow","children":[{"quickAdd":"Собрать вводные @research"}]},{"text":"Согласовать бюджет p1"}]}]}',
      );

      expect(tasks.single.quickAdd, 'Запустить проект #Work');
      expect(tasks.single.subtasks.map((task) => task.quickAdd), [
        'Написать бриф tomorrow',
        'Согласовать бюджет p1',
      ]);
      expect(
        tasks.single.subtasks.first.subtasks.single.quickAdd,
        'Собрать вводные @research',
      );
    });
  });

  group('filter parser', () {
    test('parses focus predicates and boolean operators', () {
      final ast = FilterParser().parse('today & !focus:completed');

      expect(ast, isA<AndNode>());
      final and = ast as AndNode;
      expect(and.left, isA<PredicateNode>());
      expect(and.right, isA<NotNode>());
      expect((and.left as PredicateNode).predicate.name, 'today');
      expect(
        ((and.right as NotNode).node as PredicateNode).predicate.name,
        'focus',
      );
      expect(
        ((and.right as NotNode).node as PredicateNode).predicate.value,
        'completed',
      );
    });
  });

  group('achievements', () {
    test('retained completions count without task rows', () {
      final now = DateTime.utc(2026, 5, 1, 10);
      final items = evaluateAchievements(
        completions: [
          for (var index = 0; index < 5; index++)
            _achievementCompletion('completion-$index', now, taskId: 't$index'),
        ],
        intervals: const [],
      );

      expect(_achievementById(items, 'task_5').unlocked, isTrue);
    });

    test('milestones unlock at thresholds and ignore invalid intervals', () {
      final now = DateTime(2026, 5, 1, 10);
      final items = evaluateAchievements(
        completions: [
          for (var index = 0; index < 10; index++)
            _achievementCompletion('completion-$index', now, taskId: 't$index'),
        ],
        intervals: [
          for (var index = 0; index < 5; index++)
            _achievementInterval('work-$index', now),
          _achievementInterval('break', now, type: 'shortBreak'),
          _achievementInterval('stopped', now, status: 'stopped'),
          _achievementInterval('deleted', now, isDeleted: true),
        ],
      );

      expect(_achievementById(items, 'focus_5').unlocked, isTrue);
      expect(_achievementById(items, 'focus_10').unlocked, isFalse);
      expect(_achievementById(items, 'task_10').unlocked, isTrue);
      expect(_achievementById(items, 'task_25').unlocked, isFalse);
    });

    test('combo achievements unlock from local-day and linked task rules', () {
      final dayOne = DateTime(2026, 5, 1, 10);
      final dayTwo = DateTime(2026, 5, 2, 10);
      final dayThree = DateTime(2026, 5, 3, 10);
      final dayFour = DateTime(2026, 5, 4, 10);

      final items = evaluateAchievements(
        completions: [
          _achievementCompletion('day-one-task', dayOne, taskId: 'task-a'),
          for (var index = 0; index < 3; index++)
            _achievementCompletion(
              'day-two-task-$index',
              dayTwo,
              taskId: 'task-b-$index',
            ),
          _achievementCompletion(
            'linked-task',
            dayFour.add(const Duration(hours: 2)),
            taskId: 'linked',
          ),
        ],
        intervals: [
          _achievementInterval('day-one-work', dayOne),
          for (var index = 0; index < 3; index++)
            _achievementInterval('day-two-work-$index', dayTwo),
          for (var index = 0; index < 5; index++)
            _achievementInterval('day-three-work-$index', dayThree),
          _achievementInterval(
            'linked-work',
            dayFour,
            taskId: 'linked',
            completedAt: dayFour.add(const Duration(minutes: 25)),
          ),
        ],
      );

      expect(_achievementById(items, 'combo_day_not_wasted').unlocked, isTrue);
      expect(
        _achievementById(items, 'combo_focus_plus_check').unlocked,
        isTrue,
      );
      expect(_achievementById(items, 'combo_no_fuss').unlocked, isTrue);
      expect(_achievementById(items, 'combo_clean_entry').unlocked, isTrue);
      expect(
        _achievementById(items, 'combo_tomato_closed_question').unlocked,
        isTrue,
      );
    });

    test('no fuss combo requires zero stopped intervals that day', () {
      final day = DateTime(2026, 5, 1, 10);
      final items = evaluateAchievements(
        completions: const [],
        intervals: [
          for (var index = 0; index < 5; index++)
            _achievementInterval('work-$index', day),
          _achievementInterval('stopped', day, status: 'stopped'),
        ],
      );

      expect(_achievementById(items, 'combo_no_fuss').unlocked, isFalse);
    });

    test(
      'prefs baseline suppresses old unlocks and future unlocks once',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftAchievementRepository(
          db,
          SharedPreferences.getInstance,
        );
        final now = DateTime(2026, 5, 1, 10);
        final baselineItems = evaluateAchievements(
          completions: [_achievementCompletion('old-task', now)],
          intervals: [_achievementInterval('old-work', now)],
        );

        final firstPending = await repository.takePendingAnnouncements(
          baselineItems,
        );

        expect(firstPending, isEmpty);

        final futureItems = evaluateAchievements(
          completions: [
            for (var index = 0; index < 5; index++)
              _achievementCompletion('task-$index', now, taskId: 't$index'),
          ],
          intervals: [_achievementInterval('old-work', now)],
        );

        final secondPending = await repository.takePendingAnnouncements(
          futureItems,
        );
        final thirdPending = await repository.takePendingAnnouncements(
          futureItems,
        );

        expect(secondPending.map((item) => item.id), ['task_5']);
        expect(thirdPending, isEmpty);
      },
    );
  });

  group('pomodoist task retention', () {
    test('local or Supabase paid entitlement disables task history cutoff', () {
      final now = DateTime.utc(2026, 7, 7);
      final freeOverview = AccountOverview(
        profile: const AccountProfile(id: 'free'),
        apps: const [
          AccountAppSummary(
            id: AccountAppId.pomodoist,
            displayName: 'Pomodoist',
          ),
        ],
        generatedAt: now,
      );
      final paidOverview = AccountOverview(
        profile: const AccountProfile(id: 'paid'),
        apps: const [
          AccountAppSummary(
            id: AccountAppId.pomodoist,
            displayName: 'Pomodoist',
            entitlements: [
              AccountEntitlement(
                appId: AccountAppId.pomodoist,
                entitlementId: 'pomodoist_plus',
                status: 'active',
                purchaseType: 'lifetime',
                source: 'revenuecat',
              ),
            ],
          ),
        ],
        generatedAt: now,
      );

      expect(
        pomodoistTaskHistoryCutoff(freeOverview, now: now),
        now.subtract(pomodoistFreeTaskHistoryRetention),
      );
      expect(pomodoistTaskHistoryCutoff(paidOverview, now: now), isNull);
      expect(
        activePomodoistPaidEntitlement(paidOverview, now: now)?.source,
        'revenuecat',
      );
      expect(
        pomodoistTaskHistoryCutoff(
          freeOverview,
          now: now,
          hasLocalPaidEntitlement: true,
        ),
        isNull,
      );
    });

    test('only active Pomodoist paid entitlements grant retention', () {
      final now = DateTime.utc(2026, 7, 7);
      for (final fixture in [
        (
          appId: AccountAppId.pomodoist,
          status: 'active',
          purchaseType: 'lifetime',
          validUntil: null,
          expected: true,
        ),
        (
          appId: AccountAppId.pomodoist,
          status: 'active',
          purchaseType: 'subscription',
          validUntil: now.add(const Duration(days: 1)),
          expected: true,
        ),
        (
          appId: AccountAppId.pomodoist,
          status: 'expired',
          purchaseType: 'subscription',
          validUntil: now.subtract(const Duration(days: 1)),
          expected: false,
        ),
        (
          appId: AccountAppId.pomodoist,
          status: 'revoked',
          purchaseType: 'lifetime',
          validUntil: null,
          expected: false,
        ),
        (
          appId: AccountAppId.nottica,
          status: 'active',
          purchaseType: 'lifetime',
          validUntil: null,
          expected: false,
        ),
      ]) {
        final overview = AccountOverview(
          profile: const AccountProfile(id: 'user'),
          apps: [
            AccountAppSummary(
              id: fixture.appId,
              displayName: fixture.appId,
              entitlements: [
                AccountEntitlement(
                  appId: fixture.appId,
                  entitlementId: 'fixture',
                  status: fixture.status,
                  purchaseType: fixture.purchaseType,
                  source: 'manual',
                  validUntil: fixture.validUntil,
                ),
              ],
            ),
          ],
          generatedAt: now,
        );
        expect(
          hasActivePomodoistPaidEntitlement(overview, now: now),
          fixture.expected,
        );
      }
    });
  });

  group('reengagement notifications', () {
    test('preference defaults to enabled', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          notificationSchedulerProvider.overrideWithValue(
            _FakeReengagementNotificationScheduler(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(reengagementNotificationsEnabledProvider), isTrue);

      await container.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(reengagementNotificationsEnabledProvider), isTrue);
    });

    test('disabled preference persists and cancels reminder', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = _FakeReengagementNotificationScheduler();
      final container = ProviderContainer(
        overrides: [notificationSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);

      await container
          .read(reengagementNotificationsEnabledProvider.notifier)
          .setEnabled(false);
      final prefs = await SharedPreferences.getInstance();

      expect(
        prefs.getBool(reengagementNotificationsEnabledPreferenceKey),
        isFalse,
      );
      expect(scheduler.cancelReengagementCount, 1);
    });

    test('next reminder chooses today or tomorrow at 20:30', () {
      expect(
        nextReengagementReminderAt(
          now: DateTime(2026, 5, 1, 19),
          hasProgressToday: false,
        ),
        DateTime(2026, 5, 1, 20, 30),
      );
      expect(
        nextReengagementReminderAt(
          now: DateTime(2026, 5, 1, 21),
          hasProgressToday: false,
        ),
        DateTime(2026, 5, 2, 20, 30),
      );
      expect(
        nextReengagementReminderAt(
          now: DateTime(2026, 5, 1, 19),
          hasProgressToday: true,
        ),
        DateTime(2026, 5, 2, 20, 30),
      );
    });

    test(
      'coordinator schedules when enabled and cancels when disabled',
      () async {
        final scheduler = _FakeReengagementNotificationScheduler();

        await syncReengagementReminder(
          enabled: true,
          summary: _productivitySummary(completedTasks: 0),
          now: DateTime(2026, 5, 1, 19),
          language: AppLanguage.en,
          scheduler: scheduler,
        );

        expect(scheduler.permissionRequestCount, 1);
        expect(scheduler.scheduledReengagementAt, DateTime(2026, 5, 1, 20, 30));
        expect(scheduler.scheduledReengagementTitle, 'Your tomato misses you');

        await syncReengagementReminder(
          enabled: false,
          summary: _productivitySummary(completedTasks: 0),
          now: DateTime(2026, 5, 1, 19),
          language: AppLanguage.en,
          scheduler: scheduler,
        );

        expect(scheduler.cancelReengagementCount, 1);
      },
    );

    test('coordinator schedules tomorrow after progress today', () async {
      final scheduler = _FakeReengagementNotificationScheduler();

      await syncReengagementReminder(
        enabled: true,
        summary: _productivitySummary(completedFocusIntervals: 1),
        now: DateTime(2026, 5, 1, 19),
        language: AppLanguage.ru,
        scheduler: scheduler,
      );

      expect(scheduler.scheduledReengagementAt, DateTime(2026, 5, 2, 20, 30));
      expect(scheduler.scheduledReengagementTitle, 'Помидор скучает');
    });

    test(
      'task start sync schedules future timed tasks and cancels stale',
      () async {
        final scheduler = _FakeReengagementNotificationScheduler()
          ..pendingTaskStarts = {'stale-task', 'future-task'};
        final now = DateTime(2026, 5, 1, 9);

        await syncTaskStartNotifications(
          tasks: [
            _notificationTask(
              id: 'future-task',
              content: 'Future',
              schedule: TaskSchedule.timed(
                start: DateTime(2026, 5, 1, 10),
                end: DateTime(2026, 5, 1, 11),
              ),
            ),
            _notificationTask(
              id: 'all-day-task',
              content: 'All day',
              schedule: TaskSchedule.allDay(DateTime(2026, 5, 1)),
            ),
            _notificationTask(
              id: 'past-task',
              content: 'Past',
              schedule: TaskSchedule.timed(
                start: DateTime(2026, 5, 1, 8),
                end: DateTime(2026, 5, 1, 9),
              ),
            ),
          ],
          now: now,
          language: AppLanguage.en,
          scheduler: scheduler,
        );

        expect(scheduler.permissionRequestCount, 1);
        expect(
          scheduler.scheduledTaskStarts['future-task'],
          DateTime(2026, 5, 1, 10).toUtc(),
        );
        expect(scheduler.scheduledTaskStarts, isNot(contains('all-day-task')));
        expect(scheduler.scheduledTaskStarts, isNot(contains('past-task')));
        expect(scheduler.canceledTaskStarts, ['stale-task']);
      },
    );
  });

  group('quick add settings', () {
    test(
      'default timed block duration persists and ignores invalid values',
      () async {
        SharedPreferences.setMockInitialValues({
          quickAddDefaultTimedBlockMinutesPreferenceKey: 45,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          container.read(quickAddDefaultTimedBlockMinutesProvider),
          defaultQuickAddTimedBlockMinutes,
        );

        await container.read(sharedPreferencesProvider.future);
        await Future<void>.delayed(Duration.zero);

        expect(container.read(quickAddDefaultTimedBlockMinutesProvider), 45);

        await container
            .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
            .setMinutes(90);
        final prefs = await SharedPreferences.getInstance();

        expect(prefs.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey), 90);

        await container
            .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
            .setMinutes(maxQuickAddTimedBlockMinutes + 1);

        expect(container.read(quickAddDefaultTimedBlockMinutesProvider), 90);
        expect(prefs.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey), 90);
      },
    );

    test('invalid stored default timed block duration falls back', () async {
      SharedPreferences.setMockInitialValues({
        quickAddDefaultTimedBlockMinutesPreferenceKey:
            maxQuickAddTimedBlockMinutes + 1,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(quickAddDefaultTimedBlockMinutesProvider),
        defaultQuickAddTimedBlockMinutes,
      );
    });
  });

  group('drift repositories', () {
    late AppDatabase db;
    late DriftSyncQueueRepository syncQueue;
    late DriftTaskRepository taskRepository;
    late DriftProjectRepository projectRepository;
    late DriftLabelRepository labelRepository;
    late DriftFocusRepository focusRepository;
    late KanbanTransitionCoordinator kanbanTransitions;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      syncQueue = DriftSyncQueueRepository(db);
      kanbanTransitions = KanbanTransitionCoordinator(db, syncQueue);
      taskRepository = DriftTaskRepository(
        db,
        syncQueue,
        kanbanTransitions: kanbanTransitions,
      );
      projectRepository = DriftProjectRepository(db, syncQueue);
      labelRepository = DriftLabelRepository(db, syncQueue);
      focusRepository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        kanbanTransitions: kanbanTransitions,
      );
    });

    tearDown(() => db.close());

    test('quick add creates project, task, label, and sync commands', () async {
      final service = QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: taskRepository,
        projectRepository: projectRepository,
      );

      final taskId = await service.createTask(
        'Подготовить релиз today p1 #Work @coding 4p',
      );
      final task = await taskRepository.watchTask(taskId).first;
      final commands = await syncQueue.watchPending().first;

      expect(task, isNotNull);
      expect(task!.content, 'Подготовить релиз');
      expect(task.priority, 1);
      expect(task.estimatedFocusIntervals, 4);
      expect(commands.map((command) => command.type), contains('task.create'));
      expect(
        commands.map((command) => command.type),
        contains('project.create'),
      );
      expect(commands.map((command) => command.type), contains('label.create'));
    });

    test(
      'task updates append labels without duplicating their relations',
      () async {
        final existingLabelId = await labelRepository.createLabel('existing');
        final taskId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Task with edited labels'),
        );

        const patch = UpdateTaskPatch(labelNames: ['existing', 'new']);
        await taskRepository.updateTask(taskId, patch);
        await taskRepository.updateTask(taskId, patch);

        final labels = await db.select(db.labels).get();
        final taskLabels = await (db.select(
          db.taskLabels,
        )..where((row) => row.taskId.equals(taskId))).get();
        final userTaskLabels = taskLabels
            .where((row) => row.kind == labelKindUser)
            .toList();

        expect(labels.where((label) => label.name == 'new'), hasLength(1));
        expect(userTaskLabels.map((row) => row.labelId).toSet(), {
          existingLabelId,
          labels.singleWhere((label) => label.name == 'new').id,
        });
        expect(userTaskLabels, hasLength(2));
      },
    );

    test('projects assign update and sync palette colors', () async {
      final automaticId = await projectRepository.createProject('Automatic');
      final explicitId = await projectRepository.createProject(
        'Explicit',
        color: projectColorPalette[4],
      );

      var projects = await projectRepository.watchProjects().first;
      final automatic = projects.singleWhere(
        (project) => project.id == automaticId,
      );
      final explicit = projects.singleWhere(
        (project) => project.id == explicitId,
      );
      expect(automatic.color, projectColorPalette.first);
      expect(explicit.color, projectColorPalette[4]);

      await projectRepository.updateProject(
        automaticId,
        UpdateProjectPatch(color: projectColorPalette[7], isFavorite: true),
      );

      projects = await projectRepository.watchProjects().first;
      final updated = projects.singleWhere(
        (project) => project.id == automaticId,
      );
      expect(updated.color, projectColorPalette[7]);
      expect(updated.isFavorite, isTrue);

      final commands = await syncQueue.watchPending().first;
      final payload = _payloadFor(commands, 'project.update', automaticId);
      expect(payload['color'], projectColorPalette[7]);
      expect(payload['isFavorite'], isTrue);
      await expectLater(
        projectRepository.updateProject(
          inboxProjectId,
          UpdateProjectPatch(color: projectColorPalette[1]),
        ),
        throwsArgumentError,
      );
    });

    test('project rename trims the name and syncs it', () async {
      final projectId = await projectRepository.createProject('Original');

      await projectRepository.updateProject(
        projectId,
        const UpdateProjectPatch(name: '  Renamed  '),
      );

      final projects = await projectRepository.watchProjects().first;
      expect(
        projects.singleWhere((project) => project.id == projectId).name,
        'Renamed',
      );
      final commands = await syncQueue.watchPending().first;
      expect(
        _payloadFor(commands, 'project.update', projectId)['name'],
        'Renamed',
      );
    });

    test(
      'project rename rejects duplicates without queuing an update',
      () async {
        final projectId = await projectRepository.createProject('Original');
        await projectRepository.createProject('Existing');
        final pendingBefore = await syncQueue.watchPending().first;

        await expectLater(
          projectRepository.updateProject(
            projectId,
            const UpdateProjectPatch(name: ' existing '),
          ),
          throwsArgumentError,
        );

        final projects = await projectRepository.watchProjects().first;
        expect(
          projects.singleWhere((project) => project.id == projectId).name,
          'Original',
        );
        expect(
          (await syncQueue.watchPending().first).length,
          pendingBefore.length,
        );
      },
    );

    test('places a task branch on the timeline atomically', () async {
      final targetProjectId = await projectRepository.createProject('Target');
      final externalParentId = await taskRepository.createTask(
        const CreateTaskInput(content: 'External parent'),
      );
      final rootId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Move root',
          parentId: externalParentId,
          sectionId: 'old-root-section',
          schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
        ),
      );
      final childSchedule = TaskSchedule.timed(
        start: DateTime(2026, 7, 9, 8),
        end: DateTime(2026, 7, 9, 8, 30),
      );
      final childId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Move child',
          parentId: rootId,
          sectionId: 'old-child-section',
          schedule: childSchedule,
        ),
      );
      final targetSchedule = TaskSchedule.timed(
        start: DateTime(2026, 7, 9, 14),
        end: DateTime(2026, 7, 9, 14, 45),
      );

      await taskRepository.placeTaskOnTimeline(
        rootId,
        schedule: targetSchedule,
        projectId: targetProjectId,
      );

      final root = await taskRepository.watchTask(rootId).first;
      final child = await taskRepository.watchTask(childId).first;
      expect(root!.projectId, targetProjectId);
      expect(root.sectionId, isNull);
      expect(root.parentId, isNull);
      expect(root.schedule, targetSchedule);
      expect(child!.projectId, targetProjectId);
      expect(child.sectionId, isNull);
      expect(child.parentId, rootId);
      expect(child.schedule, childSchedule);

      final commands = await syncQueue.watchPending().first;
      expect(
        commands
            .where((command) => command.type == 'task.move')
            .map((command) => command.clientId),
        containsAll([rootId, childId]),
      );
      expect(
        commands.where(
          (command) =>
              command.type == 'task.update' && command.clientId == rootId,
        ),
        isNotEmpty,
      );
    });

    test(
      'timeline placement keeps a parent already in the target project',
      () async {
        final targetProjectId = await projectRepository.createProject('Target');
        final targetParentId = await taskRepository.createTask(
          CreateTaskInput(content: 'Target parent', projectId: targetProjectId),
        );
        final rootId = await taskRepository.createTask(
          CreateTaskInput(
            content: 'Move root',
            parentId: targetParentId,
            schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
          ),
        );
        final targetSchedule = TaskSchedule.timed(
          start: DateTime(2026, 7, 9, 14),
          end: DateTime(2026, 7, 9, 14, 30),
        );

        await taskRepository.placeTaskOnTimeline(
          rootId,
          schedule: targetSchedule,
          projectId: targetProjectId,
        );

        final root = await taskRepository.watchTask(rootId).first;
        expect(root!.parentId, targetParentId);
        expect(root.projectId, targetProjectId);
        expect(root.schedule, targetSchedule);
      },
    );

    test(
      'quick add default priority yields to explicit priority token',
      () async {
        final service = QuickAddService(
          parser: const QuickAddParser(),
          taskRepository: taskRepository,
          projectRepository: projectRepository,
        );

        final defaultPriorityId = await service.createTask(
          'Default matrix task',
          priority: 2,
        );
        final explicitPriorityId = await service.createTask(
          'Explicit matrix task p1',
          priority: 3,
        );

        final defaultPriority = await taskRepository
            .watchTask(defaultPriorityId)
            .first;
        final explicitPriority = await taskRepository
            .watchTask(explicitPriorityId)
            .first;

        expect(defaultPriority!.priority, 2);
        expect(explicitPriority!.priority, 1);
      },
    );

    test('quick add default schedule yields to explicit schedule', () async {
      final service = QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: taskRepository,
        projectRepository: projectRepository,
      );
      final defaultSchedule = TaskSchedule.timed(
        start: DateTime(2026, 5, 4, 10),
        end: DateTime(2026, 5, 4, 10, 30),
      );

      final defaultScheduleId = await service.createTask(
        'Timeline default slot task',
        defaultSchedule: defaultSchedule,
      );
      final explicitScheduleId = await service.createTask(
        'Timeline explicit task today 18:00',
        defaultSchedule: defaultSchedule,
      );

      final defaultTask = await taskRepository
          .watchTask(defaultScheduleId)
          .first;
      final explicitTask = await taskRepository
          .watchTask(explicitScheduleId)
          .first;

      expect(defaultTask!.schedule!.start!.toLocal(), DateTime(2026, 5, 4, 10));
      expect(defaultTask.schedule!.duration, const Duration(minutes: 30));
      expect(explicitTask!.schedule!.start!.toLocal().hour, 18);
      expect(explicitTask.schedule!.start!.toLocal().minute, 0);
    });

    test(
      'quick add forwards default date through both creation APIs',
      () async {
        final service = QuickAddService(
          parser: const QuickAddParser(),
          taskRepository: taskRepository,
          projectRepository: projectRepository,
        );
        final defaultDate = DateTime(2026, 5, 5, 18);

        final allDayId = await service.createTask(
          'Contextual all-day task',
          defaultDate: defaultDate,
        );
        final timedContext = await service.createTaskWithContext(
          'Contextual timed task 09:15',
          defaultDate: defaultDate,
        );

        final allDay = await taskRepository.watchTask(allDayId).first;
        final timed = await taskRepository.watchTask(timedContext.id).first;
        expect(allDay!.schedule!.isAllDay, isTrue);
        expect(allDay.schedule!.displayDate, DateTime(2026, 5, 5));
        expect(timed!.schedule!.start!.toLocal(), DateTime(2026, 5, 5, 9, 15));
      },
    );

    test(
      'quick add schedule precedence is explicit then date then schedule',
      () async {
        final service = QuickAddService(
          parser: const QuickAddParser(),
          taskRepository: taskRepository,
          projectRepository: projectRepository,
        );
        final defaultSchedule = TaskSchedule.timed(
          start: DateTime(2026, 5, 4, 10),
          end: DateTime(2026, 5, 4, 10, 30),
        );
        final defaultDate = DateTime(2026, 5, 5);

        final scheduleOnlyId = await service.createTask(
          'Default schedule task',
          defaultSchedule: defaultSchedule,
        );
        final contextualId = await service.createTask(
          'Contextual date task',
          defaultDate: defaultDate,
          defaultSchedule: defaultSchedule,
        );
        final explicitId = await service.createTask(
          'Explicit date task 2026-05-06 11:00',
          defaultDate: defaultDate,
          defaultSchedule: defaultSchedule,
        );

        final scheduleOnly = await taskRepository
            .watchTask(scheduleOnlyId)
            .first;
        final contextual = await taskRepository.watchTask(contextualId).first;
        final explicit = await taskRepository.watchTask(explicitId).first;
        expect(scheduleOnly!.schedule, defaultSchedule);
        expect(contextual!.schedule!.isAllDay, isTrue);
        expect(contextual.schedule!.displayDate, defaultDate);
        expect(explicit!.schedule!.start!.toLocal(), DateTime(2026, 5, 6, 11));
      },
    );

    test(
      'deleting a project moves its tasks to inbox and syncs delete',
      () async {
        final projectId = await projectRepository.createProject('Delete me');
        final taskId = await taskRepository.createTask(
          CreateTaskInput(
            content: 'Move me',
            projectId: projectId,
            sectionId: 'section-1',
          ),
        );

        await projectRepository.deleteProject(projectId);

        final projects = await projectRepository.watchProjects().first;
        final task = await taskRepository.watchTask(taskId).first;
        final commands = await syncQueue.watchPending().first;
        final movePayload = _payloadFor(commands, 'task.move', taskId);

        expect(
          projects.map((project) => project.id),
          isNot(contains(projectId)),
        );
        expect(task!.projectId, inboxProjectId);
        expect(task.sectionId, isNull);
        expect(movePayload['projectId'], inboxProjectId);
        expect(movePayload['sectionId'], isNull);
        expect(
          commands.where((command) => command.type == 'project.delete'),
          isNotEmpty,
        );
        final replacementProjectId = await projectRepository.createProject(
          'Delete me',
        );
        expect(replacementProjectId, isNot(projectId));
      },
    );

    test('deleting a label hides it and syncs delete', () async {
      final labelId = await labelRepository.createLabel('obsolete');

      await labelRepository.deleteLabel(labelId);

      final labels = await labelRepository.watchLabels().first;
      final commands = await syncQueue.watchPending().first;

      expect(labels.map((label) => label.id), isNot(contains(labelId)));
      expect(
        commands.where((command) => command.type == 'label.delete'),
        isNotEmpty,
      );
      final replacementLabelId = await labelRepository.createLabel('obsolete');
      expect(replacementLabelId, isNot(labelId));
    });

    test('quick add estimates timed tasks from the focus preset', () async {
      final service = QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: taskRepository,
        projectRepository: projectRepository,
        focusPreset: _testPreset(
          id: defaultPresetId,
          workMinutes: 25,
          shortBreakMinutes: 5,
          longBreakMinutes: 15,
        ),
      );

      final taskId = await service.createTask('Планирование today 10:00 1h');
      final task = await taskRepository.watchTask(taskId).first;

      expect(task!.durationSeconds, 60 * 60);
      expect(task.estimatedFocusIntervals, 2);
    });

    test('quick add uses default timed block duration', () async {
      final service = QuickAddService(
        parser: const QuickAddParser(
          defaultTimedBlockDuration: Duration(minutes: 45),
        ),
        taskRepository: taskRepository,
        projectRepository: projectRepository,
      );

      final taskId = await service.createTask('Планирование today 10:00');
      final task = await taskRepository.watchTask(taskId).first;

      expect(task!.durationSeconds, 45 * 60);
    });

    test(
      'quick add can create subtasks with inherited project and section',
      () async {
        final service = QuickAddService(
          parser: const QuickAddParser(),
          taskRepository: taskRepository,
          projectRepository: projectRepository,
        );

        final childId = await service.createTask(
          'Написать бриф tomorrow p1 @research',
          parentId: 'parent-1',
          projectId: 'project-1',
          sectionId: 'section-1',
        );
        final explicitProjectId = await service.createTask(
          'Заказать мерч #Marketing',
          parentId: 'parent-1',
          projectId: 'project-1',
          sectionId: 'section-1',
        );

        final child = await taskRepository.watchTask(childId).first;
        final explicitProject = await taskRepository
            .watchTask(explicitProjectId)
            .first;

        expect(child!.parentId, 'parent-1');
        expect(child.projectId, 'project-1');
        expect(child.sectionId, 'section-1');
        expect(child.priority, 1);
        expect(child.dueDate, isNotNull);
        expect(explicitProject!.parentId, 'parent-1');
        expect(explicitProject.projectId, isNot('project-1'));
        expect(explicitProject.sectionId, isNull);
      },
    );

    test('task descriptions create update sync and clear', () async {
      final taskId = await taskRepository.createTask(
        const CreateTaskInput(
          content: 'Task with comment',
          description: 'Initial comment',
        ),
      );

      var task = await taskRepository.watchTask(taskId).first;
      expect(task!.description, 'Initial comment');

      await taskRepository.updateTask(
        taskId,
        const UpdateTaskPatch(
          description: 'Updated comment',
          updateDescription: true,
        ),
      );
      task = await taskRepository.watchTask(taskId).first;
      expect(task!.description, 'Updated comment');

      await taskRepository.updateTask(
        taskId,
        const UpdateTaskPatch(updateDescription: true),
      );
      task = await taskRepository.watchTask(taskId).first;
      expect(task!.description, isNull);

      final commands = await syncQueue.watchPending().first;
      final createPayload = _payloadFor(commands, 'task.create', taskId);
      final updatePayloads = commands
          .where(
            (command) =>
                command.type == 'task.update' && command.clientId == taskId,
          )
          .map(
            (command) => Map<String, Object?>.from(
              jsonDecode(command.payloadJson) as Map,
            ),
          )
          .toList();

      expect(createPayload['description'], 'Initial comment');
      expect(updatePayloads.first['description'], 'Updated comment');
      expect(updatePayloads.last.containsKey('description'), isTrue);
      expect(updatePayloads.last['description'], isNull);
    });

    test(
      'moves tasks into parents and keeps subtree project in sync',
      () async {
        final projectId = await projectRepository.createProject('Work');
        final parentId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Parent task'),
        );
        final childId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Child task'),
        );
        final grandchildId = await taskRepository.createTask(
          CreateTaskInput(content: 'Grandchild task', parentId: childId),
        );

        await taskRepository.moveTask(
          childId,
          projectId: projectId,
          clearSectionId: true,
          parentId: parentId,
          orderKey: '999',
        );

        final child = await taskRepository.watchTask(childId).first;
        final grandchild = await taskRepository.watchTask(grandchildId).first;
        final commands = await syncQueue.watchPending().first;

        expect(child!.parentId, parentId);
        expect(child.projectId, projectId);
        expect(child.orderKey, '999');
        expect(grandchild!.parentId, childId);
        expect(grandchild.projectId, projectId);
        expect(
          commands
              .where((command) => command.type == 'task.move')
              .map((command) => command.clientId),
          containsAll([childId, grandchildId]),
        );
        await expectLater(
          taskRepository.moveTask(parentId, parentId: grandchildId),
          throwsArgumentError,
        );
      },
    );

    test('updates collapse state and cascades completion lifecycle', () async {
      final parentId = await taskRepository.createTask(
        const CreateTaskInput(content: 'Parent lifecycle'),
      );
      final childId = await taskRepository.createTask(
        CreateTaskInput(content: 'Child lifecycle', parentId: parentId),
      );
      final grandchildId = await taskRepository.createTask(
        CreateTaskInput(content: 'Grandchild lifecycle', parentId: childId),
      );

      await taskRepository.updateTask(
        parentId,
        const UpdateTaskPatch(isCollapsed: true),
      );
      expect(
        (await taskRepository.watchTask(parentId).first)!.isCollapsed,
        true,
      );

      await taskRepository.completeTask(parentId);
      expect(
        (await taskRepository.watchTask(parentId).first)!.isCompleted,
        true,
      );
      expect(
        (await taskRepository.watchTask(childId).first)!.isCompleted,
        true,
      );
      expect(
        (await taskRepository.watchTask(grandchildId).first)!.isCompleted,
        true,
      );

      await taskRepository.uncompleteTask(parentId);
      expect(
        (await taskRepository.watchTask(parentId).first)!.isCompleted,
        false,
      );
      expect(
        (await taskRepository.watchTask(childId).first)!.isCompleted,
        false,
      );
      expect(
        (await taskRepository.watchTask(grandchildId).first)!.isCompleted,
        false,
      );

      await taskRepository.deleteTask(parentId);
      final openIds =
          (await taskRepository.watchTasks(const TaskQuery.all()).first).map(
            (task) => task.id,
          );
      expect(openIds, isNot(contains(parentId)));
      expect(openIds, isNot(contains(childId)));
      expect(openIds, isNot(contains(grandchildId)));
    });

    test('day query returns only open tasks scheduled for that date', () async {
      final selectedDay = DateTime(2026, 5, 4);
      final allDayId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'All-day selected',
          schedule: TaskSchedule.allDay(selectedDay),
        ),
      );
      final timedId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Timed selected',
          schedule: TaskSchedule.timed(
            start: DateTime(2026, 5, 4, 10),
            end: DateTime(2026, 5, 4, 11),
          ),
        ),
      );
      final otherDayId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Other day',
          schedule: TaskSchedule.allDay(
            selectedDay.add(const Duration(days: 1)),
          ),
        ),
      );
      final completedId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Completed selected',
          schedule: TaskSchedule.allDay(selectedDay),
        ),
      );
      final deletedId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Deleted selected',
          schedule: TaskSchedule.allDay(selectedDay),
        ),
      );

      await taskRepository.completeTask(completedId);
      await taskRepository.deleteTask(deletedId);

      final tasks = await taskRepository
          .watchTasks(TaskQuery.day(selectedDay))
          .first;

      final taskIds = tasks.map((task) => task.id);
      expect(taskIds, hasLength(2));
      expect(taskIds, containsAll([allDayId, timedId]));
      expect(taskIds, isNot(contains(otherDayId)));
      expect(taskIds, isNot(contains(completedId)));
      expect(taskIds, isNot(contains(deletedId)));
    });

    test('materializes due recurring task subtree once', () async {
      final rootId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Daily root',
          labelNames: const ['habit'],
          schedule: TaskSchedule.timed(
            start: DateTime(2026, 7, 1, 10),
            end: DateTime(2026, 7, 1, 11),
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.day,
              seriesId: 'daily-series',
            ),
          ),
        ),
      );
      final childId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Daily child',
          parentId: rootId,
          labelNames: const ['child'],
          schedule: TaskSchedule.allDay(DateTime(2026, 7, 1)),
        ),
      );

      await taskRepository.materializeDueRecurringTasks(
        now: DateTime(2026, 7, 2, 9),
      );

      final oldRoot = await taskRepository.watchTask(rootId).first;
      final oldChild = await taskRepository.watchTask(childId).first;
      final tasks = await taskRepository
          .watchTasks(const TaskQuery.all())
          .first;
      final newRoot = tasks.singleWhere(
        (task) => task.content == 'Daily root' && task.id != rootId,
      );
      final newChild = tasks.singleWhere(
        (task) => task.content == 'Daily child' && task.id != childId,
      );

      expect(oldRoot!.schedule!.recurrence, isNull);
      expect(oldRoot.schedule!.recurrenceSeriesId, 'daily-series');
      expect(oldChild!.parentId, rootId);
      expect(newRoot.schedule!.recurrence, isNotNull);
      expect(newRoot.schedule!.start!.toLocal(), DateTime(2026, 7, 2, 10));
      expect(newChild.parentId, newRoot.id);
      expect(newChild.schedule!.displayDate, DateTime(2026, 7, 2));
      expect(newChild.schedule!.recurrence, isNull);

      final copiedLabels = await (db.select(
        db.taskLabels,
      )..where((label) => label.taskId.isIn([newRoot.id, newChild.id]))).get();
      expect(
        copiedLabels.where((row) => row.kind == labelKindUser),
        hasLength(2),
      );
      expect(
        copiedLabels.where((row) => row.kind == labelKindKanbanStatus),
        hasLength(2),
      );

      await taskRepository.materializeDueRecurringTasks(
        now: DateTime(2026, 7, 2, 9),
      );
      expect(
        await (db.select(
          db.tasks,
        )..where((task) => task.isDeleted.equals(false))).get(),
        hasLength(4),
      );
    });

    test(
      'completed future recurring task materializes after its date',
      () async {
        final taskId = await taskRepository.createTask(
          CreateTaskInput(
            content: 'Completed early',
            schedule: TaskSchedule.allDay(
              DateTime(2026, 7, 5),
              recurrence: const TaskRecurrence(
                interval: 1,
                unit: TaskRecurrenceUnit.day,
                seriesId: 'early-series',
              ),
            ),
          ),
        );
        await taskRepository.completeTask(taskId);

        await taskRepository.materializeDueRecurringTasks(
          now: DateTime(2026, 7, 1, 9),
        );

        final tasks = await taskRepository
            .watchTasks(const TaskQuery.all())
            .first;
        final next = tasks.singleWhere(
          (task) => task.content == 'Completed early',
        );

        expect(next.schedule!.displayDate, DateTime(2026, 7, 6));
        expect(next.schedule!.recurrence, isNotNull);
        expect(
          (await taskRepository.watchTask(taskId).first)!.schedule!.recurrence,
          isNull,
        );
      },
    );

    test('delete only recurring occurrence creates next copy first', () async {
      final taskId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Delete one',
          schedule: TaskSchedule.allDay(
            DateTime(2030, 1, 1),
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.day,
              seriesId: 'delete-one-series',
            ),
          ),
        ),
      );

      await taskRepository.deleteRecurringOccurrence(
        taskId,
        includeFollowing: false,
      );

      expect((await taskRepository.watchTask(taskId).first)!.isDeleted, isTrue);
      final tasks = await taskRepository
          .watchTasks(const TaskQuery.all())
          .first;
      final next = tasks.singleWhere((task) => task.content == 'Delete one');
      expect(next.id, isNot(taskId));
      expect(next.schedule!.displayDate, DateTime(2030, 1, 2));
      expect(next.schedule!.recurrence, isNotNull);
    });

    test('delete following recurring occurrences keeps earlier ones', () async {
      final previousId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Previous occurrence',
          schedule: TaskSchedule.allDay(
            DateTime(2029, 12, 31),
            recurrenceSeriesId: 'delete-following-series',
          ),
        ),
      );
      final selectedId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Selected occurrence',
          schedule: TaskSchedule.allDay(
            DateTime(2030, 1, 1),
            recurrenceSeriesId: 'delete-following-series',
          ),
        ),
      );
      final futureId = await taskRepository.createTask(
        CreateTaskInput(
          content: 'Future occurrence',
          schedule: TaskSchedule.allDay(
            DateTime(2030, 1, 2),
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.day,
              seriesId: 'delete-following-series',
            ),
          ),
        ),
      );
      final childId = await taskRepository.createTask(
        CreateTaskInput(content: 'Future child', parentId: futureId),
      );
      await taskRepository.completeTask(futureId);

      await taskRepository.deleteRecurringOccurrence(
        selectedId,
        includeFollowing: true,
      );

      expect(
        (await taskRepository.watchTask(previousId).first)!.isDeleted,
        isFalse,
      );
      expect(
        (await taskRepository.watchTask(selectedId).first)!.isDeleted,
        isTrue,
      );
      expect(
        (await taskRepository.watchTask(futureId).first)!.isDeleted,
        isTrue,
      );
      expect(
        (await taskRepository.watchTask(childId).first)!.isDeleted,
        isTrue,
      );

      await taskRepository.deleteRecurringOccurrence(
        selectedId,
        includeFollowing: true,
      );
      expect(
        (await taskRepository.watchTask(previousId).first)!.isDeleted,
        isFalse,
      );
    });

    test('focus interval completion updates task focus aggregates', () async {
      final taskId = await taskRepository.createTask(
        const CreateTaskInput(
          content: 'Write sync engine',
          estimatedFocusIntervals: 2,
        ),
      );

      await focusRepository.startRun(
        StartFocusRunInput(taskId: taskId, targetWorkIntervals: 2),
      );
      await focusRepository.completeActiveInterval();
      final task = await taskRepository.watchTask(taskId).first;
      final activeInterval = await focusRepository.watchActiveInterval().first;

      expect(task!.completedFocusIntervals, 1);
      expect(activeInterval, isNotNull);
      expect(activeInterval!.type, 'shortBreak');
      expect(activeInterval.status, 'ready');
    });

    test(
      'active focus watchers ignore newer orphaned rows and stay paired',
      () async {
        final now = DateTime.utc(2026, 7, 11, 9);

        await db
            .into(db.focusRuns)
            .insert(
              FocusRunsCompanion.insert(
                id: 'coherent-run',
                userId: localUserId,
                presetId: defaultPresetId,
                status: 'active',
                startedAt: now,
                targetWorkIntervals: 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.focusIntervals)
            .insert(
              FocusIntervalsCompanion.insert(
                id: 'coherent-interval',
                runId: 'coherent-run',
                type: 'work',
                status: 'running',
                plannedSeconds: 25 * 60,
                startedAt: now,
                sequenceNumber: 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.focusRuns)
            .insert(
              FocusRunsCompanion.insert(
                id: 'orphan-run',
                userId: localUserId,
                presetId: defaultPresetId,
                status: 'active',
                startedAt: now.add(const Duration(minutes: 1)),
                targetWorkIntervals: 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.focusIntervals)
            .insert(
              FocusIntervalsCompanion.insert(
                id: 'orphan-interval',
                runId: 'missing-run',
                type: 'work',
                status: 'running',
                plannedSeconds: 25 * 60,
                startedAt: now.add(const Duration(minutes: 2)),
                sequenceNumber: 1,
                createdAt: now,
                updatedAt: now,
              ),
            );

        final run = await focusRepository.watchActiveRun().first;
        final interval = await focusRepository.watchActiveInterval().first;

        expect(run?.id, 'coherent-run');
        expect(interval?.id, 'coherent-interval');
        expect(interval?.runId, run?.id);
      },
    );

    test('active focus watchers return null for partial state', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await db
          .into(db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: 'orphan-run',
              userId: localUserId,
              presetId: defaultPresetId,
              status: 'active',
              startedAt: now,
              targetWorkIntervals: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );

      expect(await focusRepository.watchActiveRun().first, isNull);
      expect(await focusRepository.watchActiveInterval().first, isNull);
    });

    test(
      'focus run intervals are ordered by sequence and exclude deleted rows',
      () async {
        final now = DateTime.utc(2026, 5, 1, 10);

        Future<void> insertInterval(
          String id,
          int sequenceNumber, {
          bool isDeleted = false,
        }) {
          return db
              .into(db.focusIntervals)
              .insert(
                FocusIntervalsCompanion.insert(
                  id: id,
                  runId: 'ordered-run',
                  type: 'work',
                  status: 'completed',
                  plannedSeconds: 25 * 60,
                  startedAt: now,
                  sequenceNumber: sequenceNumber,
                  createdAt: now,
                  updatedAt: now,
                  isDeleted: Value(isDeleted),
                ),
              );
        }

        await insertInterval('sequence-3', 3);
        await insertInterval('sequence-1', 1);
        await insertInterval('sequence-2', 2);
        await insertInterval('deleted-sequence-0', 0, isDeleted: true);

        final intervals = await focusRepository
            .watchIntervalsForRun('ordered-run')
            .first;
        final container = ProviderContainer(
          overrides: [
            focusRepositoryProvider.overrideWithValue(focusRepository),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          focusIntervalsForRunProvider('ordered-run'),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final providedIntervals = await container.read(
          focusIntervalsForRunProvider('ordered-run').future,
        );

        expect(intervals.map((interval) => interval.id), [
          'sequence-1',
          'sequence-2',
          'sequence-3',
        ]);
        expect(providedIntervals.map((interval) => interval.id), [
          'sequence-1',
          'sequence-2',
          'sequence-3',
        ]);
      },
    );

    test(
      'linked Focus start moves the task to configured focus status',
      () async {
        final taskId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Focus this task'),
        );
        await db
            .update(db.kanbanSettings)
            .write(
              const KanbanSettingsCompanion(
                focusStatusLabelId: Value(kanbanStatusTodoId),
              ),
            );
        await db.delete(db.syncCommands).go();

        await focusRepository.startRun(
          StartFocusRunInput(taskId: taskId),
          now: DateTime.utc(2026, 7, 10, 9),
        );

        final assignment =
            (await (db.select(
              db.taskLabels,
            )..where((row) => row.taskId.equals(taskId))).get()).singleWhere(
              (row) => row.kind == labelKindKanbanStatus,
            );
        expect(assignment.labelId, kanbanStatusTodoId);
        final commands = await syncQueue.watchPending().first;
        expect(commands.map((command) => command.type), [
          'task.kanbanStatus.set',
        ]);
      },
    );

    test('completed linked Focus rejection preserves the active run', () async {
      final activeRunId = await focusRepository.startRun(
        const StartFocusRunInput(),
        now: DateTime.utc(2026, 7, 10, 8),
      );
      final completedTaskId = await taskRepository.createTask(
        const CreateTaskInput(content: 'Already complete'),
      );
      await taskRepository.completeTask(completedTaskId);

      await expectLater(
        focusRepository.startRun(
          StartFocusRunInput(taskId: completedTaskId),
          now: DateTime.utc(2026, 7, 10, 9),
        ),
        throwsStateError,
      );

      final activeRun = await focusRepository.watchActiveRun().first;
      expect(activeRun?.id, activeRunId);
      expect(
        (await taskRepository.watchTask(completedTaskId).first)?.isCompleted,
        isTrue,
      );
    });
    test('productivity summary includes all-time achievements', () async {
      final repository = DriftProductivityRepository(db);
      final now = DateTime.utc(2026, 5, 1, 10);

      await db
          .into(db.taskCompletions)
          .insert(
            TaskCompletionsCompanion.insert(
              id: 'completion-1',
              taskId: 'task-1',
              userId: localUserId,
              completedAt: now,
              createdAt: now,
            ),
          );
      await db
          .into(db.taskCompletions)
          .insert(
            TaskCompletionsCompanion.insert(
              id: 'completion-2',
              taskId: 'task-2',
              userId: localUserId,
              completedAt: now.add(const Duration(days: 1)),
              createdAt: now,
            ),
          );

      Future<void> insertInterval(
        String id, {
        required String type,
        required String status,
        bool isDeleted = false,
      }) {
        return db
            .into(db.focusIntervals)
            .insert(
              FocusIntervalsCompanion.insert(
                id: id,
                runId: 'run-$id',
                type: type,
                status: status,
                plannedSeconds: 1500,
                startedAt: now,
                completedAt: Value(status == 'completed' ? now : null),
                sequenceNumber: 1,
                createdAt: now,
                updatedAt: now,
                isDeleted: Value(isDeleted),
              ),
            );
      }

      await insertInterval('work-1', type: 'work', status: 'completed');
      await insertInterval('work-2', type: 'work', status: 'completed');
      await insertInterval('break-1', type: 'shortBreak', status: 'completed');
      await insertInterval('stopped-1', type: 'work', status: 'stopped');
      await insertInterval(
        'deleted-1',
        type: 'work',
        status: 'completed',
        isDeleted: true,
      );

      final summary = await repository.watchTodaySummary().first;

      expect(summary.allTimeCompletedTasks, 2);
      expect(summary.allTimeCompletedFocusIntervals, 2);
    });

    test('productivity summary includes last seven days stats', () async {
      final repository = DriftProductivityRepository(db);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final outsideWindow = today.subtract(const Duration(days: 7));

      DateTime noonUtc(DateTime day) {
        return DateTime(day.year, day.month, day.day, 12).toUtc();
      }

      Future<void> insertCompletion(String id, DateTime day) {
        final completedAt = noonUtc(day);
        return db
            .into(db.taskCompletions)
            .insert(
              TaskCompletionsCompanion.insert(
                id: id,
                taskId: 'task-$id',
                userId: localUserId,
                completedAt: completedAt,
                createdAt: completedAt,
              ),
            );
      }

      Future<void> insertInterval(
        String id,
        DateTime day, {
        String type = 'work',
        String status = 'completed',
        bool isDeleted = false,
        int pausedSeconds = 0,
      }) {
        final startedAt = noonUtc(day);
        final completedAt = startedAt.add(const Duration(minutes: 25));
        return db
            .into(db.focusIntervals)
            .insert(
              FocusIntervalsCompanion.insert(
                id: id,
                runId: 'run-$id',
                type: type,
                status: status,
                plannedSeconds: 1500,
                startedAt: startedAt,
                completedAt: Value(status == 'completed' ? completedAt : null),
                pausedTotalSeconds: Value(pausedSeconds),
                sequenceNumber: 1,
                createdAt: startedAt,
                updatedAt: startedAt,
                isDeleted: Value(isDeleted),
              ),
            );
      }

      await insertCompletion('today-1', today);
      await insertCompletion('yesterday-1', yesterday);
      await insertCompletion('yesterday-2', yesterday);
      await insertCompletion('outside-1', outsideWindow);
      await insertInterval('today-work', today);
      await insertInterval('yesterday-work', yesterday, pausedSeconds: 60);
      await insertInterval('break', yesterday, type: 'shortBreak');
      await insertInterval('stopped', yesterday, status: 'stopped');
      await insertInterval('deleted', yesterday, isDeleted: true);
      await insertInterval('outside-work', outsideWindow);

      final summary = await repository.watchTodaySummary().first;
      final yesterdaySummary = summary.lastSevenDays[5];
      final todaySummary = summary.lastSevenDays.last;

      expect(summary.lastSevenDays, hasLength(7));
      expect(todaySummary.localDate, today);
      expect(todaySummary.completedTasks, 1);
      expect(todaySummary.completedFocusIntervals, 1);
      expect(todaySummary.totalFocusSeconds, 1500);
      expect(yesterdaySummary.localDate, yesterday);
      expect(yesterdaySummary.completedTasks, 2);
      expect(yesterdaySummary.completedFocusIntervals, 1);
      expect(yesterdaySummary.totalFocusSeconds, 1440);
    });

    test(
      'final work interval still creates a break before completing run',
      () async {
        await focusRepository.startRun(
          const StartFocusRunInput(
            presetId: defaultPresetId,
            targetWorkIntervals: 1,
          ),
        );

        await focusRepository.completeActiveInterval();

        var run = await focusRepository.watchActiveRun().first;
        var interval = await focusRepository.watchActiveInterval().first;
        expect(run, isNotNull);
        expect(run!.completedWorkIntervals, 1);
        expect(interval, isNotNull);
        expect(interval!.type, 'shortBreak');
        expect(interval.status, 'ready');

        await focusRepository.startReadyInterval();
        await focusRepository.completeActiveInterval();

        run = await focusRepository.watchActiveRun().first;
        interval = await focusRepository.watchActiveInterval().first;
        expect(run, isNull);
        expect(interval, isNull);
      },
    );

    test(
      'final completed break publishes linked run completion details',
      () async {
        final completions = <FocusRunCompletionEvent>[];
        final repository = DriftFocusRepository(
          db,
          syncQueue,
          _NoopNotificationScheduler(),
          kanbanTransitions: kanbanTransitions,
          onRunCompleted: completions.add,
        );
        final taskId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Ship celebration'),
        );
        final completedAt = DateTime.utc(2026, 8, 19, 12);
        final runId = await repository.startRun(
          StartFocusRunInput(
            taskId: taskId,
            presetId: defaultPresetId,
            targetWorkIntervals: 1,
          ),
        );

        await repository.completeActiveInterval();
        expect(completions, isEmpty);

        await repository.startReadyInterval();
        await repository.completeActiveInterval(now: completedAt);
        await repository.completeActiveInterval(now: completedAt);

        expect(completions, hasLength(1));
        expect(completions.single.runId, runId);
        expect(completions.single.taskId, taskId);
        expect(completions.single.taskTitle, 'Ship celebration');
        expect(completions.single.completedWorkIntervals, 1);
        expect(completions.single.targetWorkIntervals, 1);
        expect(completions.single.completedAt, completedAt);
      },
    );

    test('completion callback failures do not fail a committed run', () async {
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        onRunCompleted: (_) => throw StateError('presentation failed'),
      );
      await repository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 1,
        ),
      );
      await repository.completeActiveInterval();
      await repository.startReadyInterval();

      await repository.completeActiveInterval();

      expect(await repository.watchActiveRun().first, isNull);
      expect(await repository.watchActiveInterval().first, isNull);
    });

    test(
      'focus sync queue stays empty until the whole run completes',
      () async {
        final runId = await focusRepository.startRun(
          const StartFocusRunInput(
            presetId: defaultPresetId,
            targetWorkIntervals: 1,
          ),
        );
        await focusRepository.pauseActiveInterval();
        await focusRepository.resumeActiveInterval();
        await focusRepository.logDistraction(runId: runId, note: 'Ping');
        await focusRepository.completeActiveInterval();
        await focusRepository.startReadyInterval();

        var focusCommands = (await syncQueue.watchPending().first)
            .where((command) => command.type.startsWith('focus.'))
            .toList();
        expect(focusCommands, isEmpty);

        await focusRepository.completeActiveInterval();

        focusCommands = (await syncQueue.watchPending().first)
            .where((command) => command.type.startsWith('focus.'))
            .toList();
        expect(focusCommands.map((command) => command.type), [
          'focus.run.complete',
        ]);
        expect(focusCommands.single.clientId, runId);
      },
    );

    test('stopping focus queues only one terminal run command', () async {
      final runId = await focusRepository.startRun(
        const StartFocusRunInput(targetWorkIntervals: 2),
      );
      await focusRepository.pauseActiveInterval();

      await focusRepository.stopActiveRun(reason: StopFocusReason.stopped);

      final focusCommands = (await syncQueue.watchPending().first)
          .where((command) => command.type.startsWith('focus.'))
          .toList();
      expect(focusCommands.map((command) => command.type), ['focus.run.stop']);
      expect(focusCommands.single.clientId, runId);
    });

    test('stopping or interrupting never publishes completion', () async {
      final completions = <FocusRunCompletionEvent>[];
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        onRunCompleted: completions.add,
      );

      for (final reason in StopFocusReason.values) {
        await repository.startRun(
          const StartFocusRunInput(targetWorkIntervals: 1),
        );
        await repository.stopActiveRun(reason: reason);
      }

      expect(completions, isEmpty);
    });

    test(
      'focus run target follows explicit task and cadence precedence',
      () async {
        final cadencePresetId = await focusRepository.createPreset(
          const CreateFocusPresetInput(
            name: 'Three-step cadence',
            workSeconds: 25 * 60,
            shortBreakSeconds: 5 * 60,
            longBreakSeconds: 15 * 60,
            intervalsBeforeLongBreak: 3,
          ),
        );
        final estimatedTaskId = await taskRepository.createTask(
          const CreateTaskInput(
            content: 'Estimated focus task',
            estimatedFocusIntervals: 5,
          ),
        );
        final unestimatedTaskId = await taskRepository.createTask(
          const CreateTaskInput(content: 'Unestimated focus task'),
        );

        Future<void> expectTarget(
          StartFocusRunInput input,
          int expected,
        ) async {
          await focusRepository.startRun(input);
          expect(
            (await focusRepository.watchActiveRun().first)!.targetWorkIntervals,
            expected,
          );
        }

        await expectTarget(
          StartFocusRunInput(
            taskId: estimatedTaskId,
            presetId: cadencePresetId,
            targetWorkIntervals: 2,
          ),
          2,
        );
        await expectTarget(
          StartFocusRunInput(
            taskId: estimatedTaskId,
            presetId: cadencePresetId,
          ),
          5,
        );
        await expectTarget(
          StartFocusRunInput(
            taskId: unestimatedTaskId,
            presetId: cadencePresetId,
          ),
          1,
        );
        await expectTarget(StartFocusRunInput(presetId: cadencePresetId), 3);
      },
    );

    test('starts a run with the selected preset', () async {
      await focusRepository.startRun(
        const StartFocusRunInput(
          presetId: deepWorkPresetId,
          targetWorkIntervals: 2,
        ),
      );

      final run = await focusRepository.watchActiveRun().first;
      final interval = await focusRepository.watchActiveInterval().first;

      expect(run!.presetId, deepWorkPresetId);
      expect(interval!.plannedSeconds, 50 * 60);
      expect(interval.status, 'running');
    });

    test('switches active run preset for future intervals only', () async {
      await focusRepository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 2,
        ),
      );

      await focusRepository.changeActiveRunPreset(deepWorkPresetId);
      var interval = await focusRepository.watchActiveInterval().first;
      expect(interval!.plannedSeconds, 25 * 60);

      await focusRepository.completeActiveInterval();
      interval = await focusRepository.watchActiveInterval().first;

      expect(interval!.type, 'shortBreak');
      expect(interval.plannedSeconds, 10 * 60);
      expect(interval.status, 'ready');
    });

    test(
      'edited presets affect future intervals without rewriting current one',
      () async {
        final presets = await focusRepository.watchPresets().first;
        final deepWork = presets.firstWhere(
          (preset) => preset.id == deepWorkPresetId,
        );
        await focusRepository.startRun(
          const StartFocusRunInput(
            presetId: deepWorkPresetId,
            targetWorkIntervals: 2,
          ),
        );

        await focusRepository.updatePreset(
          deepWorkPresetId,
          UpdateFocusPresetInput(
            name: deepWork.name,
            workSeconds: 40 * 60,
            shortBreakSeconds: 11 * 60,
            longBreakSeconds: deepWork.longBreakSeconds,
            intervalsBeforeLongBreak: deepWork.intervalsBeforeLongBreak,
            autoStartBreaks: deepWork.autoStartBreaks,
            autoStartWork: deepWork.autoStartWork,
            allowPause: deepWork.allowPause,
            strictMode: deepWork.strictMode,
          ),
        );

        var interval = await focusRepository.watchActiveInterval().first;
        expect(interval!.plannedSeconds, 50 * 60);

        await focusRepository.completeActiveInterval();
        interval = await focusRepository.watchActiveInterval().first;

        expect(interval!.type, 'shortBreak');
        expect(interval.plannedSeconds, 11 * 60);
      },
    );

    test('ready intervals wait when auto-start is disabled', () async {
      await focusRepository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 2,
        ),
      );
      await focusRepository.completeActiveInterval();

      var interval = await focusRepository.watchActiveInterval().first;
      expect(interval!.status, 'ready');
      expect(interval.plannedSeconds, 5 * 60);

      await focusRepository.startReadyInterval();
      interval = await focusRepository.watchActiveInterval().first;
      expect(interval!.status, 'running');
    });

    test('allowPause false blocks pausing', () async {
      final presetId = await focusRepository.createPreset(
        const CreateFocusPresetInput(
          name: 'No Pause',
          workSeconds: 25 * 60,
          shortBreakSeconds: 5 * 60,
          longBreakSeconds: 15 * 60,
          intervalsBeforeLongBreak: 4,
          allowPause: false,
        ),
      );

      await focusRepository.startRun(
        StartFocusRunInput(presetId: presetId, targetWorkIntervals: 2),
      );
      await focusRepository.pauseActiveInterval();

      final interval = await focusRepository.watchActiveInterval().first;
      expect(interval!.status, 'running');
    });

    test('pause active interval marks interval and run paused', () async {
      await focusRepository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 2,
        ),
      );

      await focusRepository.pauseActiveInterval();

      final interval = await focusRepository.watchActiveInterval().first;
      final run = await focusRepository.watchActiveRun().first;
      expect(interval!.status, 'paused');
      expect(interval.pausedAt, isNotNull);
      expect(run!.status, 'paused');
    });

    test(
      'focus repository emits sounds only for successful state changes',
      () async {
        final sounds = _RecordingFocusSoundPlayer();
        final repository = DriftFocusRepository(
          db,
          syncQueue,
          _NoopNotificationScheduler(),
          soundPlayer: sounds,
        );

        await repository.pauseActiveInterval();
        await repository.resumeActiveInterval();
        await repository.completeActiveInterval();
        expect(sounds.cues, isEmpty);

        await repository.startRun(
          const StartFocusRunInput(
            presetId: defaultPresetId,
            targetWorkIntervals: 2,
          ),
        );
        await repository.pauseActiveInterval();
        await repository.resumeActiveInterval();
        await repository.completeActiveInterval();

        expect(sounds.cues, [
          FocusSoundCue.start,
          FocusSoundCue.pause,
          FocusSoundCue.resume,
          FocusSoundCue.complete,
        ]);
      },
    );

    test(
      'skipping work leaves it uncredited and starts a short break',
      () async {
        final notifications = _RecordingNotificationScheduler();
        final sounds = _RecordingFocusSoundPlayer();
        final repository = DriftFocusRepository(
          db,
          syncQueue,
          notifications,
          soundPlayer: sounds,
        );
        final presetId = await repository.createPreset(
          const CreateFocusPresetInput(
            name: 'Auto breaks',
            workSeconds: 25 * 60,
            shortBreakSeconds: 5 * 60,
            longBreakSeconds: 15 * 60,
            intervalsBeforeLongBreak: 1,
            autoStartBreaks: true,
          ),
        );
        final runId = await repository.startRun(
          StartFocusRunInput(presetId: presetId, targetWorkIntervals: 1),
        );
        notifications.scheduledBodies.clear();

        await repository.skipActiveInterval();

        final run = await repository.watchActiveRun().first;
        final intervals = await repository.watchIntervalsForRun(runId).first;
        expect(run, isNotNull);
        expect(run!.completedWorkIntervals, 0);
        expect(intervals.map((interval) => interval.type), [
          'work',
          'shortBreak',
        ]);
        expect(intervals.map((interval) => interval.status), [
          'skipped',
          'running',
        ]);
        expect(notifications.focusCancelCount, 1);
        expect(notifications.scheduledBodies, ['Break completed']);
        expect(sounds.cues, [FocusSoundCue.start]);
      },
    );

    test('skipping a break starts the next work interval', () async {
      final notifications = _RecordingNotificationScheduler();
      final sounds = _RecordingFocusSoundPlayer();
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        notifications,
        soundPlayer: sounds,
      );
      final presetId = await repository.createPreset(
        const CreateFocusPresetInput(
          name: 'Auto work',
          workSeconds: 25 * 60,
          shortBreakSeconds: 5 * 60,
          longBreakSeconds: 15 * 60,
          intervalsBeforeLongBreak: 4,
          autoStartWork: true,
        ),
      );
      final runId = await repository.startRun(
        StartFocusRunInput(presetId: presetId, targetWorkIntervals: 2),
      );
      await repository.completeActiveInterval();
      notifications.scheduledBodies.clear();

      await repository.skipActiveInterval();

      final run = await repository.watchActiveRun().first;
      final intervals = await repository.watchIntervalsForRun(runId).first;
      expect(run, isNotNull);
      expect(run!.completedWorkIntervals, 1);
      expect(intervals.map((interval) => interval.type), [
        'work',
        'shortBreak',
        'work',
      ]);
      expect(intervals.map((interval) => interval.status), [
        'completed',
        'skipped',
        'running',
      ]);
      expect(notifications.scheduledBodies, ['Focus interval completed']);
      expect(sounds.cues, [FocusSoundCue.start, FocusSoundCue.complete]);
    });

    test('skipping the final break completes the focus run', () async {
      final runId = await focusRepository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 1,
        ),
      );
      await focusRepository.completeActiveInterval();

      await focusRepository.skipActiveInterval();

      expect(await focusRepository.watchActiveRun().first, isNull);
      expect(await focusRepository.watchActiveInterval().first, isNull);
      final storedRun = await (db.select(
        db.focusRuns,
      )..where((run) => run.id.equals(runId))).getSingle();
      final intervals = await focusRepository.watchIntervalsForRun(runId).first;
      expect(storedRun.status, 'completed');
      expect(storedRun.endedAt, isNotNull);
      expect(storedRun.completedWorkIntervals, 1);
      expect(intervals.map((interval) => interval.status), [
        'completed',
        'skipped',
      ]);
    });

    test('skipping the final break publishes run completion', () async {
      final completions = <FocusRunCompletionEvent>[];
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        onRunCompleted: completions.add,
      );
      final completedAt = DateTime.utc(2026, 8, 19, 13);
      final runId = await repository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 1,
        ),
      );
      await repository.completeActiveInterval();

      await repository.skipActiveInterval(now: completedAt);
      await repository.skipActiveInterval(now: completedAt);

      expect(completions, hasLength(1));
      expect(completions.single.runId, runId);
      expect(completions.single.taskId, isNull);
      expect(completions.single.taskTitle, isNull);
      expect(completions.single.completedWorkIntervals, 1);
      expect(completions.single.targetWorkIntervals, 1);
      expect(completions.single.completedAt, completedAt);
    });

    test('skipping the final break plays the completion sound', () async {
      final sounds = _RecordingFocusSoundPlayer();
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        soundPlayer: sounds,
      );
      await repository.startRun(
        const StartFocusRunInput(
          presetId: defaultPresetId,
          targetWorkIntervals: 1,
        ),
      );
      await repository.completeActiveInterval();

      await repository.skipActiveInterval();

      expect(sounds.cues, [
        FocusSoundCue.start,
        FocusSoundCue.complete,
        FocusSoundCue.complete,
      ]);
    });

    test('strict mode blocks skip and early completion', () async {
      final completions = <FocusRunCompletionEvent>[];
      final repository = DriftFocusRepository(
        db,
        syncQueue,
        _NoopNotificationScheduler(),
        onRunCompleted: completions.add,
      );
      final presetId = await focusRepository.createPreset(
        const CreateFocusPresetInput(
          name: 'Strict',
          workSeconds: 25 * 60,
          shortBreakSeconds: 5 * 60,
          longBreakSeconds: 15 * 60,
          intervalsBeforeLongBreak: 4,
          strictMode: true,
        ),
      );

      final runId = await repository.startRun(
        StartFocusRunInput(presetId: presetId, targetWorkIntervals: 2),
      );
      await repository.skipActiveInterval();

      var interval = await repository.watchActiveInterval().first;
      expect(interval!.status, 'running');
      expect(interval.type, 'work');
      expect(await repository.watchIntervalsForRun(runId).first, hasLength(1));

      await repository.completeActiveInterval();

      interval = await repository.watchActiveInterval().first;
      expect(interval!.status, 'running');
      expect(interval.type, 'work');
      expect(completions, isEmpty);
    });

    test('demo seed data is idempotent and avoids sync commands', () async {
      await db.ensureDemoSeedData();
      await db.ensureDemoSeedData();

      final projects = await db.select(db.projects).get();
      final tasks = await db.select(db.tasks).get();
      final labels = await db.select(db.labels).get();
      final taskLabels = await db.select(db.taskLabels).get();
      final completions = await db.select(db.taskCompletions).get();
      final focusIntervals = await db.select(db.focusIntervals).get();
      final syncCommands = await db.select(db.syncCommands).get();
      final user = await (db.select(
        db.users,
      )..where((row) => row.id.equals(localUserId))).getSingle();

      expect(user.email, 'emily.parker@example.com');
      expect(user.displayName, 'Emily Parker');
      expect(
        projects.where((project) => project.id.startsWith('demo-project')),
        hasLength(5),
      );
      expect(
        labels.where((label) => label.id.startsWith('demo-label')),
        hasLength(12),
      );
      expect(
        tasks.where((task) => task.id.startsWith('demo-task')),
        hasLength(33),
      );
      expect(
        tasks.map((task) => task.content),
        contains('Review Google Calendar sync edge cases'),
      );
      expect(
        completions.where((row) => row.id.startsWith('demo-completion')),
        hasLength(7),
      );
      expect(
        focusIntervals.where((row) => row.id.startsWith('demo-focus-interval')),
        hasLength(7),
      );
      expect(
        taskLabels.map((link) => '${link.taskId}:${link.labelId}').toSet(),
        hasLength(taskLabels.length),
      );
      expect(syncCommands, isEmpty);
    });
  });

  group('project colors', () {
    ProjectItem project(String id, {String? color}) => ProjectItem(
      id: id,
      userId: localUserId,
      name: id,
      color: color,
      orderKey: id,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    test('uses stable palette fallback for projects without colors', () {
      final first = effectiveProjectColor(project('project-without-color'));
      final second = effectiveProjectColor(project('project-without-color'));

      expect(projectColorPalette, hasLength(14));
      expect(projectColorPalette, contains(first));
      expect(second, first);
      expect(
        effectiveProjectColor(project(inboxProjectId)),
        inboxProjectColorHex,
      );
    });

    test(
      'chooses the least used palette color with palette-order tie break',
      () {
        final projects = [
          project('one', color: projectColorPalette[0]),
          project('two', color: projectColorPalette[0]),
          project('three', color: projectColorPalette[1]),
        ];

        expect(nextProjectColor(projects), projectColorPalette[2]);
      },
    );
  });
}

AchievementItem _achievementById(List<AchievementItem> items, String id) {
  return items.firstWhere((item) => item.id == id);
}

TaskCompletionRow _achievementCompletion(
  String id,
  DateTime completedAt, {
  String taskId = 'task',
}) {
  return TaskCompletionRow(
    id: id,
    taskId: taskId,
    userId: localUserId,
    completedAt: completedAt,
    createdAt: completedAt,
  );
}

FocusIntervalRow _achievementInterval(
  String id,
  DateTime startedAt, {
  String? taskId,
  String type = 'work',
  String status = 'completed',
  DateTime? completedAt,
  bool isDeleted = false,
}) {
  return FocusIntervalRow(
    id: id,
    runId: 'run-$id',
    taskId: taskId,
    type: type,
    status: status,
    plannedSeconds: 1500,
    startedAt: startedAt,
    pausedTotalSeconds: 0,
    completedAt:
        completedAt ??
        (status == 'completed'
            ? startedAt.add(const Duration(minutes: 25))
            : null),
    stoppedAt: status == 'stopped'
        ? startedAt.add(const Duration(minutes: 5))
        : null,
    sequenceNumber: 1,
    createdAt: startedAt,
    updatedAt: startedAt,
    isDeleted: isDeleted,
  );
}

ProductivitySummary _productivitySummary({
  int completedTasks = 0,
  int completedFocusIntervals = 0,
}) {
  return ProductivitySummary(
    completedTasks: completedTasks,
    completedFocusIntervals: completedFocusIntervals,
    totalFocusSeconds: 0,
    plannedFocusIntervals: 0,
    openTasks: 0,
    allTimeCompletedTasks: 0,
    allTimeCompletedFocusIntervals: 0,
  );
}

TaskItem _notificationTask({
  required String id,
  required String content,
  required TaskSchedule schedule,
}) {
  final now = DateTime.utc(2026);
  return TaskItem(
    id: id,
    userId: localUserId,
    content: content,
    projectId: inboxProjectId,
    priority: 4,
    dueJson: schedule.toJsonString(),
    status: 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeReengagementNotificationScheduler extends NotificationScheduler {
  int cancelReengagementCount = 0;
  int permissionRequestCount = 0;
  DateTime? scheduledReengagementAt;
  String? scheduledReengagementTitle;
  final scheduledTaskStarts = <String, DateTime>{};
  final canceledTaskStarts = <String>[];
  Set<String> pendingTaskStarts = const {};

  @override
  Future<void> requestNotificationPermissions() async {
    permissionRequestCount++;
  }

  @override
  Future<void> scheduleReengagementReminder({
    required DateTime firstAt,
    required String title,
    required String body,
  }) async {
    scheduledReengagementAt = firstAt;
    scheduledReengagementTitle = title;
  }

  @override
  Future<void> cancelReengagementReminder() async {
    cancelReengagementCount++;
  }

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {
    scheduledTaskStarts[taskId] = startAt;
  }

  @override
  Future<void> cancelTaskStart(String taskId) async {
    canceledTaskStarts.add(taskId);
  }

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async {
    return pendingTaskStarts;
  }
}

FocusPresetItem _testPreset({
  required String id,
  required int workMinutes,
  required int shortBreakMinutes,
  required int longBreakMinutes,
}) {
  return FocusPresetItem(
    id: id,
    userId: localUserId,
    name: id,
    workSeconds: workMinutes * 60,
    shortBreakSeconds: shortBreakMinutes * 60,
    longBreakSeconds: longBreakMinutes * 60,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: id == defaultPresetId,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Map<String, Object?> _payloadFor(
  List<SyncCommandRow> commands,
  String type,
  String clientId,
) {
  final command = commands.firstWhere(
    (command) => command.type == type && command.clientId == clientId,
  );
  return Map<String, Object?>.from(jsonDecode(command.payloadJson) as Map);
}

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelFocusNotification() async {}

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}
}

class _RecordingNotificationScheduler extends _NoopNotificationScheduler {
  final scheduledBodies = <String>[];
  int focusCancelCount = 0;

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {
    scheduledBodies.add(body);
  }

  @override
  Future<void> cancelFocusNotification() async {
    focusCancelCount++;
  }
}

class _RecordingFocusSoundPlayer implements FocusSoundPlayer {
  final cues = <FocusSoundCue>[];

  @override
  Future<void> play(FocusSoundCue cue) async {
    cues.add(cue);
  }

  @override
  Future<void> dispose() async {}
}
