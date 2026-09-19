import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_fr.dart';

void main() {
  test('daily summary refreshes at midnight, not every timer tick', () {
    final repository = _DailyRepository();
    final container = ProviderContainer(
      overrides: [
        productivityRepositoryProvider.overrideWithValue(repository),
        focusTickerProvider.overrideWithValue(
          AsyncData(DateTime(2026, 9, 9, 23, 59)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(productivitySummaryProvider, (_, _) {});
    expect(repository.subscriptions, 1);
    void tick(DateTime time) {
      container.updateOverrides([
        productivityRepositoryProvider.overrideWithValue(repository),
        focusTickerProvider.overrideWithValue(AsyncData(time)),
      ]);
      container.read(productivitySummaryProvider);
    }

    tick(DateTime(2026, 9, 9, 23, 59, 59));
    expect(repository.subscriptions, 1);
    tick(DateTime(2026, 9, 10));
    expect(repository.subscriptions, 2);
  });

  test('French plural rules retain zero in a daily task count', () {
    expect(
      AppLocalizationsFr().todayTaskSummary(0, 4, '50 min'),
      startsWith('0'),
    );
  });
}

class _DailyRepository implements ProductivityRepository {
  int subscriptions = 0;
  @override
  Stream<ProductivitySummary> watchTodaySummary() {
    subscriptions++;
    return const Stream.empty();
  }

  @override
  Future<Result<void>> recalculateDailyStats(DateTime localDate) =>
      Result.capture<void>(() async {});
}
