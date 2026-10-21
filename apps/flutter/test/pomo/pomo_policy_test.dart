import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_reactions.dart';

void main() {
  test(
    'timer stays visible for old preferences and preserves explicit hiding',
    () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'showTimer': null},
        {'showTimer': 'false'},
      ]) {
        expect(PomoPreferences.fromJson(json).toJson()['showTimer'], true);
      }
      final hidden = PomoPreferences.fromJson({'showTimer': false});
      expect(hidden.toJson()['showTimer'], false);
      expect(hidden.copyWith(quiet: true).toJson()['showTimer'], false);
      expect(
        PomoPreferences.fromJson(hidden.toJson()).toJson()['showTimer'],
        false,
      );
    },
  );
  test('dismissal dominates active Focus and survives serialization', () {
    final p = PomoPreferences(enabled: true, dismissed: true);
    expect(p.shouldShow(hasRun: true), false);
    expect(PomoPreferences.fromJson(p.toJson()).dismissed, true);
    expect(const PomoPreferences().shouldShow(hasRun: true), false);
    expect(
      const PomoPreferences(enabled: true).shouldShow(hasRun: false),
      true,
    );
    expect(
      const PomoPreferences(
        enabled: true,
        focusOnly: true,
      ).shouldShow(hasRun: false),
      false,
    );
    expect(
      const PomoPreferences(
        enabled: true,
        focusOnly: true,
      ).shouldShow(hasRun: false, explicitShow: true),
      true,
    );
  });
  test('corrupt coordinates are rejected', () {
    expect(PomoPreferences.fromJson({'x': double.nan, 'y': 2}).x, null);
  });
  test(
    'reactions prioritize closure, coalesce celebrations and throttle taps',
    () {
      fakeAsync((time) {
        final r = PomoReactions(now: () => DateTime(2026).add(time.elapsed));
        expect(r.request(PomoEmotion.greeting, eventId: 'show:1'), true);
        expect(r.request(PomoEmotion.surprised), false);
        expect(r.request(PomoEmotion.happy, eventId: 'task:1'), true);
        expect(r.request(PomoEmotion.happy, eventId: 'interval:1'), false);
        time.elapse(const Duration(seconds: 3));
        expect(r.emotion, null);
        expect(r.request(PomoEmotion.happy, eventId: 'task:1'), false);
        expect(r.request(PomoEmotion.surprised), true);
        expect(r.request(PomoEmotion.surprised), false);
        expect(r.request(PomoEmotion.sad), true);
        time.elapse(const Duration(milliseconds: 899));
        expect(r.emotion, PomoEmotion.sad);
        time.elapse(const Duration(milliseconds: 1));
        expect(r.emotion, null);
        r.dispose();
      });
    },
  );
  test(
    'motion changes immediately replace motion and do not delay closing',
    () {
      fakeAsync((time) {
        final r = PomoReactions(now: () => DateTime(2026).add(time.elapsed));
        r.request(PomoEmotion.happy, eventId: '1');
        r.setMotion(quiet: false, reduceMotion: true);
        expect(r.animated, false);
        expect(r.emotion, PomoEmotion.happy);
        time.elapse(const Duration(milliseconds: 600));
        expect(r.emotion, null);
        r.request(PomoEmotion.sad);
        expect(r.remaining, Duration.zero);
        r.dispose();
      });
    },
  );
}
