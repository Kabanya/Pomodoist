import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/ui/quick_add/view_models/global_quick_add_window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  GlobalQuickAddWindowManager manager({PreferencesService? service}) =>
      GlobalQuickAddWindowManager(
        preferences: LocalPreferencesRepository(
          service ?? PreferencesService(SharedPreferences.getInstance),
        ),
      );

  test(
    'voice takes priority and closing it restores the open comment size',
    () {
      expect(
        globalQuickAddWindowSize(voiceExpanded: true, commentExpanded: true),
        globalQuickAddVoiceSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: false, commentExpanded: true),
        globalQuickAddCommentSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: false, commentExpanded: false),
        globalQuickAddCompactSize,
      );
      expect(
        globalQuickAddWindowSize(voiceExpanded: true, commentExpanded: false),
        globalQuickAddVoiceSize,
      );
    },
  );

  test(
    'detailed editor expands within the work area and restores the base size',
    () {
      const base = Size(680, 240);
      expect(
        globalQuickAddWindowSize(
          baseSize: base,
          voiceExpanded: false,
          commentExpanded: false,
          editorExpanded: true,
          workArea: const Size(850, 700),
        ),
        const Size(850, 700),
      );
      expect(
        globalQuickAddWindowSize(
          baseSize: base,
          voiceExpanded: false,
          commentExpanded: false,
        ),
        base,
      );
    },
  );

  test('expansion preserves a larger base and the chosen comment width', () {
    expect(
      globalQuickAddWindowSize(
        baseSize: const Size(850, 760),
        voiceExpanded: true,
        commentExpanded: true,
      ),
      const Size(850, 760),
    );
    expect(
      globalQuickAddWindowSize(
        baseSize: const Size(460, 230),
        voiceExpanded: false,
        commentExpanded: true,
      ),
      const Size(460, 340),
    );
  });

  test('restored and expanded sizes respect the working area', () {
    expect(
      globalQuickAddWindowSize(
        baseSize: const Size(1200, 1000),
        voiceExpanded: true,
        commentExpanded: true,
        workArea: const Size(800, 600),
      ),
      const Size(800, 600),
    );
    expect(
      globalQuickAddWindowSize(
        baseSize: const Size(1, 1),
        voiceExpanded: false,
        commentExpanded: false,
        workArea: const Size(300, 150),
      ),
      const Size(300, 150),
    );
  });

  test('manual dimensions survive a new manager and temporary modes', () async {
    final first = manager();
    await first.restoreSize();
    await first.rememberSize(const Size(510, 260));
    await first.setCommentExpanded(true);
    await first.setVoiceMode(true);
    await first.setVoiceMode(false);
    await first.setCommentExpanded(false);
    expect(first.baseSize, const Size(510, 260));
    final reopened = manager();
    await reopened.restoreSize();
    expect(reopened.baseSize, const Size(510, 260));

    await reopened.setVoiceMode(true);
    await reopened.rememberSize(const Size(600, 500));
    await reopened.setVoiceMode(false);
    expect(reopened.baseSize, const Size(600, 500));
    final restarted = manager();
    await restarted.restoreSize();
    expect(restarted.baseSize, const Size(600, 500));
  });

  test(
    'malformed dimensions fall back and valid outliers are clamped',
    () async {
      for (final saved in [
        'not json',
        '[]',
        '{"width": "wide", "height": 250}',
        '{"width": 500}',
        '{"width": -1, "height": 250}',
        '{"width": 500, "height": 0}',
        '{"width": 1e999, "height": 250}',
        42,
      ]) {
        SharedPreferences.setMockInitialValues({quickAddWindowSizeKey: saved});
        final window = manager();
        await window.restoreSize();
        expect(window.baseSize, globalQuickAddCompactSize, reason: '$saved');
      }
      SharedPreferences.setMockInitialValues({
        quickAddWindowSizeKey: '{"width": 1200, "height": 100}',
      });
      final window = manager();
      await window.restoreSize();
      expect(window.baseSize, const Size(900, 100));
    },
  );

  test('storage failure keeps manual dimensions usable in memory', () async {
    final window = manager(
      service: PreferencesService(() async => throw StateError('unavailable')),
    );
    await window.restoreSize();
    expect(window.baseSize, globalQuickAddCompactSize);
    await window.rememberSize(const Size(530, 270));
    await window.restoreSize();
    expect(window.baseSize, const Size(530, 270));
  });

  test('a delayed load cannot overwrite a manual resize', () async {
    SharedPreferences.setMockInitialValues({
      quickAddWindowSizeKey: '{"width": 800, "height": 400}',
    });
    final pending = Completer<SharedPreferences?>();
    final window = manager(service: PreferencesService(() => pending.future));
    final load = window.restoreSize();
    final save = window.rememberSize(const Size(540, 280));
    pending.complete(await SharedPreferences.getInstance());
    await Future.wait([load, save]);
    expect(window.baseSize, const Size(540, 280));
  });

  test('rapid manual resizes persist the latest complete size', () async {
    final window = manager();
    await Future.wait([
      window.rememberSize(const Size(500, 250)),
      window.rememberSize(const Size(560, 290)),
    ]);
    await window.rememberSize(const Size(double.infinity, 300));
    await window.rememberSize(Size.zero);
    final restarted = manager();
    await restarted.restoreSize();
    expect(restarted.baseSize, const Size(560, 290));
    expect(window.baseSize, restarted.baseSize);
  });

  test(
    'first opening fits the labeled toolbar without replacing manual sizes',
    () async {
      final initial = manager();
      await initial.restoreSize();
      await initial.setPreferredWidth(842.2);
      expect(initial.baseSize, const Size(843, 200));
      await initial.setPreferredWidth(880);
      expect(initial.baseSize, const Size(843, 200));

      await initial.rememberSize(const Size(540, 260));
      final restored = manager();
      await restored.restoreSize();
      await restored.setPreferredWidth(843);
      expect(restored.baseSize, const Size(540, 260));
    },
  );

  test(
    'initial width includes native borders outside the content viewport',
    () async {
      final window = manager();
      await window.restoreSize();
      await window.setPreferredWidth(842.2, frameWidthInset: 16);
      expect(window.baseSize, const Size(859, 200));
    },
  );

  test(
    'automatic height includes native chrome without changing width or saving',
    () async {
      final window = manager();
      await window.restoreSize();
      await window.setPreferredWidth(842.2);
      await window.setHeightRequirements(400.2, 260.2, frameHeightInset: 32);
      expect(window.baseSize, const Size(843, 433));
      expect(
        (await SharedPreferences.getInstance()).getString(
          quickAddWindowSizeKey,
        ),
        isNull,
      );
      await window.setHeightRequirements(300, 220, frameHeightInset: 32);
      expect(window.baseSize, const Size(843, 332));
      await window.setHeightRequirements(double.nan, 220);
      expect(window.baseSize, const Size(843, 332));
    },
  );

  test(
    'height requirements retain manual sizes and protect later resizes',
    () async {
      final window = manager();
      await window.rememberSize(const Size(540, 400));
      await window.setHeightRequirements(650, 250, frameHeightInset: 32);
      expect(window.baseSize, const Size(540, 400));
      await window.rememberSize(const Size(540, 200));
      expect(window.baseSize, const Size(540, 282));
      final restored = manager();
      await restored.restoreSize();
      expect(restored.baseSize, const Size(540, 282));
    },
  );

  test(
    'a scaled minimum clamps old sizes within native and display limits',
    () {
      expect(
        globalQuickAddWindowSize(
          baseSize: const Size(540, 200),
          voiceExpanded: false,
          commentExpanded: false,
          minimumHeight: 340,
        ),
        const Size(540, 340),
      );
      expect(
        globalQuickAddWindowSize(
          baseSize: const Size(540, 200),
          voiceExpanded: false,
          commentExpanded: false,
          minimumHeight: 340,
          workArea: const Size(800, 300),
        ),
        const Size(540, 300),
      );
    },
  );

  test('temporary modes do not replace fitted base height', () async {
    final window = manager();
    await window.setHeightRequirements(300, 220);
    for (final mode in [
      window.setCommentExpanded,
      window.setVoiceMode,
      window.setEditorExpanded,
    ]) {
      await mode(true);
      await window.setHeightRequirements(600, 300);
      expect(window.baseSize, const Size(680, 300));
      await mode(false);
    }
  });
  test(
    'measured compact heights avoid the old 200 px floor and survive restart',
    () async {
      final window = manager();
      await window.setHeightRequirements(152, 142, frameHeightInset: 32);
      expect(window.baseSize, const Size(680, 184));
      await window.setPreferredWidth(843);
      expect(window.baseSize, const Size(843, 184));
      await window.rememberSize(const Size(540, 175));
      final restored = manager();
      await restored.restoreSize();
      expect(restored.baseSize, const Size(540, 175));
      await restored.setHeightRequirements(300, 142, frameHeightInset: 32);
      expect(restored.baseSize, const Size(540, 175));
    },
  );
}
