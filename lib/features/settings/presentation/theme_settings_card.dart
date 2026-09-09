import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/app_l10n.dart';
import '../../../app/app_theme_mode.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_theme_settings.dart';
import '../../../app/theme/theme_background.dart';
import '../../../app/theme/theme_image_preparation.dart';
import '../../../l10n/app_localizations.dart';

bool themeEditorCanSave(Iterable<String> colors) =>
    colors.every((value) => parseThemeColor(value) != null);

bool themeHasLowContrast(AppThemePalette colors) => [
  (colors.primaryText, colors.canvas),
  (colors.primaryText, colors.surface),
  (colors.primaryText, colors.surfaceTint),
  (colors.secondaryText, colors.canvas),
  (colors.secondaryText, colors.surface),
  (colors.mutedText, colors.canvas),
  (colors.mutedText, colors.surface),
  (colors.onAccent, colors.accentFill),
  (colors.onError, colors.error),
].any((pair) => themeContrastRatio(pair.$1, pair.$2) < 4.5);

String _themeName(AppLocalizations l10n, AppThemeDefinition theme) =>
    switch (theme.id) {
      'classic' => l10n.themeClassic,
      'ocean' => l10n.themeOcean,
      'forest' => l10n.themeForest,
      'sepia' => l10n.themeSepia,
      'graphite' => l10n.themeGraphite,
      'custom' => l10n.themeCustom,
      _ => theme.name,
    };

String _colorName(AppLocalizations l10n, AppThemeColor color) =>
    switch (color) {
      AppThemeColor.canvas => l10n.themeColorCanvas,
      AppThemeColor.surface => l10n.themeColorSurface,
      AppThemeColor.surfaceTint => l10n.themeColorSurfaceTint,
      AppThemeColor.surfaceHover => l10n.themeColorSurfaceHover,
      AppThemeColor.primaryText => l10n.themeColorPrimaryText,
      AppThemeColor.secondaryText => l10n.themeColorSecondaryText,
      AppThemeColor.mutedText => l10n.themeColorMutedText,
      AppThemeColor.border => l10n.themeColorBorder,
      AppThemeColor.accent => l10n.themeColorAccent,
      AppThemeColor.accentFill => l10n.themeColorAccentFill,
      AppThemeColor.accentTint => l10n.themeColorAccentTint,
      AppThemeColor.warning => l10n.themeColorWarning,
      AppThemeColor.info => l10n.themeColorInfo,
      AppThemeColor.success => l10n.themeColorSuccess,
      AppThemeColor.error => l10n.themeColorError,
      AppThemeColor.overdue => l10n.themeColorOverdue,
      AppThemeColor.onAccent => l10n.themeColorOnAccent,
      AppThemeColor.onError => l10n.themeColorOnError,
    };

class ThemeSettingsCard extends ConsumerWidget {
  const ThemeSettingsCard({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.themeSaveError)));
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(appThemeSettingsProvider.notifier);
    final brightness = Theme.of(context).brightness;
    controller.beginEdit();
    final safeTheme = brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Theme(
          data: safeTheme,
          child: ShadTheme(
            data: AppTheme.shadFromMaterial(
              safeTheme,
              reduceMotion: MediaQuery.disableAnimationsOf(context),
            ),
            child: _ThemeEditor(initialBrightness: brightness),
          ),
        ),
      );
    } finally {
      controller.cancelPreview();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appThemeSettingsProvider);
    final mode = ref.watch(appThemeModeProvider);
    final enabled =
        settings.isLoaded && !settings.isSaving && settings.preview == null;
    Widget choices(Iterable<AppThemeDefinition> themes) => LayoutBuilder(
      builder: (context, constraints) {
        final width =
            ((constraints.maxWidth - 8 * (themes.length - 1)) / themes.length)
                .clamp(144.0, double.infinity);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              for (final theme in themes)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        selected: settings.selectedId == theme.id,
                        child: OutlinedButton(
                          onPressed: enabled
                              ? () => _run(
                                  context,
                                  () => ref
                                      .read(appThemeSettingsProvider.notifier)
                                      .selectTheme(theme.id),
                                )
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 16,
                            ),
                            side: BorderSide(
                              color: settings.selectedId == theme.id
                                  ? context.appColors.accent
                                  : context.appColors.border,
                              width: settings.selectedId == theme.id ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _themeName(l10n, theme),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (settings.selectedId == theme.id)
                                    const Icon(LucideIcons.check, size: 18),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _PalettePair(theme: theme, compact: true),
                            ],
                          ),
                        ),
                      ),
                      if (!theme.isBuiltIn)
                        ShadButton.ghost(
                          enabled: enabled,
                          onPressed: () => _edit(context, ref),
                          child: Text(l10n.themeCustomize),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsThemeTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsThemeSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<AppThemeMode>(
                key: const Key('settings-theme-mode-select'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    icon: const Icon(LucideIcons.sunMoon),
                    label: Text(l10n.settingsThemeSystem),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    icon: const Icon(LucideIcons.sun),
                    label: Text(l10n.settingsThemeLight),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    icon: const Icon(LucideIcons.moon),
                    label: Text(l10n.settingsThemeDark),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => _run(
                  context,
                  () => ref
                      .read(appThemeModeProvider.notifier)
                      .setThemeMode(selection.single),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (settings.loadFailed) ...[
              Text(l10n.themeLoadError),
              ShadButton.outline(
                onPressed: () => _run(
                  context,
                  () => ref.read(appThemeSettingsProvider.notifier).load(),
                ),
                child: Text(l10n.commonRetry),
              ),
            ] else if (!settings.isLoaded)
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            choices(settings.themes),
          ],
        ),
      ),
    );
  }
}

