import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/account/avatar_emoji.dart';
import 'package:pomodoist/domain/models/habits/habit_icons.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

IconData habitIconData(String? name) => switch (name) {
  'bookOpen' => LucideIcons.bookOpen,
  'dumbbell' => LucideIcons.dumbbell,
  'footprints' => LucideIcons.footprints,
  'glassWater' => LucideIcons.glassWater,
  'moon' => LucideIcons.moon,
  'sun' => LucideIcons.sun,
  'heart' => LucideIcons.heart,
  'brain' => LucideIcons.brain,
  'apple' => LucideIcons.apple,
  'coffee' => LucideIcons.coffee,
  'music' => LucideIcons.music,
  'pencil' => LucideIcons.pencil,
  'code' => LucideIcons.code,
  'leaf' => LucideIcons.leaf,
  'target' => LucideIcons.target,
  'bike' => LucideIcons.bike,
  _ => LucideIcons.repeat2,
};

class HabitSign extends StatelessWidget {
  const HabitSign({required this.icon, super.key});
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final emoji = readAvatarEmoji(icon);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: emoji == null
          ? Icon(habitIconData(icon), size: 18, color: colors.mutedText)
          : Text(
              emoji,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 20),
            ),
    );
  }
}

class HabitIconButton extends StatelessWidget {
  const HabitIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.habitIcon,
    child: Semantics(
      label: context.l10n.habitIcon,
      child: ShadButton.ghost(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        enabled: onPressed != null,
        onPressed: onPressed,
        child: HabitSign(icon: icon),
      ),
    ),
  );
}

Future<void> showHabitIconPicker(
  BuildContext context, {
  required String? icon,
  required Future<bool> Function(String?) onSave,
}) => showDialog<void>(
  context: context,
  animationStyle: AnimationStyle(
    duration: AppMotion.duration(context, AppMotion.popup),
    reverseDuration: AppMotion.duration(context, AppMotion.popup),
    curve: AppMotion.curve,
  ),
  builder: (_) => _HabitIconPicker(icon: icon, onSave: onSave),
);

class _HabitIconPicker extends StatefulWidget {
  const _HabitIconPicker({required this.icon, required this.onSave});
  final String? icon;
  final Future<bool> Function(String?) onSave;
  @override
  State<_HabitIconPicker> createState() => _HabitIconPickerState();
}

class _HabitIconPickerState extends State<_HabitIconPicker> {
  late String? _icon = widget.icon;
  late bool _emojiTab = !HabitIcon.values.any((i) => i.name == widget.icon);
  bool _saving = false;
  bool _error = false;

  Future<void> _select(String? value) async {
    if (_saving) return;
    try {
      final selected = normalizeHabitIcon(value);
      setState(() {
        _icon = selected;
        _saving = true;
        _error = false;
      });
      final saved = await widget.onSave(selected);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, colors = context.appColors;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.habitIcon,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ExcludeSemantics(child: HabitSign(icon: _icon)),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l.habitIconEmoji),
                      selected: _emojiTab,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _emojiTab = true),
                    ),
                    ChoiceChip(
                      label: Text(l.habitIconIcons),
                      selected: !_emojiTab,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _emojiTab = false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_emojiTab)
                  ExcludeFocus(
                    excluding: _saving,
                    child: IgnorePointer(
                      ignoring: _saving,
                      child: LayoutBuilder(
                        builder: (context, space) => EmojiPicker(
                          onEmojiSelected: (_, emoji) => _select(emoji.emoji),
                          config: Config(
                            height: 280,
                            locale: Localizations.localeOf(context),
                            checkPlatformCompatibility: false,
                            emojiViewConfig: EmojiViewConfig(
                              columns: (space.maxWidth / 48).floor().clamp(
                                1,
                                10,
                              ),
                              backgroundColor: colors.surface,
                              emojiSizeMax: 28,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: colors.surface,
                              indicatorColor: colors.secondaryText,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            searchViewConfig: SearchViewConfig(
                              backgroundColor: colors.surface,
                              buttonIconColor: colors.secondaryText,
                              inputTextStyle: Theme.of(
                                context,
                              ).textTheme.bodyMedium,
                              hintText: l.navSearch,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              initCategory: Category.SMILEYS,
                              recentTabBehavior: RecentTabBehavior.NONE,
                              tabIndicatorAnimDuration: AppMotion.duration(
                                context,
                                AppMotion.popup,
                              ),
                              customCategoryView: (_, state, tabs, pages) =>
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TabBar(
                                          controller: tabs,
                                          isScrollable: true,
                                          tabAlignment: TabAlignment.start,
                                          dividerColor: colors.border,
                                          labelColor: colors.accent,
                                          unselectedLabelColor:
                                              colors.secondaryText,
                                          indicatorColor: colors.accent,
                                          onTap: pages.jumpToPage,
                                          tabs: [
                                            for (final category
                                                in state.categoryEmoji)
                                              Tab(
                                                height: 48,
                                                text: _categoryLabel(
                                                  context,
                                                  category.category,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l.navSearch,
                                        onPressed: state.onShowSearchView,
                                        icon: const Icon(
                                          LucideIcons.search,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final icon in HabitIcon.values)
                        Semantics(
                          selected: _icon == icon.name,
                          child: IconButton.outlined(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            tooltip: l.habitIconOption(icon.name),
                            isSelected: _icon == icon.name,
                            onPressed: _saving
                                ? null
                                : () => _select(icon.name),
                            icon: Icon(habitIconData(icon.name), size: 20),
                          ),
                        ),
                    ],
                  ),
                if (_error) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l.habitSaveError,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  ShadButton.ghost(
                    enabled: !_saving,
                    onPressed: () => _select(_icon),
                    child: Text(l.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_saving)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ShadButton.ghost(
                height: 48,
                enabled: !_saving,
                onPressed: () => _select(null),
                child: Text(l.habitIconReset),
              ),
              ShadButton.ghost(
                height: 48,
                enabled: !_saving,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.commonCancel),
              ),
            ],
          ),
        ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: MediaQuery.sizeOf(context).width < 600
          ? Dialog.fullscreen(
              child: SafeArea(
                child: Material(color: colors.surface, child: content),
              ),
            )
          : Dialog(
              constraints: const BoxConstraints(maxWidth: 560),
              child: content,
            ),
    );
  }
}

String _categoryLabel(BuildContext context, Category category) =>
    switch (category) {
      Category.RECENT => context.l10n.habitIconEmoji,
      Category.SMILEYS => context.l10n.accountAvatarSmileys,
      Category.ANIMALS => context.l10n.accountAvatarAnimals,
      Category.FOODS => context.l10n.accountAvatarFood,
      Category.ACTIVITIES => context.l10n.accountAvatarActivities,
      Category.TRAVEL => context.l10n.accountAvatarTravel,
      Category.OBJECTS => context.l10n.accountAvatarObjects,
      Category.SYMBOLS => context.l10n.accountAvatarSymbols,
      Category.FLAGS => context.l10n.accountAvatarFlags,
    };
