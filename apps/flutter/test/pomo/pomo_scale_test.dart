import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_geometry.dart';

void main() {
  test('hidden capsule passes input through without changing geometry', () {
    for (final scale in [.25, 1.0, 2.5]) {
      final g = PomoLayout(scale);
      final menu = Rect.fromLTWH(4, 4, g.size.width - 8, 60);
      for (final expanded in [false, true]) {
        final visible = g.regions(expanded);
        expect(
          g.regions(expanded, capsuleVisible: false),
          visible.where((r) => r != g.capsule).toList(),
        );
        expect(g.regions(expanded, capsuleVisible: false, contextMenu: menu), [
          ...visible.where((r) => r != g.capsule),
          menu,
        ]);
        expect(g.regions(expanded, capsuleVisible: true), visible);
      }
    }
  });
  test('context menu extends native input regions only while open', () {
    for (final scale in [.25, 1.0, 2.5]) {
      final g = PomoLayout(scale);
      final menu = Rect.fromLTWH(4, 4, g.size.width - 8, 60);
      for (final expanded in [false, true]) {
        final normal = g.regions(expanded);
        expect(g.regions(expanded, contextMenu: menu), [...normal, menu]);
        expect(g.regions(expanded), normal);
        expect(normal, isNot(contains(menu)));
      }
    }
  });

  test(
    'rounded native bounds settle without repeated moves; real drags remain',
    () {
      final g = PomoLayout(1.35);
      const origin = Offset(100.2, 200.4);
      final desired = origin & g.size;
      final rounded = Rect.fromLTWH(
        100,
        200.5,
        (g.size.width * 2).round() / 2,
        (g.size.height * 2).round() / 2,
      );
      expect(
        PomoLayout.matchesWindowBounds(desired, rounded, pixelRatio: 2),
        true,
      );
      expect(
        PomoLayout.matchesWindowBounds(
          desired,
          rounded.shift(const Offset(1, 0)),
          pixelRatio: 2,
        ),
        false,
      );
      expect(
        PomoLayout.matchesWindowBounds(
          desired,
          Rect.fromLTWH(100, 200.5, g.size.width / 1.5, g.size.height / 1.5),
          pixelRatio: 1.5,
        ),
        false,
      );
    },
  );

  test('native size is re-applied after moving to a different monitor DPI', () {
    final g = PomoLayout(1);
    expect(g.matchesWindowSize(g.size), true);
    expect(g.matchesWindowSize(g.size / 1.5, pixelRatio: 1.5), false);
    expect(
      g.matchesWindowSize(
        Size(g.size.width + .2, g.size.height),
        pixelRatio: 2,
      ),
      true,
    );
  });

  test('old and corrupt preferences default to 100%; finite numbers clamp', () {
    for (final value in [null, '1.5', true, double.nan, double.infinity]) {
      expect(PomoPreferences.fromJson({'scale': value}).scale, 1);
    }
    expect(PomoPreferences.fromJson({'scale': -4}).scale, .25);
    expect(PomoPreferences.fromJson({'scale': 8}).scale, 2.5);
    final p = PomoPreferences.fromJson({'scale': 1.35, 'enabled': true});
    expect(PomoPreferences.fromJson(p.toJson()).scale, 1.35);
    expect(p.copyWith(quiet: true).scale, 1.35);
  });
  test(
    'all scales keep distinct controls and accessible targets inside bounds',
    () {
      for (var percent = 25; percent <= 250; percent += 5) {
        final g = PomoLayout(percent / 100);
        final controls = [
          g.add,
          g.toggle,
          g.complete,
          g.hide,
          g.settings,
          g.capsule,
        ];
        final bounds = Offset.zero & g.size;
        for (final r in [...controls, g.pet]) {
          expect(bounds.contains(r.topLeft), true, reason: '$percent: $r');
          expect(r.right <= bounds.right && r.bottom <= bounds.bottom, true);
        }
        for (var i = 0; i < controls.length; i++) {
          expect(controls[i].shortestSide, greaterThanOrEqualTo(48 - 1e-9));
          expect(controls[i].overlaps(g.pet), false);
          for (var j = i + 1; j < controls.length; j++) {
            expect(
              controls[i].overlaps(controls[j]),
              false,
              reason: '$percent: $i/$j',
            );
          }
        }
        expect(g.timerFontSize, greaterThanOrEqualTo(12));
      }
    },
  );
  test(
    'screen fitting preserves preference and center, clamps negative displays',
    () {
      const area = Rect.fromLTWH(-1280, 25, 1280, 775);
      final g = PomoLayout.fitting(2.5, area.size);
      expect(g.scale, lessThan(2.5));
      expect(g.size.width <= area.width && g.size.height <= area.height, true);
      final centered = g.position(area, center: area.center);
      expect((centered & g.size).center, area.center);
      final clamped = g.position(area, saved: const Offset(4000, -300));
      expect(clamped.dx, closeTo(area.right - g.size.width, .001));
      expect(clamped.dy, area.top);
    },
  );
  test('panel chooses left, falls back right, then clamps to work area', () {
    const area = Rect.fromLTWH(0, 0, 1280, 800);
    const size = Size(320, 240);
    expect(
      PomoLayout.panelPosition(
        area,
        const Rect.fromLTWH(800, 400, 300, 350),
        size,
      ).dx,
      468,
    );
    expect(
      PomoLayout.panelPosition(
        area,
        const Rect.fromLTWH(50, 400, 300, 350),
        size,
      ).dx,
      362,
    );
    final pos = PomoLayout.panelPosition(
      area,
      const Rect.fromLTWH(300, 700, 800, 350),
      size,
    );
    expect(pos.dx, inInclusiveRange(0, 960));
    expect(pos.dy, 560);
  });

  test('open settings stay fixed while Pomo grows and shrinks', () {
    const area = Rect.fromLTWH(0, 0, 1920, 1080);
    const panel = Size(320, 256);
    const saved = Offset(468, 447);
    for (final pomo in [
      Rect.fromLTWH(500, 100, 1000, 900),
      Rect.fromLTWH(900, 500, 100, 150),
    ]) {
      expect(PomoLayout.panelPosition(area, pomo, panel, saved: saved), saved);
    }
    expect(
      PomoLayout.panelPosition(
        const Rect.fromLTWH(-1280, 25, 1280, 775),
        const Rect.fromLTWH(-400, 200, 300, 350),
        panel,
        saved: saved,
      ),
      const Offset(-320, 447),
    );
  });
}
