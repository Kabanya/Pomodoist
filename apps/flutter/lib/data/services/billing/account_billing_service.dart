import 'package:app_account/app_account.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pomodoist/domain/models/billing/billing_models.dart';

/// Account-backed billing transport. Composition supplies identity and locale;
/// this service owns remote calls, response validation and checkout launching.
final class AccountBillingService {
  AccountBillingService({
    required AccountClient account,
    required String Function() locale,
    required void Function() onLinked,
  }) : _account = account,
       _ownerId = account.currentUserId,
       _locale = locale,
       _onLinked = onLinked;

  final AccountClient _account;
  final String? _ownerId;
  final String Function() _locale;
  final void Function() _onLinked;

  Future<void> linkPurchases(List<String> transactions) async {
    final session = _account.currentSession;
    if (_ownerId == null ||
        _account.currentUserId != _ownerId ||
        session == null ||
        session.userId != _ownerId ||
        session.accessToken == null ||
        session.accessToken!.isEmpty) {
      throw StateError('The purchase account changed.');
    }
    final response = await _account.invokeFunction(
      'pomodoist-purchase',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'transactions': transactions},
    );
    final data = response.data;
    if (data is Map && data['code'] == 'purchase_already_linked') {
      throw Exception(
        'This App Store purchase is linked to another Pomodoist account.',
      );
    }
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['ok'] != true) {
      throw Exception(
        'App Store Pro works on this device, but account linking failed.',
      );
    }
    if (_account.currentUserId == _ownerId) _onLinked();
  }

  Future<Object?> requestOffer(Map<String, Object?> body) async {
    final response = await _account.invokeFunction(
      'pomodoist-subscription-offer',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      throw BillingOfferException(
        data is Map && data['code'] is String
            ? data['code'] as String
            : 'verification_failed',
      );
    }
    return response.data;
  }

  Future<StripeBillingCatalog> loadStripeCatalog() async {
    _checkStripeOwner();
    final response = await _account.invokeFunction(
      'pomodoist-stripe-billing',
      body: {'action': 'catalog', 'offerVersion': 1},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StripeBillingException(_stripeError(response.data));
    }
    final catalog = StripeBillingCatalog.fromJson(response.data);
    return catalog;
  }

  Future<Uri> createStripeCheckout(
    String productId,
    BillingCheckoutSurface surface,
    String? selectedOffer,
  ) async {
    _checkStripeOwner();
    final response = await _account.invokeFunction(
      'pomodoist-stripe-billing',
      body: {
        'action': 'checkout',
        'offerVersion': 1,
        'selectedOffer': ?selectedOffer,
        'productId': productId,
        'surface': surface.name,
        'locale': _locale(),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StripeBillingException(_stripeError(response.data));
    }
    return stripeCheckoutUrlFromJson(response.data);
  }

  void _checkStripeOwner() {
    if (_ownerId == null || _account.currentUserId != _ownerId) {
      throw const StripeBillingException('authentication_required');
    }
  }

  Future<bool> openCheckout(Uri url) {
    _checkStripeOwner();
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  static String _stripeError(Object? value) =>
      value is Map && value['code'] is String
      ? value['code'] as String
      : 'checkout_failed';
}
