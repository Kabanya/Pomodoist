import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/route_date.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/theme_background.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/core/widgets/resizable_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_metadata_edit.dart';

class _SidebarQuickAddDialog extends StatefulWidget {
  const _SidebarQuickAddDialog({
    required this.onClose,
    required this.onDisposed,
    required this.route,
    required this.initialText,
    required this.dateInText,
    this.defaultDate,
    this.projectId,
    this.labelId,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onDisposed;
  final ModalRoute<dynamic>? route;
  final String initialText;
  final bool dateInText;
  final DateTime? defaultDate;
  final String? projectId;
  final String? labelId;

  @override
  State<_SidebarQuickAddDialog> createState() => _SidebarQuickAddDialogState();
}

class _SidebarQuickAddDialogState extends State<_SidebarQuickAddDialog> {
  bool _voiceActive = false;
  bool _editorActive = false;
  bool _commentExpanded = false;
  bool _expanded = false;
  double _compactHeight = 0;
  Size? _viewportSize;
  double _keyboardInset = 0;
  double _lastKeyboardInset = 0;
  double? _keyboardPanelHeight;
  final _panelKey = GlobalKey();
  bool _disposing = false;
  LocalHistoryEntry? _backEntry;
  final _focus = FocusScopeNode();
  final _composerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _installBackHandler();
    });
  }

  void _installBackHandler() {
    if (_backEntry != null || _voiceActive || Router.maybeOf(context) != null) {
      return;
    }
    final route = widget.route;
    if (route?.navigator == null) return;
    _backEntry = LocalHistoryEntry(
      onRemove: () {
        _backEntry = null;
        if (!_disposing && AppDateTimePicker.dismissFocused()) {
          _installBackHandler();
          return;
        }
        if (!_disposing && !_voiceActive) widget.onClose();
      },
    );
    route!.addLocalHistoryEntry(_backEntry!);
  }

  void _setVoiceActive(bool active) {
    setState(() => _voiceActive = active);
    if (active) {
      _focus.unfocus();
      final back = _backEntry;
      _backEntry = null;
      back?.remove();
    } else {
      _installBackHandler();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_voiceActive) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _backEntry?.remove();
    _focus.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 820;
    if (_viewportSize != media.size || !compact) {
      _viewportSize = media.size;
      _keyboardInset = 0;
      _lastKeyboardInset = 0;
      _keyboardPanelHeight = null;
    }
    if (compact && !_voiceActive && !_editorActive) {
      if (!_expanded &&
          _lastKeyboardInset > 0 &&
          _lastKeyboardInset == _keyboardInset) {
        final panel =
            _panelKey.currentContext?.findRenderObject() as RenderBox?;
        if (panel != null && panel.hasSize) {
          _keyboardPanelHeight = panel.size.height;
        }
      }
      if (media.viewInsets.bottom > _keyboardInset) {
        _keyboardInset = media.viewInsets.bottom;
      }
      _lastKeyboardInset = media.viewInsets.bottom;
    }
    // Menus dismiss the keyboard; grow below the draft instead of moving it down.
    final dockedHeight =
        _keyboardPanelHeight != null && media.viewInsets.bottom < _keyboardInset
        ? _keyboardPanelHeight! + _keyboardInset - media.viewInsets.bottom
        : null;
    final composer = QuickAddComposer(
      key: _composerKey,
      compact: compact,
      expanded: compact && _expanded,
      onExpand: () {
        if (_expanded) return;
        final height = _panelKey.currentContext?.size?.height;
        if (height == null) return;
        setState(() {
          _compactHeight = height;
          _expanded = true;
        });
      },
      initialText: widget.initialText,
      dateInText: widget.dateInText,
      defaultDate: widget.defaultDate,
      projectId: widget.projectId,
      labelId: widget.labelId,
      onCompleted: widget.onClose,
      onCancel: widget.onClose,
      onVoiceSessionChanged: _setVoiceActive,
      onEditorModeChanged: (active) async {
        if (mounted) setState(() => _editorActive = active);
      },
      onCommentExpandedChanged: (expanded) =>
          setState(() => _commentExpanded = expanded),
    );
    final dialog = ExcludeFocus(
      excluding: _voiceActive || _editorActive,
      child: Offstage(
        offstage: _voiceActive || _editorActive,
        child: Stack(
          children: [
            ModalBarrier(
              color: Colors.black54,
              dismissible: true,
              onDismiss: widget.onClose,
            ),
            FocusScope(
              node: _focus,
              child: compact
                  ? Padding(
                      padding: MediaQuery.viewInsetsOf(context),
                      child: SafeArea(
                        bottom: false,
                        minimum: EdgeInsets.only(top: _expanded ? 0 : 16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: _expanded ? 1 : 0),
                                duration: AppMotion.duration(
                                  context,
                                  AppMotion.panel,
                                ),
                                curve: AppMotion.curve,
                                builder: (context, progress, child) => SizedBox(
                                  height: _expanded
                                      ? _compactHeight +
                                            (constraints.maxHeight -
                                                    _compactHeight) *
                                                progress
                                      : dockedHeight?.clamp(
                                          0.0,
                                          constraints.maxHeight,
                                        ),
                                  child: child,
                                ),
                                child: Material(
                                  key: _panelKey,
                                  color: Colors.transparent,
                                  clipBehavior: Clip.antiAlias,
                                  borderRadius: _expanded
                                      ? BorderRadius.zero
                                      : const BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                  child: ThemeBackground(
                                    zone: ThemeBackgroundZone.quickAdd,
                                    blurBehind: true,
                                    color: context.appColors.surface,
                                    child: SafeArea(
                                      top: false,
                                      child: composer,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  : ResizableDialog(
                      background: ThemeBackground(
                        zone: ThemeBackgroundZone.quickAdd,
                        blurBehind: true,
                        color: context.appColors.surface,
                        child: const SizedBox.expand(),
                      ),
                      initialSize: const Size(680, 180),
                      minSize: Size(420, _commentExpanded ? 320 : 180),
                      content: composer,
                      actions: const [],
                    ),
            ),
          ],
        ),
      ),
    );
    if (Router.maybeOf(context) == null) return dialog;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_voiceActive || _editorActive) return false;
        widget.onClose();
        return true;
      },
      child: dialog,
    );
  }
}

final _sidebarQuickAdds =
    Expando<
      ({
        OverlayEntry entry,
        GlobalKey<_SidebarQuickAddDialogState> key,
        Future<void> closed,
      })
    >();

Future<void> showQuickAddDialog(
  BuildContext context, {
  String initialText = '',
  DateTime? defaultDate,
  String? projectId,
  String? labelId,
}) {
  final location = GoRouter.maybeOf(
    context,
  )?.routeInformationProvider.value.uri;
  final segments = location?.pathSegments ?? const <String>[];
  labelId ??= segments.length == 2 && segments.first == 'label'
      ? segments[1]
      : null;
  final overlay = Overlay.of(context, rootOverlay: true);
  final existing = _sidebarQuickAdds[overlay];
  if (existing != null) {
    overlay.rearrange([existing.entry], below: existing.entry);
    existing.key.currentState?._setVoiceActive(false);
    return existing.closed;
  }
  final dateScreen =
      location?.path == '/today' || location?.path == '/upcoming';
  final dateInText = dateScreen && initialText.isEmpty;
  if (dateScreen) {
    final now = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(quickAddNowProvider)().toLocal();
    defaultDate ??=
        (location!.path == '/upcoming'
            ? parseRouteDate(location.queryParameters['date'])
            : null) ??
        DateUtils.dateOnly(now);
    if (dateInText) {
      final token = DateUtils.isSameDay(defaultDate, now)
          ? context.l10n.today
          : quickAddScheduleToken(TaskSchedule.allDay(defaultDate));
      initialText = '$token ';
    }
  }
  final completion = Completer<void>();
  final key = GlobalKey<_SidebarQuickAddDialogState>();
  late final OverlayEntry entry;
  void close({bool remove = true}) {
    if (completion.isCompleted) return;
    completion.complete();
    _sidebarQuickAdds[overlay] = null;
    if (remove) {
      entry.remove();
      entry.dispose();
    }
  }

  final route = ModalRoute.of(context);
  entry = OverlayEntry(
    maintainState: true,
    builder: (_) => _SidebarQuickAddDialog(
      key: key,
      onClose: close,
      onDisposed: () => close(remove: false),
      route: route,
      initialText: initialText,
      dateInText: dateInText,
      defaultDate: defaultDate,
      projectId: projectId,
      labelId: labelId,
    ),
  );
  _sidebarQuickAdds[overlay] = (
    entry: entry,
    key: key,
    closed: completion.future,
  );
  overlay.insert(entry);
  return completion.future;
}
