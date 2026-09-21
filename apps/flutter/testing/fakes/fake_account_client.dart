import 'dart:typed_data';

import 'package:app_account/app_account.dart';

import 'strict_fake.dart';

/// In-memory [AccountClient] double.
///
/// Every call is recorded in its `<method>Calls` list and answers from the
/// mutable fields below.
class FakeAccountClient extends StrictFake implements AccountClient {
  final signInWithAppleCalls = <String?>[];
  final signInWithGoogleCalls = <String?>[];
  final signInWithEmailCalls =
      <({String email, String? redirectTo, String? captchaToken})>[];
  final signInWithPasswordCalls =
      <({String email, String password, String? captchaToken})>[];
  final signUpWithPasswordCalls =
      <({
        String email,
        String password,
        String? redirectTo,
        String? captchaToken,
      })>[];
  final signOutCalls = <void>[];
  final getOAuthAuthorizationCalls = <String>[];
  final approveOAuthAuthorizationCalls = <String>[];
  final denyOAuthAuthorizationCalls = <String>[];
  final listOAuthGrantsCalls = <void>[];
  final revokeOAuthGrantCalls = <String>[];
  final getOverviewCalls = <void>[];
  final getAppleAppAccountTokenCalls = <void>[];
  final getUsagePeriodCalls =
      <({
        String appId,
        String quotaKey,
        DateTime? periodStart,
        DateTime? periodEnd,
      })>[];
  final registerInstallCalls =
      <({
        String appId,
        String deviceId,
        String? platform,
        String? appVersion,
      })>[];
  final consumeQuotaCalls =
      <({
        String appId,
        String quotaKey,
        int units,
        DateTime? periodStart,
        DateTime? periodEnd,
      })>[];
  final pushChangesCalls =
      <({
        String appId,
        String deviceId,
        List<AccountSyncOperation> operations,
      })>[];
  final pushChangesInBatchesCalls =
      <({
        String appId,
        String deviceId,
        List<AccountSyncOperation> operations,
        int batchSize,
      })>[];
  final pullChangesCalls =
      <({String appId, String deviceId, int sinceRevision, int limit})>[];
  final syncHintsCalls = <String>[];
  final broadcastSyncHintCalls = <({String appId, String deviceId})>[];
  final invokeFunctionCalls =
      <({
        String functionName,
        Map<String, String>? headers,
        Object? body,
        Map<String, dynamic>? queryParameters,
        String? region,
      })>[];
  final uploadStorageBytesCalls =
      <({
        String bucket,
        String path,
        List<int> bytes,
        String? contentType,
        bool upsert,
        String cacheControl,
        Map<String, dynamic>? metadata,
        Map<String, String>? headers,
      })>[];
  final downloadStorageBytesCalls = <({String bucket, String path})>[];

  String? currentUserIdValue;
  String? currentEmailValue;
  AccountSession? currentSessionValue;
  AccountAuthState accountAuthState = const AccountAuthState(signedIn: false);
  AccountOverview overviewValue = AccountOverview.empty('');
  String? appleAppAccountTokenValue;
  AccountUsagePeriod usagePeriodValue = const AccountUsagePeriod(
    appId: '',
    quotaKey: '',
    used: 0,
    limit: 0,
    unit: 'count',
  );
  AccountSyncPushResult pushResultValue = const AccountSyncPushResult(
    serverRevision: 1,
    applied: [],
  );
  AccountSyncPullResult pullResultValue = const AccountSyncPullResult(
    nextCursor: 0,
    hasMore: false,
    changes: [],
  );
  Stream<AccountSyncHint> syncHintsValue = const Stream.empty();
  AccountFunctionResponse functionResponseValue = const AccountFunctionResponse(
    status: 200,
  );
  AccountOAuthAuthorization oauthAuthorizationValue =
      const AccountOAuthAuthorizationRedirect(redirectUrl: '');
  AccountOAuthConsentResult oauthConsentResultValue =
      const AccountOAuthConsentResult();
  List<AccountOAuthGrant> oauthGrantsValue = const [];
  String uploadedPath = '';
  Uint8List downloadedBytes = Uint8List(0);

  @override
  String? get currentUserId => currentUserIdValue;

  @override
  String? get currentEmail => currentEmailValue;

  @override
  AccountSession? get currentSession => currentSessionValue;

  @override
  Stream<AccountAuthState> accountAuthStateChanges() {
    return Stream.value(accountAuthState);
  }

  /// Derived from [accountAuthState], the way the real client derives both
  /// channels from one auth event stream.
  @override
  Stream<bool> authStateChanges() {
    return Stream.value(accountAuthState.signedIn);
  }

