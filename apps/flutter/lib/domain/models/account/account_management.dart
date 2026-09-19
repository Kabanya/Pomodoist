sealed class OAuthAuthorization {
  const OAuthAuthorization();
}

final class OAuthAuthorizationDetails extends OAuthAuthorization {
  OAuthAuthorizationDetails({
    required this.authorizationId,
    required this.clientName,
    required this.redirectUri,
    required List<String> scopes,
  }) : scopes = List.unmodifiable(scopes);
  final String authorizationId;
  final String? clientName;
  final String redirectUri;
  final List<String> scopes;
  bool get unsupportedScopes =>
      scopes.any(const {'openid', 'profile', 'phone'}.contains);
}

final class OAuthAuthorizationRedirect extends OAuthAuthorization {
  const OAuthAuthorizationRedirect(this.redirectUrl);
  final String redirectUrl;
}

final class ConnectedAgent {
  const ConnectedAgent({
    required this.clientId,
    required this.clientName,
    required this.connectedAt,
  });
  final String clientId;
  final String? clientName;
  final DateTime connectedAt;
}
