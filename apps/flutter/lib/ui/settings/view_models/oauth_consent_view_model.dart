import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';

enum ConsentAction { idle, approving, denying, redirecting }

final class OAuthConsentState {
  const OAuthConsentState({
    required this.valid,
    this.authorization,
    this.loadError,
    this.actionError,
    this.redirectError = false,
    this.action = ConsentAction.idle,
    this.redirectUrl,
  });
  final bool valid;
  final OAuthAuthorization? authorization;
  final Object? loadError;
  final Object? actionError;
  final bool redirectError;
  final ConsentAction action;
  final String? redirectUrl;
}

final oauthConsentViewModelProvider = NotifierProvider.autoDispose
    .family<OAuthConsentViewModel, OAuthConsentState, Uri>(
      OAuthConsentViewModel.new,
    );

class OAuthConsentViewModel extends Notifier<OAuthConsentState> {
  OAuthConsentViewModel(this.uri);
  final Uri uri;
  AccountManagementRepository? _repository;
  var _generation = 0;
  String? get _authorizationId {
    final ids = uri.queryParametersAll['authorization_id'] ?? const [];
    return ids.length == 1 &&
            ids.single.isNotEmpty &&
            !RegExp(r'\s').hasMatch(ids.single)
        ? ids.single
        : null;
  }

  @override
  OAuthConsentState build() {
    _repository = ref.watch(accountManagementRepositoryProvider);
    ++_generation;
    ref.onDispose(() => _generation++);
    if (_authorizationId != null) Future.microtask(reload);
    return OAuthConsentState(valid: _authorizationId != null);
  }

  Future<void> reload() async {
    final id = _authorizationId;
    if (id == null) return;
    final generation = ++_generation;
    state = const OAuthConsentState(valid: true);
    try {
      final repository = _repository;
      if (repository == null || !repository.isCurrent) {
        throw StateError('Account unavailable');
      }
      final authorization = (await repository.authorization(id)).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      if (authorization case OAuthAuthorizationRedirect(:final redirectUrl)) {
        _redirect(authorization, redirectUrl);
      } else {
        state = OAuthConsentState(valid: true, authorization: authorization);
      }
    } catch (error) {
      if (_repository?.isCurrent == false) return;
      if (ref.mounted && generation == _generation) {
        state = OAuthConsentState(valid: true, loadError: error);
      }
    }
  }

  Future<void> submit(bool approve) async {
    final authorization = state.authorization;
    if (state.action != ConsentAction.idle ||
        authorization is! OAuthAuthorizationDetails ||
        (approve && authorization.unsupportedScopes)) {
      return;
    }
    final repository = _repository;
    if (repository == null || !repository.isCurrent) {
      state = OAuthConsentState(
        valid: true,
        authorization: authorization,
        actionError: StateError('Account unavailable'),
      );
      return;
    }
    final generation = ++_generation;
    state = OAuthConsentState(
      valid: true,
      authorization: authorization,
      action: approve ? ConsentAction.approving : ConsentAction.denying,
    );
    try {
      final redirectUrl = (await repository.consent(
        authorization.authorizationId,
        approve: approve,
      )).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      _redirect(authorization, redirectUrl);
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = OAuthConsentState(
          valid: true,
          authorization: authorization,
          actionError: error,
        );
      }
    }
  }

  void _redirect(OAuthAuthorization authorization, String? url) {
    final uri = url == null || url.trim().isEmpty ? null : Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    final safe =
        uri != null &&
        uri.isAbsolute &&
        scheme != 'javascript' &&
        scheme != 'data' &&
        ((scheme != 'http' && scheme != 'https') || uri.host.isNotEmpty);
    state = OAuthConsentState(
      valid: true,
      authorization: authorization,
      action: ConsentAction.redirecting,
      redirectUrl: safe ? url : null,
      redirectError: !safe,
    );
  }

  void handoffFailed() {
    state = OAuthConsentState(
      valid: state.valid,
      authorization: state.authorization,
      action: state.action,
      redirectError: true,
    );
  }
}
