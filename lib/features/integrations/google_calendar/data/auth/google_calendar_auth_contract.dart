class GoogleCalendarAuthAccount {
  const GoogleCalendarAuthAccount({this.email, this.displayName});

  final String? email;
  final String? displayName;
}

abstract interface class GoogleCalendarAuthService {
  Future<void> initialize();
  Future<GoogleCalendarAuthAccount> signIn();
  Future<String?> accessToken({bool interactive = false});
  Future<void> disconnect();
}
