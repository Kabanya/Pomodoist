import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Matches the mixed Material/Shadcn environment used by both app roots.
Widget testAppBuilder(BuildContext context, Widget? child) {
  final material = Theme.of(context);
  final theme = material.extension<AppThemePalette>() != null
      ? material
      : (material.brightness == Brightness.dark
                ? AppTheme.dark()
                : AppTheme.light())
            .copyWith(platform: material.platform);
  return Localizations.override(
    context: context,
    delegates: const [TestShadLocalizations()],
    child: Theme(
      data: theme,
      child: ShadTheme(
        data: AppTheme.shadFromMaterial(
          theme,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
        child: ShadAppBuilder(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}

// Deferred translations are prepared outside widget tests' fake async clock.
class TestShadLocalizations
    extends LocalizationsDelegate<ShadLocalizationsData> {
  const TestShadLocalizations();
  static final translations = <Locale, ShadLocalizationsData>{};
  @override
  bool isSupported(Locale locale) => translations.containsKey(locale);
  @override
  Future<ShadLocalizationsData> load(Locale locale) =>
      SynchronousFuture(translations[locale]!);
  @override
  bool shouldReload(TestShadLocalizations old) => false;
}

Future<void> loadTestAppResources() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Load bundled fonts and deferred translations before widget tests enter
  // fake async, matching the assets available to the running application.
  for (final family in ['Geist', 'GeistMono']) {
    await (FontLoader('packages/shadcn_ui/$family')..addFont(
          rootBundle.load('packages/shadcn_ui/fonts/$family[wght].ttf'),
        ))
        .load();
  }
  for (final locale in AppLocalizations.supportedLocales) {
    TestShadLocalizations.translations[locale] = await GlobalShadLocalizations
        .delegate
        .load(locale);
  }
}
