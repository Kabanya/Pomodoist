import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';

void main() {
  test('specific domain exception wins, domain boundary is respected', () {
    final profile = DistractionProfile.fromJson({
      'id': 'work',
      'name': 'Work',
      'blockedCategories': ['video'],
      'overrides': [
        {'kind': 'domain', 'id': 'youtube.com', 'action': 'block'},
        {'kind': 'domain', 'id': 'learn.youtube.com', 'action': 'allow'},
      ],
    });
    expect(profile.blocks('domain', 'www.youtube.com', 'unclassified'), true);
    expect(profile.blocks('domain', 'learn.youtube.com', 'video'), false);
    expect(
      profile.blocks('domain', 'youtube.com.example.org', 'unclassified'),
      false,
    );
    expect(profile.blocks('app', 'macos:unknown', 'unclassified'), false);
  });
  test(
    'phase rules release ready and expired protection, strict pause blocks',
    () {
      final profile = DistractionProfile.fromJson({
        'id': 'work',
        'name': 'Work',
        'blockOnPause': false,
      });
      expect(profile.applies('work', 'running', false), true);
      expect(profile.applies('work', 'paused', false), false);
      expect(profile.applies('work', 'paused', true), true);
      expect(profile.applies('shortBreak', 'running', true), false);
      expect(profile.applies('work', 'ready', true), false);
    },
  );
  test('manual assignments are not replaced by automatic categories', () {
    final manual = ResourceAssignment.fromJson({
      'id': 'youtube.com',
      'kind': 'domain',
      'name': 'YouTube',
      'category': 'education',
      'source': 'manual',
    });
    final automatic = ResourceAssignment.fromJson({
      'id': 'youtube.com',
      'kind': 'domain',
      'category': 'video',
      'source': 'automatic',
    });
    expect(mergeAssignment(manual, automatic).category, 'education');
    expect(
      normalizeDomain('https://YouTube.com/watch?v=private'),
      'youtube.com',
    );
    expect(normalizeDomain('localhost'), isNull);
    expect(normalizeDomain('192.168.1.1'), isNull);
  });
}
