import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/config/distraction_repository.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';

class _Local extends Fake implements FocusRepository {}

class _FailedPreferences extends Fake implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;
  @override
  Future<bool> setBool(String key, bool value) async => false;
}

ResourceAssignment assignment(String category, String source) =>
    ResourceAssignment.fromJson({
      'id': 'example.com',
      'kind': 'domain',
      'category': category,
      'source': source,
    });

void main() {
  test(
    'failed offline profile write preserves the saved rules and queue',
    () async {
      final focus = LiveFocusRepository(
        local: _Local(),
        remote: null,
        owner: 'u',
        deviceId: 'd',
        preferences: _FailedPreferences(),
      );
      addTearDown(focus.dispose);
      focus.profiles = [
        DistractionProfile.fromJson({
          'id': 'work',
          'name': 'Work',
          'blockedCategories': ['video'],
        }),
      ];
      await expectLater(
        focus.saveProfile(
          DistractionProfile.fromJson({
            'id': 'work',
            'name': 'Work',
            'blockedCategories': ['social'],
          }),
        ),
        throwsStateError,
      );
      expect(focus.profiles.single.blockedCategories, ['video']);
      expect(focus.pendingSettings, isEmpty);
    },
  );

  test('failed automatic setting does not appear enabled', () async {
    final focus = LiveFocusRepository(
      local: _Local(),
      remote: null,
      owner: 'u',
      deviceId: 'd',
      preferences: _FailedPreferences(),
    );
    addTearDown(focus.dispose);
    final commands = CoordinatedDistractionRepository(
      focus,
      protection: () => null,
      classifyResource: (r) async => r,
    );
    await expectLater(commands.configure(automatic: true), throwsStateError);
    expect(commands.state.automatic, false);
  });

  test(
    'manual assignment made during search wins; quota error retains assignments',
    () async {
      final focus = LiveFocusRepository(
        local: _Local(),
        remote: null,
        owner: 'u',
        deviceId: 'd',
        preferences: null,
      );
      addTearDown(focus.dispose);
      final search = Completer<ResourceAssignment>();
      final commands = CoordinatedDistractionRepository(
        focus,
        protection: () => null,
        classifyResource: (_) => search.future,
      );
      commands.automatic = true;
      final pending = commands.classify(assignment('unclassified', 'manual'));
      await commands.saveAssignment(assignment('education', 'manual'));
      search.complete(assignment('social', 'automatic'));
      await pending;
      expect(commands.state.assignments.single.category, 'education');
      expect(commands.state.assignments.single.source, 'manual');
      expect(
        focus.pendingSettings.single['payload']['assignment']['category'],
        'education',
      );
      final limited = CoordinatedDistractionRepository(
        focus,
        protection: () => null,
        classifyResource: (_) async => throw StateError('quota_exceeded'),
      );
      await expectLater(
        limited.classify(assignment('unclassified', 'manual')),
        throwsStateError,
      );
      expect(commands.state.assignments.single.category, 'education');
      await commands.configure(automatic: false);
      expect(commands.state.assignments.single.category, 'education');
    },
  );
}
