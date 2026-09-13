import '../../../app/theme/app_theme_settings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_l10n.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_background.dart';
import '../../../app/widgets/app_date_time_picker.dart';
import '../../../app/widgets/resizable_dialog.dart';
import 'widgets/quick_add_bar.dart';

class _SidebarQuickAddDialog extends StatefulWidget {
  const _SidebarQuickAddDialog({
    required this.onClose,
    required this.onDisposed,
    required this.route,
    required this.initialText,
    this.defaultDate,
    this.projectId,
    this.labelId,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onDisposed;
  final ModalRoute<dynamic>? route;
  final String initialText;
  final DateTime? defaultDate;
  final String? projectId;
  final String? labelId;

  @override
  State<_SidebarQuickAddDialog> createState() => _SidebarQuickAddDialogState();
}

class _SidebarQuickAddDialogState extends State<_SidebarQuickAddDialog> {
  bool _voiceActive = false;
  bool _disposing = false;
  LocalHistoryEntry? _backEntry;
  final _focus = FocusScopeNode();

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
    final dialog = ExcludeFocus(
      excluding: _voiceActive,
      child: Offstage(
        offstage: _voiceActive,
        child: Stack(
          children: [
            ModalBarrier(
              color: Colors.black54,
              dismissible: true,
              onDismiss: widget.onClose,
            ),
            FocusScope(
              node: _focus,
              child: ResizableDialog(
                background: ThemeBackground(
                  zone: ThemeBackgroundZone.quickAdd,
                  blurBehind: true,
                  color: context.appColors.surface,
                  child: const SizedBox.expand(),
                ),
                title: Text(context.l10n.addTask),
                initialSize: const Size(560, 260),
                minSize: const Size(320, 220),
                content: QuickAddComposer(
                  initialText: widget.initialText,
                  defaultDate: widget.defaultDate,
                  projectId: widget.projectId,
                  labelId: widget.labelId,
                  onCompleted: widget.onClose,
                  onCancel: widget.onClose,
                  onVoiceSessionChanged: _setVoiceActive,
                ),
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
        if (_voiceActive) return false;
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
  final segments =
      GoRouter.maybeOf(
        context,
      )?.routeInformationProvider.value.uri.pathSegments ??
      const <String>[];
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
