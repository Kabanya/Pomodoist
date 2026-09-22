import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/ui/billing/widgets/purchase_success_screen.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_join_screen.dart';
import 'package:pomodoist/ui/collaboration/widgets/public_project_screen.dart';
import 'package:pomodoist/ui/focus/widgets/focus_screen.dart';
import 'package:pomodoist/ui/google_calendar/widgets/google_calendar_settings_screen.dart';
import 'package:pomodoist/ui/onboarding/widgets/onboarding_gate.dart';
import 'package:pomodoist/ui/planning/widgets/today_screen.dart';
import 'package:pomodoist/ui/productivity/widgets/reports_screen.dart';
import 'package:pomodoist/ui/productivity/widgets/achievements_screen.dart';
import 'package:pomodoist/ui/settings/widgets/settings_screen.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';
import 'package:pomodoist/ui/settings/widgets/keyboard_shortcuts_screen.dart';
import 'package:pomodoist/ui/settings/widgets/telegram_account_link_screen.dart';
import 'package:pomodoist/ui/settings/widgets/captcha_challenge_screen.dart';
import 'package:pomodoist/ui/settings/widgets/oauth_consent_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/browse_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/inbox_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/kanban_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/priority_matrix_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/project_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/label_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/projects_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/search_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/task_detail_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/timeline_screen.dart';
import 'package:pomodoist/ui/tasks/widgets/upcoming_screen.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/auth/password_recovery.dart';
import 'package:pomodoist/ui/core/widgets/app_startup_gate.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/widgets/adaptive_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  bool signedIn() => ref.read(accountSignedInProvider);

  final nativeLinkCoordinator = ref.read(nativeLinkCoordinatorProvider);
  final router = GoRouter(
    initialLocation: initialAppLocationFor(isWeb: kIsWeb, baseUri: Uri.base),
    overridePlatformDefaultLocation: true,
    onEnter: (context, current, next, router) async {
      if (current.uri != next.uri) {
        final guard = ref.read(taskDetailSaveGuardProvider);
        if (guard.hasRegisteredEditors && !await guard.saveAll()) {
          return const Block.stop();
        }
      }
      return const Allow();
    },
    redirect: (_, state) {
      if (ref.read(passwordRecoveryProvider).needsRoute &&
          state.uri.path != '/reset-password') {
        return '/reset-password';
      }
      if (_isLoginCallback(state.uri)) {
        return passwordRecoveryCallbackLocation(state.uri) ??
            _loginCallbackReturnTo(state.uri);
      }
      if (_isFocusDeepLink(state.uri)) {
        return '/focus';
      }
      return webAppRedirectFor(
        isWeb: kIsWeb,
        signedIn: signedIn(),
        uri: state.uri,
      );
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      GoRoute(
        path: '/login',
        redirect: (_, state) => signedIn() ? _authReturnTo(state.uri) : null,
        pageBuilder: (context, state) => NoTransitionPage(
          child: LoginScreen(
            returnTo: _authReturnTo(state.uri),
            initialFailure: accountAuthCallbackFailureFromValue(
              state.uri.queryParameters['authFailure'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/register',
        redirect: (_, state) => signedIn() ? _authReturnTo(state.uri) : null,
        pageBuilder: (context, state) => NoTransitionPage(
          child: RegisterScreen(returnTo: _authReturnTo(state.uri)),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => NoTransitionPage(
          child: PasswordResetScreen(
            fromCallback: state.uri.queryParameters['callback'] == '1',
            initialFailure: accountAuthCallbackFailureFromValue(
              state.uri.queryParameters['authFailure'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/auth/challenge',
        pageBuilder: (context, state) =>
            NoTransitionPage(child: CaptchaChallengeScreen(uri: state.uri)),
      ),
      GoRoute(
        path: '/oauth/consent',
        pageBuilder: (context, state) => NoTransitionPage(
          key: ValueKey(state.uri.toString()),
          child: _OAuthConsentRoute(uri: state.uri),
        ),
      ),
      GoRoute(
        path: '/purchase-success',
        pageBuilder: (context, state) => NoTransitionPage(
          child: PurchaseSuccessScreen(
            returnTo: _purchaseSuccessReturnTo(
              state.uri.queryParameters['returnTo'],
            ),
            source: state.uri.queryParameters['source'],
          ),
        ),
      ),
      GoRoute(
        path: '/telegram-account-link',
        pageBuilder: (context, state) => NoTransitionPage(
          child: TelegramAccountLinkScreen(
            token: state.uri.queryParameters['token'] ?? '',
            botName:
                ref.read(runtimePublicConfigProvider).environment ==
                    RuntimeEnvironment.production
                ? 'pomodoist_bot'
                : 'pomodoist_test_bot',
          ),
        ),
      ),
      GoRoute(
        path: '/shared/join/:token',
        pageBuilder: (context, state) => NoTransitionPage(
          child: CollaborationJoinScreen(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/shared/public/:token',
        pageBuilder: (context, state) => NoTransitionPage(
          child: PublicProjectScreen(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AppStartupGate(
            child: OnboardingGate(
              child: AdaptiveShell(
                location: state.uri.path,
                taskId: state.uri.queryParameters['task'],
                child: child,
              ),
            ),
          );
        },
        routes: [
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) => NoTransitionPage(
              child: SearchScreen(
                initialQuery: state.uri.queryParameters['q'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/today',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TodayScreen()),
          ),
          GoRoute(
            path: '/upcoming',
            pageBuilder: (context, state) => NoTransitionPage(
              child: UpcomingScreen(
                selectedDate: _parseRouteDate(
                  state.uri.queryParameters['date'],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/inbox',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: InboxScreen()),
          ),
          GoRoute(
            path: '/priority-matrix',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PriorityMatrixScreen()),
          ),
          GoRoute(
            path: '/timeline',
            pageBuilder: (context, state) => NoTransitionPage(
              child: TimelineScreen(
                selectedDate: _parseRouteDate(
                  state.uri.queryParameters['date'],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/kanban',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: KanbanScreen(showMobileTitle: false),
            ),
          ),
          GoRoute(
            path: '/focus',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: FocusScreen()),
          ),
          GoRoute(
            path: '/browse',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BrowseScreen()),
          ),
          GoRoute(
            path: '/browse/overdue',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OverdueTasksScreen()),
          ),
          GoRoute(
            path: '/browse/completed',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: CompletedTasksScreen()),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ProjectsScreen(
                showLabels: state.uri.queryParameters['tab'] == 'labels',
              ),
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ReportsScreen()),
          ),
          GoRoute(
            path: '/reports/achievements',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AchievementsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: SettingsScreen(location: state.uri),
            ),
          ),
          GoRoute(
            path: '/settings/shortcuts',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: KeyboardShortcutsScreen()),
          ),
          GoRoute(
            path: '/integrations/google-calendar',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GoogleCalendarSettingsScreen()),
          ),
          GoRoute(
            path: '/label/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: LabelScreen(labelId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/project/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ProjectScreen(projectId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/task/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: TaskDetailScreen(
                key: ValueKey(state.pathParameters['id']),
                taskId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
    ],
  );
  ref.listen(accountSessionProvider, (_, _) => router.refresh());
  ref.listen(passwordRecoveryStateProvider, (_, _) => router.refresh());
  final detachNativeRoutes = nativeLinkCoordinator?.attachRouteSink((location) {
    router.go(location);
    debugPrint('POMODOIST_NATIVE_LINK_HANDLED');
  });
  ref.onDispose(() {
    detachNativeRoutes?.call();
    router.dispose();
  });
  return router;
});

class _OAuthConsentRoute extends ConsumerWidget {
  const _OAuthConsentRoute({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(accountSessionProvider).value;
    return OAuthConsentScreen(
      key: ValueKey((uri.toString(), session?.userId, session?.generation)),
      uri: uri,
    );
  }
}

String initialAppLocationFor({required bool isWeb, required Uri baseUri}) {
  if (!isWeb || !baseUri.path.startsWith('/')) {
    return '/today';
  }
  if (baseUri.path == '/login-callback') {
    final recoveryLocation = passwordRecoveryCallbackLocation(baseUri);
    if (recoveryLocation != null) return recoveryLocation;
    final callbackReturnTo = accountAuthCallbackReturnTo(baseUri);
    final returnTo = callbackReturnTo != null
        ? _localReturnPath(
            callbackReturnTo,
            fallback: '/settings',
            blockedPath: '/login-callback',
          )
        : null;
    final authFailure = safeAccountAuthCallbackFailureValue(baseUri);
    if (returnTo == null && authFailure == null) return '/login-callback';
    return Uri(
      path: '/login-callback',
      queryParameters: {'returnTo': ?returnTo, 'authFailure': ?authFailure},
    ).toString();
  }
  return Uri(
    path: baseUri.path.isEmpty ? '/' : baseUri.path,
    query: baseUri.hasQuery ? baseUri.query : null,
    fragment: baseUri.path == '/auth/challenge' && baseUri.hasFragment
        ? baseUri.fragment
        : null,
  ).toString();
}

String _purchaseSuccessReturnTo(String? value) {
  return _localReturnPath(
    value,
    fallback: '/today',
    blockedPath: '/purchase-success',
  );
}

String _loginCallbackReturnTo(Uri uri) {
  final returnTo = _localReturnPath(
    accountAuthCallbackReturnTo(uri),
    fallback: '/settings',
    blockedPath: '/login-callback',
  );
  final rawFailure =
      uri.queryParameters['authFailure'] ??
      safeAccountAuthCallbackFailureValue(uri);
  final failure = accountAuthCallbackFailureFromValue(rawFailure);
  if (failure == null) return returnTo;
  return Uri(
    path: '/login',
    queryParameters: {
      if (returnTo != '/today') 'returnTo': returnTo,
      if (!failure.isCancelled) 'authFailure': failure.kind.name,
    },
  ).toString();
}

String _authReturnTo(Uri uri) {
  final returnTo = _localReturnPath(
    uri.queryParameters['returnTo'],
    fallback: '/today',
    blockedPath: '/login',
  );
  final path = Uri.parse(returnTo).path;
  return switch (path) {
    '/login' || '/register' || '/login-callback' => '/today',
    _ => returnTo,
  };
}

String _localReturnPath(
  String? value, {
  required String fallback,
  required String blockedPath,
}) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return fallback;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.path == blockedPath) {
    return fallback;
  }
  return uri.toString();
}

bool _isLoginCallback(Uri uri) {
  return (uri.scheme == appFlavor.urlScheme && uri.host == 'login-callback') ||
      uri.path == '/login-callback';
}

bool _isFocusDeepLink(Uri uri) {
  return uri.scheme == appFlavor.urlScheme && uri.host == 'focus';
}

String? webAppRedirectFor({
  required bool isWeb,
  required bool signedIn,
  required Uri uri,
}) {
  if (!isWeb || signedIn || !_requiresWebAccount(uri.path)) {
    return null;
  }
  return Uri(
    path: '/login',
    queryParameters: {'returnTo': uri.toString()},
  ).toString();
}

bool _requiresWebAccount(String path) {
  // A public project link is deliberately readable without an account.
  if (path == '/shared/public' || path.startsWith('/shared/public/')) {
    return false;
  }
  return path != '/login' &&
      path != '/register' &&
      path != '/login-callback' &&
      path != '/reset-password' &&
      path != '/auth/challenge' &&
      path != '/purchase-success';
}

DateTime? _parseRouteDate(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}
