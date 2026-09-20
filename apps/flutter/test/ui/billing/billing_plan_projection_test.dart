import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/view_models/billing_view_model.dart';

void main() {
  test(
    'paywall modes replace only the lifetime plan and expose immutable lists',
    () {
      final viewModel = BillingViewModel();
      final regular = viewModel.plansForPaywall(launchOfferMode: false);
      final launch = viewModel.plansForPaywall(launchOfferMode: true);
      expect(regular.map((plan) => plan.productId), [
        pomodoistAnnualProductId,
        pomodoistMonthlyProductId,
        pomodoistLifetimeProductId,
      ]);
      expect(launch.map((plan) => plan.productId), [
        pomodoistAnnualProductId,
        pomodoistMonthlyProductId,
        pomodoistLifetimeLaunchProductId,
      ]);
      expect(launch.first, same(regular.first));
      expect(launch[1], same(regular[1]));
      expect(() => regular.clear(), throwsUnsupportedError);
      expect(() => launch.clear(), throwsUnsupportedError);
      expect(viewModel.plansForPaywall(launchOfferMode: false), regular);
    },
  );
}