  @override
  Future<void> signInWithApple({String? redirectTo}) async {
    signInWithAppleCalls.add(redirectTo);
  }

  @override
  Future<void> signInWithGoogle({String? redirectTo}) async {
    signInWithGoogleCalls.add(redirectTo);
  }

  @override
  Future<void> signInWithEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    signInWithEmailCalls.add((
      email: email,
      redirectTo: redirectTo,
      captchaToken: captchaToken,
    ));
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    signInWithPasswordCalls.add((
      email: email,
      password: password,
      captchaToken: captchaToken,
    ));
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) async {
    signUpWithPasswordCalls.add((
      email: email,
      password: password,
      redirectTo: redirectTo,
      captchaToken: captchaToken,
    ));
  }

  @override
  Future<void> signOut() async {
    signOutCalls.add(null);
  }

  @override
  Future<AccountOAuthAuthorization> getOAuthAuthorization(
    String authorizationId,
  ) async {
    getOAuthAuthorizationCalls.add(authorizationId);
    return oauthAuthorizationValue;
  }

  @override
  Future<AccountOAuthConsentResult> approveOAuthAuthorization(
    String authorizationId,
  ) async {
    approveOAuthAuthorizationCalls.add(authorizationId);
    return oauthConsentResultValue;
  }

  @override
  Future<AccountOAuthConsentResult> denyOAuthAuthorization(
    String authorizationId,
  ) async {
    denyOAuthAuthorizationCalls.add(authorizationId);
    return oauthConsentResultValue;
  }

  @override
  Future<List<AccountOAuthGrant>> listOAuthGrants() async {
    listOAuthGrantsCalls.add(null);
    return oauthGrantsValue;
  }

  @override
  Future<void> revokeOAuthGrant(String clientId) async {
    revokeOAuthGrantCalls.add(clientId);
  }

  @override
  Future<AccountOverview> getOverview() async {
    getOverviewCalls.add(null);
    return overviewValue;
  }

  @override
  Future<String?> getAppleAppAccountToken() async {
    getAppleAppAccountTokenCalls.add(null);
    return appleAppAccountTokenValue;
  }

  @override
  Future<AccountUsagePeriod> getUsagePeriod({
    required String appId,
    required String quotaKey,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    getUsagePeriodCalls.add((
      appId: appId,
      quotaKey: quotaKey,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ));
    return usagePeriodValue;
  }

  @override
  Future<void> registerInstall({
    required String appId,
    required String deviceId,
    String? platform,
    String? appVersion,
  }) async {
    registerInstallCalls.add((
      appId: appId,
      deviceId: deviceId,
      platform: platform,
      appVersion: appVersion,
    ));
  }

  @override
  Future<AccountUsagePeriod> consumeQuota({
    required String appId,
    required String quotaKey,
    required int units,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    consumeQuotaCalls.add((
      appId: appId,
      quotaKey: quotaKey,
      units: units,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ));
    return usagePeriodValue;
  }

  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushChangesCalls.add((
      appId: appId,
      deviceId: deviceId,
      operations: operations,
    ));
    return pushResultValue;
  }

  @override
  Future<void> pushChangesInBatches({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
    int batchSize = 100,
  }) async {
    pushChangesInBatchesCalls.add((
      appId: appId,
      deviceId: deviceId,
      operations: operations,
      batchSize: batchSize,
    ));
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    pullChangesCalls.add((
      appId: appId,
      deviceId: deviceId,
      sinceRevision: sinceRevision,
      limit: limit,
    ));
    return pullResultValue;
  }

  @override
  Stream<AccountSyncHint> syncHints({required String appId}) {
    syncHintsCalls.add(appId);
    return syncHintsValue;
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {
    broadcastSyncHintCalls.add((appId: appId, deviceId: deviceId));
  }

  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    invokeFunctionCalls.add((
      functionName: functionName,
      headers: headers,
      body: body,
      queryParameters: queryParameters,
      region: region,
    ));
    return functionResponseValue;
  }

  @override
  Future<String> uploadStorageBytes({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    bool upsert = true,
    String cacheControl = '3600',
    Map<String, dynamic>? metadata,
    Map<String, String>? headers,
  }) async {
    uploadStorageBytesCalls.add((
      bucket: bucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
      upsert: upsert,
      cacheControl: cacheControl,
      metadata: metadata,
      headers: headers,
    ));
    return uploadedPath;
  }

  @override
  Future<Uint8List> downloadStorageBytes({
    required String bucket,
    required String path,
  }) async {
    downloadStorageBytesCalls.add((bucket: bucket, path: path));
    return downloadedBytes;
  }
}