class _PalettePair extends StatelessWidget {
  const _PalettePair({
    required this.theme,
    this.compact = false,
    this.backgroundZone = ThemeBackgroundZone.main,
  });
  final AppThemeDefinition theme;
  final bool compact;
  final ThemeBackgroundZone backgroundZone;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, entry) in [
        (context.l10n.settingsThemeLight, theme.light),
        (context.l10n.settingsThemeDark, theme.dark),
      ].indexed) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(entry.$1, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ThemeBackgroundPreview(
                  image: theme.backgrounds.resolve(
                    backgroundZone,
                    index == 0 ? Brightness.light : Brightness.dark,
                  ),
                  color: backgroundZone == ThemeBackgroundZone.sidebar
                      ? entry.$2.surface
                      : entry.$2.canvas,
                  child: Container(
                    padding: EdgeInsets.all(compact ? 8 : 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: entry.$2.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact) ...[
                          Text(
                            context.l10n.themePreviewTask,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: entry.$2.primaryText),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.themePreviewSecondary,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: entry.$2.secondaryText),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Container(
                          padding: EdgeInsets.all(compact ? 4 : 8),
                          decoration: BoxDecoration(
                            color: entry.$2.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: entry.$2.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.circleCheck,
                                color: entry.$2.accent,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Container(
                                  height: 3,
                                  color: entry.$2.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: entry.$2.accentFill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: compact
                              ? SizedBox(
                                  height: 8,
                                  child: Center(
                                    child: Icon(
                                      LucideIcons.plus,
                                      size: 10,
                                      color: entry.$2.onAccent,
                                    ),
                                  ),
                                )
                              : Text(
                                  context.l10n.commonAdd,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: entry.$2.onAccent),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _ThemeEditor extends ConsumerStatefulWidget {
  const _ThemeEditor({required this.initialBrightness});
  final Brightness initialBrightness;

  @override
  ConsumerState<_ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends ConsumerState<_ThemeEditor> {
  late final AppThemeDefinition _initial = ref
      .read(appThemeSettingsProvider)
      .preview!;
  late Brightness _brightness = widget.initialBrightness;
  AppThemeColor? _expanded = AppThemeColor.accent;
  late final Map<(Brightness, AppThemeColor), String> _hex = {
    for (final pair in [
      (Brightness.light, _initial.light),
      (Brightness.dark, _initial.dark),
    ])
      for (final entry in pair.$2.values.entries)
        (pair.$1, entry.key): themeColorHex(entry.value),
  };
  bool _saveFailed = false;
  ThemeBackgroundZone _backgroundZone = ThemeBackgroundZone.main;
  String? _imageError;

  ThemeBackgroundZone get _editingZone =>
      ref.read(appThemeSettingsProvider).preview!.backgrounds.mode ==
          ThemeBackgroundMode.separate
      ? _backgroundZone
      : ThemeBackgroundZone.main;

  void _backgroundContextChanged({
    Brightness? brightness,
    ThemeBackgroundZone? zone,
    ThemeBackgroundMode? mode,
  }) {
    final controller = ref.read(appThemeSettingsProvider.notifier);
    controller.cancelImageSelection();
    if (mode != null) {
      final draft = ref.read(appThemeSettingsProvider).preview!;
      controller.updatePreview(
        draft.copyWith(backgrounds: draft.backgrounds.copyWith(mode: mode)),
      );
    }
    setState(() {
      _brightness = brightness ?? _brightness;
      _backgroundZone = zone ?? _backgroundZone;
      _imageError = null;
    });
  }

  void _changeBackground(ThemeBackgroundImage image) {
    final controller = ref.read(appThemeSettingsProvider.notifier);
    final draft = ref.read(appThemeSettingsProvider).preview!;
    controller.updatePreview(
      draft.copyWith(
        backgrounds: draft.backgrounds.withImage(
          _editingZone,
          _brightness,
          image,
        ),
      ),
    );
  }

  Future<void> _pickBackground() async {
    setState(() => _imageError = null);
    try {
      await ref
          .read(appThemeSettingsProvider.notifier)
          .chooseBackground(
            _editingZone,
            _brightness,
            () => openFile(
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: 'Images',
                  extensions: [
                    'jpg',
                    'jpeg',
                    'png',
                    'webp',
                    'gif',
                    'bmp',
                    'heic',
                    'heif',
                    'tif',
                    'tiff',
                  ],
                  mimeTypes: ['image/*'],
                  uniformTypeIdentifiers: ['public.image'],
                ),
              ],
            ),
          );
    } catch (error) {
      if (mounted) {
        setState(
          () => _imageError = error is ThemeImageTooLargeException
              ? context.l10n.themeBackgroundTooLarge
              : context.l10n.themeBackgroundImageError,
        );
      }
    }
  }

  void _reset() {
    ref.read(appThemeSettingsProvider.notifier).resetPreviewToClassic();
    setState(() {
      _hex.updateAll(
        (key, _) => themeColorHex(
          (key.$1 == Brightness.light
                  ? AppTheme.classicLight
                  : AppTheme.classicDark)
              .values[key.$2]!,
        ),
      );
      _saveFailed = false;
      _imageError = null;
    });
  }

  void _changeColor(AppThemeColor role, String raw) {
    setState(() => _hex[(_brightness, role)] = raw);
    final color = parseThemeColor(raw);
    if (color == null) return;
    final controller = ref.read(appThemeSettingsProvider.notifier);
    final draft = ref.read(appThemeSettingsProvider).preview!;
    controller.updatePreview(
      _brightness == Brightness.light
          ? draft.copyWith(light: draft.light.withColor(role, color))
          : draft.copyWith(dark: draft.dark.withColor(role, color)),
    );
  }

  Future<void> _save() async {
    setState(() => _saveFailed = false);
    try {
      await ref.read(appThemeSettingsProvider.notifier).savePreview();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appThemeSettingsProvider);
    final draft = settings.preview ?? _initial;
    final palette = _brightness == Brightness.light ? draft.light : draft.dark;
    final l10n = context.l10n;
    final zone = draft.backgrounds.mode == ThemeBackgroundMode.separate
        ? _backgroundZone
        : ThemeBackgroundZone.main;
    final background = draft.backgrounds.imageFor(zone, _brightness);
    final backgroundModes = {
      ThemeBackgroundMode.mainOnly: l10n.themeBackgroundMainOnly,
      ThemeBackgroundMode.wholeApp: l10n.themeBackgroundWholeApp,
      ThemeBackgroundMode.separate: l10n.themeBackgroundSeparate,
    };
    final backgroundZones = {
      ThemeBackgroundZone.main: l10n.themeBackgroundMain,
      ThemeBackgroundZone.sidebar: l10n.themeBackgroundSidebar,
      ThemeBackgroundZone.quickAdd: l10n.themeBackgroundQuickAdd,
    };
    final groups = [
      (
        l10n.themeColorsSurfaces,
        [
          AppThemeColor.canvas,
          AppThemeColor.surface,
          AppThemeColor.surfaceTint,
          AppThemeColor.surfaceHover,
          AppThemeColor.border,
        ],
      ),
      (
        l10n.themeColorsText,
        [
          AppThemeColor.primaryText,
          AppThemeColor.secondaryText,
          AppThemeColor.mutedText,
        ],
      ),
      (
        l10n.themeColorsAccent,
        [
          AppThemeColor.accent,
          AppThemeColor.accentFill,
          AppThemeColor.accentTint,
          AppThemeColor.onAccent,
        ],
      ),
      (
        l10n.themeColorsStatus,
        [
          AppThemeColor.warning,
          AppThemeColor.info,
          AppThemeColor.success,
          AppThemeColor.error,
          AppThemeColor.overdue,
          AppThemeColor.onError,
        ],
      ),
    ];
    void cancel() {
      if (!settings.isSaving) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: !settings.isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(appThemeSettingsProvider.notifier).cancelPreview();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): cancel},
        child: AlertDialog(
          insetPadding: const EdgeInsets.all(16),
          // A tight width bypasses AlertDialog's intrinsic sizing, which the
          // RGB sliders' LayoutBuilder cannot provide.
          constraints: const BoxConstraints.tightFor(width: 820),
          scrollable: true,
          title: Text(l10n.themeEditorTitle),
          content: SizedBox(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.themeLivePreview),
                const SizedBox(height: 16),
                _PalettePair(theme: draft, backgroundZone: zone),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<Brightness>(
                    segments: [
                      ButtonSegment(
                        value: Brightness.light,
                        label: Text(l10n.settingsThemeLight),
                        icon: const Icon(LucideIcons.sun),
                      ),
                      ButtonSegment(
                        value: Brightness.dark,
                        label: Text(l10n.settingsThemeDark),
                        icon: const Icon(LucideIcons.moon),
                      ),
                    ],
                    selected: {_brightness},
                    onSelectionChanged: settings.isSaving
                        ? null
                        : (selection) => _backgroundContextChanged(
                            brightness: selection.single,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.themeBackgroundTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in backgroundModes.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: draft.backgrounds.mode == entry.key,
                        onSelected: settings.isSaving
                            ? null
                            : (_) => _backgroundContextChanged(mode: entry.key),
                      ),
                  ],
                ),
                if (draft.backgrounds.mode == ThemeBackgroundMode.separate) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in backgroundZones.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: zone == entry.key,
                          onSelected: settings.isSaving
                              ? null
                              : (_) =>
                                    _backgroundContextChanged(zone: entry.key),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ThemeBackgroundPreview(
                    image: background,
                    color: zone == ThemeBackgroundZone.sidebar
                        ? palette.surface
                        : palette.canvas,
                    child: SizedBox(
                      height: 140,
                      child: background.imageId == null
                          ? Center(
                              child: Text(
                                l10n.themeBackgroundEmpty,
                                style: TextStyle(color: palette.primaryText),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      enabled: !settings.isSaving && !settings.isPreparingImage,
                      onPressed: _pickBackground,
                      child: Text(
                        background.imageId == null
                            ? l10n.themeBackgroundChoose
                            : l10n.themeBackgroundReplace,
                      ),
                    ),
                    if (background.imageId != null)
                      ShadButton.ghost(
                        enabled: !settings.isSaving,
                        onPressed: () {
                          ref
                              .read(appThemeSettingsProvider.notifier)
                              .cancelImageSelection();
                          _changeBackground(
                            background.copyWith(clearImage: true),
                          );
                          setState(() => _imageError = null);
                        },
                        child: Text(l10n.themeBackgroundRemove),
                      ),
                  ],
                ),
                if (settings.isPreparingImage)
                  Semantics(
                    liveRegion: true,
                    child: Text(l10n.themeBackgroundLoading),
                  ),
                if (_imageError != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _imageError!,
                      style: TextStyle(color: context.appColors.error),
                    ),
                  ),
                Text(
                  '${l10n.themeBackgroundDim}: ${(background.dim * 100).round()}%',
                ),
                Slider(
                  value: background.dim,
                  divisions: 100,
                  label: '${(background.dim * 100).round()}%',
                  semanticFormatterCallback: (value) =>
                      '${l10n.themeBackgroundDim}: ${(value * 100).round()}%',
                  onChanged: settings.isSaving || background.imageId == null
                      ? null
                      : (value) =>
                            _changeBackground(background.copyWith(dim: value)),
                ),
                Text('${l10n.themeBackgroundBlur}: ${background.blur.round()}'),
                Slider(
                  value: background.blur,
                  max: 20,
                  divisions: 20,
                  label: '${background.blur.round()}',
                  semanticFormatterCallback: (value) =>
                      '${l10n.themeBackgroundBlur}: ${value.round()}',
                  onChanged: settings.isSaving || background.imageId == null
                      ? null
                      : (value) =>
                            _changeBackground(background.copyWith(blur: value)),
                ),
                if (themeHasLowContrast(draft.light) ||
                    themeHasLowContrast(draft.dark))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l10n.themeLowContrast,
                      style: TextStyle(color: context.appColors.warning),
                    ),
                  ),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8),
                    child: Text(
                      group.$1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final role in group.$2)
                    _ColorEditorRow(
                      key: ValueKey((_brightness, role)),
                      label: _colorName(l10n, role),
                      hex: _hex[(_brightness, role)]!,
                      color: palette.values[role]!,
                      expanded: _expanded == role,
                      enabled: !settings.isSaving,
                      onToggle: () => setState(
                        () => _expanded = _expanded == role ? null : role,
                      ),
                      onChanged: (raw) => _changeColor(role, raw),
                    ),
                ],
                if (_hex.values.any((value) => parseThemeColor(value) == null))
                  Text(
                    l10n.themeInvalidHex,
                    style: TextStyle(color: context.appColors.error),
                  ),
                if (_saveFailed)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.themeSaveError,
                      style: TextStyle(color: context.appColors.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            ShadButton.ghost(
              enabled: !settings.isSaving,
              onPressed: _reset,
              child: Text(l10n.themeResetToClassic),
            ),
            ShadButton.ghost(
              enabled: !settings.isSaving,
              onPressed: cancel,
              child: Text(l10n.commonCancel),
            ),
            ShadButton(
              enabled:
                  !settings.isSaving &&
                  !settings.isPreparingImage &&
                  themeEditorCanSave(_hex.values),
              onPressed: _save,
              leading: settings.isSaving
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.appColors.onAccent,
                      ),
                    )
                  : null,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorEditorRow extends StatefulWidget {
  const _ColorEditorRow({
    required this.label,
    required this.hex,
    required this.color,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.onChanged,
    super.key,
  });
  final String label;
  final String hex;
  final Color color;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorEditorRow> createState() => _ColorEditorRowState();
}

class _ColorEditorRowState extends State<_ColorEditorRow> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.hex,
  );
  late final List<ShadSliderController> _rgb = [
    for (final shift in [16, 8, 0])
      ShadSliderController(
        initialValue: ((widget.color.toARGB32() >> shift) & 255).toDouble(),
      ),
  ];

  @override
  void didUpdateWidget(covariant _ColorEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hex.text != widget.hex) {
      _hex.value = TextEditingValue(
        text: widget.hex,
        selection: TextSelection.collapsed(offset: widget.hex.length),
      );
    }
    for (var index = 0; index < 3; index++) {
      _rgb[index].value = ((widget.color.toARGB32() >> (16 - index * 8)) & 255)
          .toDouble();
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    for (final slider in _rgb) {
      slider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invalid = parseThemeColor(widget.hex) == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                expanded: widget.expanded,
                child: IconButton(
                  tooltip: '${widget.label} · RGB',
                  onPressed: widget.enabled ? widget.onToggle : null,
                  icon: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.color,
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(widget.label)),
              const SizedBox(width: 8),
              SizedBox(
                width: 116,
                child: Semantics(
                  label: '${widget.label} HEX',
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: ShadInput(
                      controller: _hex,
                      enabled: widget.enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: AppTheme.monoTextStyle.copyWith(
                        color: invalid
                            ? context.appColors.error
                            : context.appColors.primaryText,
                      ),
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (invalid)
            Text(
              context.l10n.themeInvalidHex,
              style: TextStyle(color: context.appColors.error),
            ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 12,
                end: 8,
                bottom: 8,
              ),
              child: Column(
                children: [
                  for (final (index, channel) in ['R', 'G', 'B'].indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Text(channel)),
                          Expanded(
                            child: Semantics(
                              label: '${widget.label} $channel',
                              child: ShadSlider(
                                controller: _rgb[index],
                                min: 0,
                                max: 255,
                                divisions: 255,
                                enabled: widget.enabled,
                                semanticFormatterCallback: (value) =>
                                    value.round().toString(),
                                onChanged: (value) {
                                  final channels = _rgb
                                      .map((slider) => slider.value.round())
                                      .toList();
                                  channels[index] = value.round();
                                  widget.onChanged(
                                    themeColorHex(
                                      Color.fromARGB(
                                        255,
                                        channels[0],
                                        channels[1],
                                        channels[2],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${_rgb[index].value.round()}',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
