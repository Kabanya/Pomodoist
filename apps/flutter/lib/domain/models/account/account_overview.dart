const pomodoistAccountAppId = 'pomodoist';

final class PomodoistAccountProfile {
  const PomodoistAccountProfile({
    required this.id,
    this.email,
    this.displayName,
    this.isPro = false,
  });

  final String id;
  final String? email;
  final String? displayName;
  final bool isPro;
}

final class PomodoistAccountEntitlement {
  const PomodoistAccountEntitlement({
    required this.appId,
    required this.entitlementId,
    required this.status,
    required this.purchaseType,
    required this.source,
    this.productId,
    this.store,
    this.validUntil,
    this.renewsAt,
  });

  final String appId;
  final String entitlementId;
  final String status;
  final String purchaseType;
  final String source;
  final String? productId;
  final String? store;
  final DateTime? validUntil;
  final DateTime? renewsAt;

  bool get active => status == 'active';
  bool get paid => purchaseType == 'subscription' || purchaseType == 'lifetime';
}

final class PomodoistAccountAppSummary {
  PomodoistAccountAppSummary({
    required this.id,
    required this.displayName,
    List<PomodoistAccountEntitlement> entitlements = const [],
  }) : entitlements = List.unmodifiable(entitlements);

  final String id;
  final String displayName;
  final List<PomodoistAccountEntitlement> entitlements;
}

final class PomodoistAccountOverview {
  PomodoistAccountOverview({
    required this.profile,
    required List<PomodoistAccountAppSummary> apps,
    required this.generatedAt,
  }) : apps = List.unmodifiable(apps);

  factory PomodoistAccountOverview.empty(String userId) =>
      PomodoistAccountOverview(
        profile: PomodoistAccountProfile(id: userId),
        apps: const [],
        generatedAt: DateTime.now().toUtc(),
      );

  final PomodoistAccountProfile profile;
  final List<PomodoistAccountAppSummary> apps;
  final DateTime generatedAt;

  Iterable<PomodoistAccountEntitlement> get entitlements =>
      apps.expand((app) => app.entitlements);
}
