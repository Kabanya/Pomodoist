import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/billing/purchase_success_screen.dart';
import '../features/focus/presentation/focus_screen.dart';
import '../features/integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import '../features/onboarding/onboarding_gate.dart';
import '../features/planning/presentation/today_screen.dart';
import '../features/productivity/presentation/reports_screen.dart';
import '../features/productivity/presentation/achievements_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/keyboard_shortcuts_screen.dart';
import '../features/settings/presentation/telegram_account_link_screen.dart';
import '../features/settings/presentation/captcha_challenge_screen.dart';
import '../features/settings/presentation/oauth_consent_screen.dart';
import '../features/tasks/presentation/browse_screen.dart';
import '../features/tasks/presentation/inbox_screen.dart';
import '../features/tasks/presentation/kanban/kanban_screen.dart';
import '../features/tasks/presentation/priority_matrix_screen.dart';
import '../features/tasks/presentation/project_screen.dart';
import '../features/tasks/presentation/projects_screen.dart';
import '../features/tasks/presentation/search_screen.dart';
import '../features/tasks/presentation/task_detail_screen.dart';
import '../features/tasks/presentation/timeline_screen.dart';
import '../features/tasks/presentation/upcoming_screen.dart';
import 'account_auth_feedback.dart';
import 'account_providers.dart';
import 'app_startup_gate.dart';
import 'runtime_public_config.dart';
import 'widgets/adaptive_shell.dart';

enum _RouteMotionKind { section, detail }

const _routeMotionBaseline = bool.fromEnvironment('NAVIGATION_MOTION_BASELINE');

Page<void> _motionPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
  _RouteMotionKind kind,
) {
  final detail = kind == _RouteMotionKind.detail;
  if (!detail || _routeMotionBaseline) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        key: const ValueKey('route-motion-detail'),
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              (Directionality.of(context) == TextDirection.rtl ? -24 : 24) *
                  (1 - curved.value),
              0,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  bool signedIn() {
    final authState = ref.read(accountAuthStateProvider).value;
    final account = ref.read(accountClientProvider);
    return authState?.signedIn ?? (account?.currentUserId != null);
  }

  final nativeLinkCoordinator = ref.read(nativeLinkCoordinatorProvider);
  final router = GoRouter(
    initialLocation: initialAppLocationFor(isWeb: kIsWeb, baseUri: Uri.base),
    overridePlatformDefaultLocation: true,
    redirect: (_, state) {
      if (_isLoginCallback(state.uri)) {
        return _loginCallbackReturnTo(state.uri);
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
      ShellRoute(
        builder: (context, state, child) {
          return AppStartupGate(
            child: OnboardingGate(
              child: AdaptiveShell(location: state.uri.path, child: child),
            ),
          );
        },
        routes: [
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const SearchScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/today',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const TodayScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/upcoming',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              UpcomingScreen(
                selectedDate: _parseRouteDate(
                  state.uri.queryParameters['date'],
                ),
              ),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/inbox',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const InboxScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/priority-matrix',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const PriorityMatrixScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/timeline',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              TimelineScreen(
                selectedDate: _parseRouteDate(
                  state.uri.queryParameters['date'],
                ),
              ),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/kanban',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const KanbanScreen(showMobileTitle: false),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/focus',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const FocusScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/browse',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const BrowseScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/browse/completed',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const CompletedTasksScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const ProjectsScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const ReportsScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/reports/achievements',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const AchievementsScreen(),
              _RouteMotionKind.detail,
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const SettingsScreen(),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/settings/shortcuts',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              const KeyboardShortcutsScreen(),
              _RouteMotionKind.detail,
            ),
          ),
          GoRoute(
            path: '/integrations/google-calendar',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GoogleCalendarSettingsScreen()),
          ),
          GoRoute(
            path: '/project/:id',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              ProjectScreen(projectId: state.pathParameters['id']!),
              _RouteMotionKind.section,
            ),
          ),
          GoRoute(
            path: '/task/:id',
            pageBuilder: (context, state) => _motionPage(
              context,
              state,
              TaskDetailScreen(taskId: state.pathParameters['id']!),
              _RouteMotionKind.detail,
            ),
          ),
        ],
      ),
    ],
  );
  ref.listen(accountAuthStateProvider, (_, _) => router.refresh());
  ref.listen(accountClientProvider, (_, _) => router.refresh());
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
    final account = ref.watch(accountClientProvider);
    final authState = ref.watch(accountAuthStateProvider).value;
    final userId = account?.currentUserId ?? authState?.session?.userId;
    return OAuthConsentScreen(
      key: ValueKey((uri.toString(), identityHashCode(account), userId)),
      uri: uri,
    );
  }
}

String initialAppLocationFor({required bool isWeb, required Uri baseUri}) {
  if (!isWeb || !baseUri.path.startsWith('/')) {
    return '/today';
  }
  if (baseUri.path == '/login-callback') {
    final returnToValues = baseUri.queryParametersAll['returnTo'];
    final returnTo = returnToValues?.length == 1
        ? _localReturnPath(
            returnToValues!.single,
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
    uri.queryParameters['returnTo'],
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
  return (uri.scheme == 'pomodoist' && uri.host == 'login-callback') ||
      uri.path == '/login-callback';
}

bool _isFocusDeepLink(Uri uri) {
  return uri.scheme == 'pomodoist' && uri.host == 'focus';
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
  return path != '/login' &&
      path != '/register' &&
      path != '/login-callback' &&
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
