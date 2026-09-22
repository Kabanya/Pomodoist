/// Identity of a build flavor.
///
/// Pomodoist ships three builds that must be installable side by side: the
/// development build, the staging build and the production build. Everything
/// that differs between them — the display name, the platform bundle
/// identifiers, the custom URL scheme, the iOS app group and the Windows toast
/// activation GUID — is declared here and nowhere else, so platform
/// configuration, runtime code and release tooling all read one table.
///
/// This file is deliberately pure Dart. It lives under `lib/domain/` because
/// every layer is allowed to depend on domain models, and it imports only
/// `dart:` libraries so that it can be reached from `lib/domain/**` and
/// `lib/data/**` without dragging Flutter or Riverpod across a layer boundary.
/// `String.fromEnvironment` is part of `dart:core`, which is what lets a
/// Flutter-free file read the compile-time `FLUTTER_APP_FLAVOR` define.
enum AppFlavor {
  development,
  staging,
  production;

  /// Name shown under the app icon and in window titles.
  String get displayName => switch (this) {
    AppFlavor.development => 'Pomodoist Dev',
    AppFlavor.staging => 'Pomodoist Stg',
    AppFlavor.production => 'Pomodoist',
  };

  /// Platform application identifier (Android `applicationId`, iOS/macOS
  /// bundle identifier, Linux and Windows application id).
  ///
  /// All three desktop platforms and the mobile platforms share this value.
  String get applicationId => switch (this) {
    AppFlavor.development => 'com.finchforge.pomodoist.dev',
    AppFlavor.staging => 'com.finchforge.pomodoist.stg',
    AppFlavor.production => 'com.finchforge.pomodoist',
  };

  /// Custom URL scheme that routes deep links to this build.
  String get urlScheme => switch (this) {
    AppFlavor.development => 'pomodoist-dev',
    AppFlavor.staging => 'pomodoist-stg',
    AppFlavor.production => 'pomodoist',
  };

  /// iOS app group shared by the app, its watch app and its focus widget.
  String get appGroup => switch (this) {
    AppFlavor.development => 'group.com.pomodoist.dev',
    AppFlavor.staging => 'group.com.pomodoist.stg',
    AppFlavor.production => 'group.com.pomodoist',
  };

  /// Bundle identifier of the embedded watch app.
  String get watchBundleId => '$applicationId.watchkitapp';

  /// Bundle identifier of the watch app's test host.
  String get watchTestsBundleId => '$applicationId.watchkitapp.tests';

  /// Bundle identifier of the iOS focus widget extension.
  String get focusWidgetBundleId => '$applicationId.focuswidget';

  /// Bundle identifier of the iOS/macOS runner test target.
  String get runnerTestsBundleId => '$applicationId.RunnerTests';

  /// GUID Windows uses to activate a toast notification from this build.
  ///
  /// Each flavor needs its own GUID so that notifications posted by one
  /// installed build never wake another one.
  String get windowsToastGuid => switch (this) {
    AppFlavor.development => 'c4d2e8b3-6f75-4029-ab1c-3e8d7f209b45',
    AppFlavor.staging => 'b3c1d7a2-5e64-4f18-9a0b-2d7c6e1f8a34',
    AppFlavor.production => '8681f633-939c-46f5-84cc-18f295e4382c',
  };

  /// Dart entry point this flavor is built from.
  String get entrypoint => switch (this) {
    AppFlavor.development => 'lib/main_development.dart',
    AppFlavor.staging => 'lib/main_staging.dart',
    AppFlavor.production => 'lib/main.dart',
  };

  /// Whether this is the flavor users install from the app stores.
  bool get isProduction => this == AppFlavor.production;
}

/// Raw value of the compile-time `FLUTTER_APP_FLAVOR` define.
///
/// Flutter sets that define automatically when `--flavor <name>` is passed, and
/// leaves it empty otherwise. It is always empty on the web, where the flavor
/// is chosen at runtime from the deployed `config.js` instead.
const String kBuildFlavorName = String.fromEnvironment('FLUTTER_APP_FLAVOR');

/// Parses a flavor name, ignoring case and surrounding whitespace.
///
/// Returns `null` for an empty or unrecognized name, so callers can tell "no
/// flavor was given" apart from "the flavor is production".
AppFlavor? appFlavorFromName(String name) =>
    switch (name.trim().toLowerCase()) {
      'development' => AppFlavor.development,
      'staging' => AppFlavor.staging,
      'production' => AppFlavor.production,
      _ => null,
    };

/// The flavor the current build was compiled for, or `null` when the build
/// carries no `--flavor` (a bare `flutter run`, a unit test, or any web build).
AppFlavor? get buildTimeAppFlavor => appFlavorFromName(kBuildFlavorName);

/// Backing field for [appFlavor]. Keep it private: the value must only change
/// through [setAppFlavor].
AppFlavor _appFlavor = buildTimeAppFlavor ?? AppFlavor.production;

/// The flavor this running process is.
///
/// Initialized to [buildTimeAppFlavor], falling back to
/// [AppFlavor.production] when the build carries no flavor at all. On the web
/// that fallback is temporary: the compile-time define is always empty there
/// because the same image is deployed to staging and production, so bootstrap
/// calls [setAppFlavor] once the runtime configuration has been read.
///
/// Because this is a mutable global rather than a parameter, lower layers
/// (`lib/data/**`, `lib/domain/**`) can read the flavor at any call site
/// without threading it through every constructor and function.
///
/// Initialization order: the compile-time define wins by default; web
/// bootstrap may override it exactly once, before any widget or repository is
/// constructed. The value must not change after startup — code that caches
/// flavor-dependent values (bundle identifiers, notification GUIDs, deep link
/// schemes) reads it once and would not observe a later change.
AppFlavor get appFlavor => _appFlavor;

/// Sets the flavor of the running process.
///
/// Intended to be called exactly once, during bootstrap, before any widget or
/// repository is constructed. It is not named `debugSetAppFlavor` because the
/// web bootstrap legitimately calls it in production builds, not only from
/// tests; see [appFlavor] for the initialization order contract.
void setAppFlavor(AppFlavor flavor) {
  _appFlavor = flavor;
}
