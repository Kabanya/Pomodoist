import 'window_lifecycle_policy.dart';
import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/native_channel.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'impl/cascade_close_service_impl.dart';
import 'impl/modal_state_service.dart';
import 'impl/window_communicator_impl.dart';
import 'shared_entry_app.dart';
import 'app_shell/app_shell_registry.dart';
import 'view_shell_brightness_sync.dart';
import 'utils/calc_window_position.dart';
import 'utils/mapped_value_notifier.dart';

enum _CreateViewError {
  timeout(code: -1),
  forceClose(code: -2),
  unhandled(code: null);

  final int? code;

  String message(int token) => switch (this) {
    _CreateViewError.timeout => 'Failed to create dialog window, tokenId: $token. Error: timeout',
    // TODO: Handle this case.
    _CreateViewError.forceClose => 'Failed to create dialog window, tokenId: $token. Error: force close',
    // TODO: Handle this case.
    _CreateViewError.unhandled => 'Failed to create dialog window, tokenId: $token. Unhandled error',
  };

  const _CreateViewError({required this.code});
}

// ---------------------------------------------------------------------------
// Per-window registration (widget tree + optional parent link).
// ---------------------------------------------------------------------------
abstract class _ViewEntry {
  _ViewEntry({required this.widgetBuilder, required this.parentContext, ViewShellOverrides? initialShellOverrides})
    : viewShellOverrides = ValueNotifier<ViewShellOverrides?>(initialShellOverrides);

  final Widget Function(BuildContext) widgetBuilder;
  final BuildContext? parentContext;

  final ValueNotifier<ViewShellOverrides?> viewShellOverrides;

  void disposeEntryResources() => viewShellOverrides.dispose();
}

class _WindowEntry extends _ViewEntry {
  _WindowEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    this.parentId,
  });

  final int? parentId;
}

class _DialogEntry<T> extends _ViewEntry {
  _DialogEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    required this.parentId,
    required this.isModal,
    required this.closeCompleter,
  });

  final int parentId;
  final bool isModal;
  final Completer<T?> closeCompleter;

  void completeResult(dynamic result) {
    if (result != null && result is! T) {
      throw ArgumentError.value(result, 'MVD', 'Expected dialog result of type $T, got ${result.runtimeType}');
    }
    if (!closeCompleter.isCompleted) {
      closeCompleter.complete(result as T?);
    }
  }
}

// ---------------------------------------------------------------------------
// Global accessor for MultiViewDesktop and openWindow().
// ---------------------------------------------------------------------------

_MultiViewRootState? _rootState;
final NativeChannel _nativeChannel = NativeChannel();
bool _hasInitView = true;

/// Returns the live `_MultiViewRootState` after `runMultiApp` has started.
// ignore: library_private_types_in_public_api
_MultiViewRootState get globalRootState {
  if (_rootState == null) {
    throw Exception('globalRootState not initialized. Use runMultiApp instead of runApp or runWidget');
  }
  return _rootState!;
}

int get _initPlatformId => !Platform.isMacOS ? 0 : 1;

Future<Widget> createMultiViewRoot(
  Widget Function(BuildContext, int) home,
  Widget Function(Widget)? scope,
  MultiAppConfig config,
) async {
  _hasInitView = await _nativeChannel.checkWindowExist(_initPlatformId) ?? true;

  // Reset native behavioral flags before the widget tree is built
  if (_hasInitView) {
    await _nativeChannel.resetWindowToDefaults(_initPlatformId, config);
  }

  final mainRoot = _MultiViewRoot(homeBuilder: home, config: config);
  return scope?.call(mainRoot) ?? mainRoot;
}

// ---------------------------------------------------------------------------
// _MultiViewRoot
// ---------------------------------------------------------------------------

/// The invisible root widget placed at the top of the tree by `runMultiApp`.
///
/// Manages a `ViewCollection` whose entries grow/shrink as windows are
/// opened or closed.  Each child is wrapped in a `ViewScope` so that any
/// descendant can call `MultiViewDesktop.getIdByContext`.
class _MultiViewRoot extends StatefulWidget {
  const _MultiViewRoot({required this.homeBuilder, required this.config});

  final Widget Function(BuildContext, int) homeBuilder;
  final MultiAppConfig config;

  @override
  State<_MultiViewRoot> createState() => _MultiViewRootState();
}

// ---------------------------------------------------------------------------
// _MultiViewRootState
// ---------------------------------------------------------------------------

class _MultiViewRootState extends State<_MultiViewRoot> with WidgetsBindingObserver {
  late final _ViewsManagerImpl _viewsManagerImpl;

  WindowCommunicator get communicator => _viewsManagerImpl.communicator;

  ViewsManager get manager => _viewsManagerImpl;

  List<int> get allShiftedViewsId => _viewsManagerImpl.allShiftedWindowIds;

  ValueNotifier<List<int>> get windowsIdsNotif => _viewsManagerImpl.windowsNotifier;

  ValueNotifier<List<int>> get dialogsIdsNotif => _viewsManagerImpl.dialogsNotifier;

  /// Returns the modal-dialog counter notifier for the window with `realViewId`.
  ValueNotifier<List<DialogInfo>> getDialogModalNotifier(int realViewId) =>
      _viewsManagerImpl.getDialogModalPublicIdsFromRealParentIdNotifier(realViewId);

  final AppShellRegistry _appShellRegistry = AppShellRegistry();

  late final AppShellController appShell = AppShellController(_appShellRegistry);

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _rootState = this;
    _viewsManagerImpl = _ViewsManagerImpl(
      config: widget.config,
      cascadeCloseService: CascadeCloseService(),
      communicator: WindowCommunicatorImpl(),
    );
    WidgetsBinding.instance.addObserver(this);

    _initMainView();
  }

  void _initMainView() async {
    // Snapshot to avoid concurrent-modification errors on the live views set.
    final initial = WidgetsBinding.instance.platformDispatcher.views.toList();
    final excludeId = !Platform.isMacOS ? -1 : 0;
    final live = initial.where((v) => v.viewId != excludeId).toList();
    if (live.isEmpty) return;

    // After hot restart the lowest live view id may not be 1 (e.g. if view 1 was closed).
    live.sort((a, b) => a.viewId.compareTo(b.viewId));
    await _viewsManagerImpl.registerInitialWindow(
      viewId: live.first.viewId,
      homeBuilder: (context) => widget.homeBuilder(context, 1),
    );
    unawaited(_viewsManagerImpl.applyNativeLifecyclePolicy());
    unawaited(_viewsManagerImpl.applyInitialTaskbarMenu());
    // Only for debug. Closes all windows from past session on hot restart
    if (!kReleaseMode) {
      final registered = _viewsManagerImpl.allRealWindowIds.toSet();
      final orphaned = live.where((v) => !registered.contains(v.viewId)).toList();
      _viewsManagerImpl.removeOrphanViewsForceAfterRestart(orphaned.map((e) => e.viewId).toList());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_rootState, this)) _rootState = null;
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // WidgetsBindingObserver
  // --------------------------------------------------------------------------

  @override
  void didChangeMetrics() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _viewsManagerImpl.reconcileAnchor(dispatcher);

    final gone = _viewsManagerImpl.allRealWindowIds.where((id) => dispatcher.view(id: id) == null).toList();
    if (gone.isNotEmpty) {
      setState(() {
        for (final id in gone) {
          _handleClose(id);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.hidden) return;
    keepDesktopFramesAlive(() => mounted && _viewsManagerImpl.allRealWindowIds.isNotEmpty);
  }

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------

  void _handleClose(int viewId) {
    if (!mounted) return;
    _viewsManagerImpl._disposeView(viewId);
    setState(() {});
  }

  void addWindowView(
    int viewId,
    Widget Function(BuildContext) childBuilder, {
    required BuildContext? parentContext,
    int? parentId,
    ViewShellOverrides? shellOverrides,
  }) {
    setState(() {
      _viewsManagerImpl.registerWindow(
        viewId,
        childBuilder,
        parentContext: parentContext,
        parentId: parentId,
        shellOverrides: shellOverrides,
      );
    });
    _syncViewShellBrightness(viewId, shellOverrides);
  }

  void addDialogView<T>(
    int viewId,
    Widget Function(BuildContext) childBuilder, {
    required BuildContext parentContext,
    required int parentId,
    required Completer<T?> closeCompleter,
    bool isModalDialog = false,
    ViewShellOverrides? shellOverrides,
  }) {
    setState(() {
      _viewsManagerImpl.registerDialog<T>(
        viewId,
        childBuilder,
        parentContext: parentContext,
        parentId: parentId,
        isModal: isModalDialog,
        closeCompleter: closeCompleter,
        shellOverrides: shellOverrides,
      );
      return;
    });
    _syncViewShellBrightness(viewId, shellOverrides);
  }

  void _syncViewShellBrightness(int viewId, ViewShellOverrides? shellOverrides) {
    final brightness = resolveViewShellBrightness(_appShellRegistry, shellOverrides);
    if (brightness == null) return;
    unawaited(_viewsManagerImpl.setBrightness(viewId, brightness));
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = <Widget>[];
    final entries = [..._viewsManagerImpl.windowEntries, ..._viewsManagerImpl.dialogEntries];
    final ids = entries.map((e) => e.key).toList()..sort();
    for (int i = 0; i < ids.length; i++) {
      final entry = entries.firstWhere((e) => e.key == ids[i]);
      final id = entry.key;
      final parentContext = entry.value.parentContext;
      final flutterView = dispatcher.view(id: id);
      if (flutterView != null) {
        final modalNotifier = _viewsManagerImpl.getDialogModalPublicIdsFromRealParentIdNotifier(id);
        views.add(
          View(
            key: ValueKey('view_$id'),
            view: flutterView,
            child: DialogScope(
              notifier: modalNotifier,
              child: ParentWindowScope(
                parentContext: parentContext,
                child: ViewScope(
                  viewId: id,
                  child: Builder(
                    builder: (context) {
                      final content = entry.value.widgetBuilder(context);
                      if (id == _viewsManagerImpl.mainRealViewId) {
                        return MainAppShellCapture(registry: _appShellRegistry, child: content);
                      }

                      return ViewShellBrightnessSync(
                        registry: _appShellRegistry,
                        viewShellOverrides: entry.value.viewShellOverrides,
                        onBrightnessChanged: (brightness) => _viewsManagerImpl.setBrightness(id, brightness),
                        child: SharedEntryApp(
                          registry: _appShellRegistry,
                          viewShellOverrides: entry.value.viewShellOverrides,
                          child: content,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return ViewCollection(views: views);
  }
}

// ---------------------------------------------------------------------------
// ViewsManager impl
// ---------------------------------------------------------------------------

class _CreateCompleter<T> {
  final Completer<T?> completer;
  final int token;
  final bool isDialog;
  final int? parentId;

  const _CreateCompleter({
    required this.completer,
    required this.token,
    required this.isDialog,
    required this.parentId,
  });

  factory _CreateCompleter.window(int token, {int? parentId}) {
    return _CreateCompleter(completer: Completer<T?>(), token: token, isDialog: false, parentId: parentId);
  }

  factory _CreateCompleter.dialog(int token, {required int parentId}) {
    return _CreateCompleter(completer: Completer<T?>(), token: token, isDialog: true, parentId: parentId);
  }

  void complete([T? resId]) => completer.complete(resId);

  bool get isCompleted => completer.isCompleted;

  Future<T?> get future => completer.future;
}

/// Default `ViewsManager`: native channel, window registry, listeners, and close modes.
class _ViewsManagerImpl implements ViewsManager {
  final CascadeCloseService cascadeCloseService;
  final WindowCommunicatorImpl communicator;
  final MultiAppConfig config;

  final ModalStateService _modalStateService = ModalStateService();

  /// Active strategy when the main window's close button is pressed.
  late CloseMode closeMode;

  _ViewsManagerImpl({required this.config, required this.cascadeCloseService, required this.communicator}) {
    _nativeChannel.setMethodCallHandler(_onStaticCall);
    closeMode = config.generalParams.closeMode;
  }

  late bool _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;

  List<VoidCallback?> _taskbarMenuCallbacks = [];

  /// Applies `MultiPlatformParams.menuItems` from startup config.
  Future<void> applyInitialTaskbarMenu() async {
    final items = config.generalParams.menuItems;
    if (items.isEmpty) return;
    await setTaskbarMenu(items: items);
  }

  /// Pushes lifecycle quit policy to the native embedder.
  Future<void> applyNativeLifecyclePolicy() async {
    if (Platform.isMacOS) {
      await _nativeChannel.setTerminateAfterLastWindowClosed(
        config.macosParams.closeAppAfterLastWindowClosed && !_saveLastWindowToReopen,
      );
      await _nativeChannel.setHasTaskbarCallback(config.macosParams.onTaskbarTap != null);
    } else if (Platform.isLinux) {
      await _nativeChannel.setTerminateAfterLastWindowClosed(true);
    }
  }

  /// Returns the `ValueNotifier<List<DialogInfo>>` tracking modal dialogs blocking `realViewId`.
  ValueNotifier<List<DialogInfo>> getDialogModalPublicIdsFromRealParentIdNotifier(int realViewId) =>
      _dialogModalPublicNotifiers.putIfAbsent(
        realViewId,
        () => MappedValueNotifier(
          source: _modalStateService.getNotifier(realViewId),
          transform: (dialogs) => [for (final d in dialogs) (id: _realToShifted(d.id), isModal: d.isModal)],
        ),
      );

  @override
  int shiftedToRealId(int viewId) => _shiftedToReal(viewId);

  @override
  int realToShiftedId(int viewId) => _realToShifted(viewId);

  // token -> widget, entries waiting for the native "viewCreated" event.
  int _nextToken = 0;

  // id shift after hot restart
  int _hotRestartShift = 0;

  final Map<int, ValueNotifier<List<DialogInfo>>> _dialogModalPublicNotifiers = {};

  final Map<int, dynamic> _dialogsResults = {};

  // token -> Completer<int?> for pending views.
  final Map<int, _CreateCompleter<int?>> _createCompleters = {};

  final Map<int, int> _childCreatePending = {};

  // viewId -> listener list.
  final Map<int, ObserverList<WindowListenerCallbacks>> _listeners = {};

  /// Anchor window: receives app-level close policy (`CloseMode`) from the native close button.
  int? _realAnchorId;

  int? get realAnchorId => _realAnchorId;

  /// Back-compat alias used by native channel app-wide calls.
  int? get mainId => _realAnchorId;

  List<WindowObserver> get _observers => config.observers;

  /// View id for app-wide native calls (dock badge, taskbar, etc.).
  int? get _lifecycleViewId {
    if (_realAnchorId != null && _windows.containsKey(_realAnchorId)) return _realAnchorId;
    if (_windows.isEmpty) return null;
    return _windows.keys.reduce((a, b) => a < b ? a : b);
  }

  int _initRealId = _initPlatformId;

  int get mainRealViewId => _initRealId;
  bool _isInitFirstSecondaryView = false;

  final Map<int, _WindowEntry> _windows = {};
  final Set<int> _utilityWindowIds = {};
  final Map<int, _DialogEntry> _dialogs = {};

  final ValueNotifier<List<int>> _windowsNotifier = ValueNotifier([]);
  final ValueNotifier<List<int>> _dialogsNotifier = ValueNotifier([]);

  ValueNotifier<List<int>> get windowsNotifier => _windowsNotifier;

  ValueNotifier<List<int>> get dialogsNotifier => _dialogsNotifier;

  Iterable<MapEntry<int, _WindowEntry>> get windowEntries => _windows.entries;

  Iterable<MapEntry<int, _DialogEntry>> get dialogEntries => _dialogs.entries;

  List<int> get allRealWindowIds => _windows.keys.toList();

  List<int> get allShiftedWindowIds => _windows.keys.map((e) => _realToShifted(e)).toList();

  Future<void> registerInitialWindow({required int viewId, required Widget Function(BuildContext) homeBuilder}) async {
    // Win & linux by default init from 0 id but macos from 1
    _hotRestartShift = !Platform.isMacOS ? -1 : 0;
    if (!_hasInitView) {
      viewId = await _createNextMainWindowAfterRestart(homeBuilder);
    }

    _hotRestartShift = viewId - 1;
    _initRealId = viewId;
    _setAnchor(viewId, force: true);
    await _applyOptionsToInitialAnchor();

    globalRootState.addWindowView(viewId, homeBuilder, parentContext: null, parentId: null);
  }

  Future<int> _createNextMainWindowAfterRestart(Widget Function(BuildContext) homeBuilder) async {
    final opts = config.globalOptions;
    final int token = _nextToken++;
    _createCompleters[token] = _CreateCompleter.window(token);

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = await calcWindowPosition(windowSize, opts.alignment!);
    }

    try {
      await _nativeChannel.createWindowRequest(
        token: token,
        title: opts.title ?? '',
        focusOnShow: opts.focusOnShow ?? true,
        isUtility: opts.isUtility,
        linuxDesktopOverlay: opts.linuxDesktopOverlay,
        linuxDesktopOverlayRole: opts.linuxDesktopOverlayRole,
        backgroundColor: opts.backgroundColor,
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
      );
    } catch (e, st) {
      throw Exception('Failed to create new window, tokenId: $token. Error: $e, stack: $st');
    }

    final newViewId = await _waitCompleter(token);
    _createCompleters.remove(token);

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      if (error == _CreateViewError.forceClose) {
        // if (newRealIdAndErrorCode.viewId != null) {
        //   _nativeChannel.forceCloseView(newViewId);
        // }
      }
      throw Exception(error.message(token));
    }

    return newViewId!;
  }

  Future<void> _applyOptionsToInitialAnchor() async {
    if (realAnchorId == null) return;
    await applyOptions(realAnchorId!, opts: config.globalOptions);
    unawaited(_nativeChannel.show(realAnchorId!));
  }

  void _updateHotRestartShiftBySecondary(int viewId) {
    if (viewId == 2) {
      _isInitFirstSecondaryView = true;
    }
    if (allShiftedWindowIds.length == 1 && allShiftedWindowIds.first == 1 && viewId > 2 && !_isInitFirstSecondaryView) {
      _hotRestartShift = viewId - allShiftedWindowIds.first - 1;

      _isInitFirstSecondaryView = true;
    }
  }

  void registerWindow(
    int viewId,
    Widget Function(BuildContext) widgetBuilder, {
    required BuildContext? parentContext,
    int? parentId,
    ViewShellOverrides? shellOverrides,
  }) {
    if (parentId != null && !_windows.containsKey(parentId)) {
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addWindow(
      viewId,
      _WindowEntry(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        parentId: parentId,
        initialShellOverrides: shellOverrides,
      ),
    );
    _notifyObservers(
      (o) => o.onWindowOpened(_realToShifted(viewId), parentViewId: parentId != null ? _realToShifted(parentId) : null),
    );
    if (_realAnchorId == null && !_utilityWindowIds.contains(viewId)) {
      _setAnchor(viewId);
    }
  }

  void registerDialog<T>(
    int viewId,
    Widget Function(BuildContext) widgetBuilder, {
    required BuildContext? parentContext,
    required int parentId,
    required bool isModal,
    required Completer<T?> closeCompleter,
    ViewShellOverrides? shellOverrides,
  }) {
    if (!_windows.containsKey(parentId)) {
      throw ArgumentError.value(parentId, 'Parent error', 'Parent window is not registered');
    }
    _updateHotRestartShiftBySecondary(viewId);

    _addDialog(
      viewId,
      _DialogEntry<T>(
        widgetBuilder: widgetBuilder,
        parentContext: parentContext,
        initialShellOverrides: shellOverrides,
        parentId: parentId,
        isModal: isModal,
        closeCompleter: closeCompleter,
      ),
    );

    _notifyObservers((o) => o.onDialogOpened(_realToShifted(viewId), parentViewId: _realToShifted(parentId)));
  }

  void _notifyObservers(void Function(WindowObserver) action) {
    for (final observer in _observers) {
      action(observer);
    }
  }

  Future<void> _setAnchor(int? viewId, {bool force = false}) async {
    if (!config.generalParams.enableDynamicAnchor && !force) return;
    final previousShifted = _realAnchorId != null ? _realToShifted(_realAnchorId!) : null;
    _realAnchorId = viewId;
    final newShifted = viewId != null ? _realToShifted(viewId) : null;
    if (previousShifted != newShifted) {
      _notifyObservers((o) => o.onAnchorChanged(previousShifted, newShifted));
    }
    if (viewId == null) return;
    await _nativeChannel.setAnchorViewId(viewId);
  }

  /// When the anchor `FlutterView` disappears, pick another root window.
  void reconcileAnchor(PlatformDispatcher dispatcher) {
    final anchor = _realAnchorId;
    if (anchor == null) return;
    if (dispatcher.view(id: anchor) != null) return;
    _setAnchor(_realAnchorId);
    _promoteAnchor();
  }

  List<int> _anchorCandidates({int? excludingViewId}) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates = appWindowCandidates(
      windows: _windows.entries.map((entry) => (id: entry.key, parentId: entry.value.parentId)),
      utilityIds: _utilityWindowIds,
      liveIds: dispatcher.views.map((view) => view.viewId).toSet(),
      excludingId: excludingViewId,
    );
    return candidates;
  }

  /// Picks another root window as anchor (lowest live view id), optionally skipping `excludingViewId`.
  void _promoteAnchor({int? excludingViewId}) {
    final candidates = _anchorCandidates(excludingViewId: excludingViewId);
    if (candidates.isEmpty) {
      _setAnchor(null);
      return;
    }
    _setAnchor(candidates.first);
  }

  int _realToShifted(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == _initRealId) {
      return 1;
    }

    return viewId - _hotRestartShift;
  }

  int _shiftedToReal(int viewId) {
    if (allRealWindowIds.contains(_initPlatformId) && viewId == 1) {
      return _initRealId;
    }

    return viewId + _hotRestartShift;
  }

  List<int> _directChildIds(int parentId) =>
      _windows.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  /// Direct children of `parentId` that are dialogs (`_WindowEntry.isDialog`).
  List<int> _directDialogChildIds(int parentId) =>
      _dialogs.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  List<int> _descendantIdsDeepestFirst(int rootId) {
    final result = <int>[];
    void walk(int id) {
      for (final child in _directChildIds(id)) {
        walk(child);
        result.add(child);
      }
    }

    walk(rootId);
    return result;
  }

  List<int> _rootWindowIds({int? excludingId}) =>
      _windows.entries.where((e) => e.value.parentId == null && e.key != excludingId).map((e) => e.key).toList();

  Future<dynamic> _onStaticCall(MethodCall call) async {
    if (call.method != 'onEvent') return null;

    final String eventName = call.arguments['eventName'] as String;

    if (eventName == 'viewCreated') {
      final int viewId = call.arguments['viewId'] as int;
      final int token = call.arguments['token'] as int;
      final maybeParentId = _childCreatePending[token];
      _createComplete(token, viewId);
      if (maybeParentId == null) return;
      _childCreatePending.remove(token);
      await _nativeChannel.setPreConfirmClose(maybeParentId, false);
    } else if (eventName == 'taskbar-callback') {
      config.macosParams.onTaskbarTap?.call();
    } else if (eventName == 'preconfirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        // debugPrint('preconfirm: $viewId');
        await _handlePreConfirmClose(viewId);
      }
    } else if (eventName == 'confirm-close') {
      final int? viewId = call.arguments['viewId'] as int?;
      if (viewId != null) {
        // debugPrint('confirm: $viewId');
        await _onConfirmClose(viewId);
      }
    } else if (eventName == 'applicationShouldTerminateRequest') {
      unawaited(_macosOnShouldAppTerminate());
    } else if (eventName == 'taskbarMenuItemSelected') {
      final id = call.arguments['id'] as int?;
      if (id != null) {
        _invokeTaskbarMenuCallback(id);
      }
    } else {
      final int? viewId = call.arguments['viewId'] as int?;

      if (viewId != null) {
        _dispatchViewEvent(viewId, eventName);
      }
    }

    return null;
  }

  Future<void> _macosOnShouldAppTerminate() async {
    final confirmTerminate = await config.macosParams.onTerminate?.call() ?? true;
    await _nativeChannel.replyToApplicationShouldTerminate(confirmTerminate);
  }

  Future<void> _onConfirmClose(int viewId) async {
    final isDialog = _dialogs.containsKey(viewId);
    final isModalDialog = isDialog && (_dialogs[viewId]?.isModal ?? false);
    await _removeAllDialogsByParent(viewId);

    await _disposeView(viewId);

    await _nativeChannel.setConfirmClose(viewId, isConfirm: true);
    if (isModalDialog) {
      await _nativeChannel.destroyModalDialog(viewId);
    } else {
      await _nativeChannel.forceCloseView(viewId);
    }
    cascadeCloseService.completeWindow(viewId);
  }

  /// Runs before `isPreventClose` / `isConfirmClose`; subtree closes per `closeMode`.
  Future<void> _handlePreConfirmClose(int viewId) async {
    final nextAnchorCandidates = _anchorCandidates(excludingViewId: viewId)..sort();
    // Closing the last real Windows app window exits utilities without asking
    // their decorative close handlers to delay application shutdown.
    if (Platform.isWindows && viewId == _realAnchorId && nextAnchorCandidates.isEmpty) {
      for (final utilityId in _utilityWindowIds.toList()) {
        await _onConfirmClose(utilityId);
      }
    }
    // debugPrint('nextAnchorCandidates: $nextAnchorCandidates');
    if (viewId == _realAnchorId && nextAnchorCandidates.isNotEmpty && !config.generalParams.enableDynamicAnchor) {
      for (final candidate in nextAnchorCandidates.reversed) {
        cascadeCloseService.abort(candidate);
        cascadeCloseService.attachWindow(candidate);
        await _closeSubtreeByMode(candidate, closeMode);
        final closed = await cascadeCloseService.waitWindow(candidate);
        if (!closed) {
          return;
        }
      }
    }
    // debugPrint('close $viewId subtree');

    await _closeSubtreeByMode(viewId, closeMode);
  }

  Future<void> _closeSubtreeByMode(int rootId, CloseMode mode) async {
    await _waitAllCreatingViews();
    switch (mode) {
      case CloseMode.none:
        await _removeViewsNone(rootId);
        break;
      case CloseMode.softCascade:
        await _removeViewsCascade(rootId);
        break;
      case CloseMode.forceSecondary:
        await _removeSecondaryViewsForce(rootId);
        break;
      case CloseMode.destroy:
        await _destroyAllViewsForce(rootId);
        break;
    }
  }

  /// Aborts the cascade close that is waiting on `viewId`.
  ///
  /// Completing the completer with `false` causes the cascade loop to `return`
  /// early, leaving the main window open. All other pending completers are
  /// also cleared so that a later independent close of those windows does not
  /// unexpectedly resume the (already aborted) cascade.
  Future<void> _cancelCascade(int viewId) async {
    final parentsRecurs = [..._parentsId(viewId), ..._dialogParentIds(viewId), viewId];
    for (final parent in parentsRecurs) {
      await _nativeChannel.setPreConfirmClose(parent, false);
      cascadeCloseService.abort(parent);
    }
  }

  int? _directParentId(int childId) {
    final entry = _windows[childId];
    return entry?.parentId;
  }

  List<int> _parentsId(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = _directParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  int? _directDialogParentId(int childId) {
    final entry = _dialogs[childId];
    return entry?.parentId;
  }

  List<int> _dialogParentIds(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = _directDialogParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  // --------------------------------------------------------------------------
  // Per-view event dispatch
  // --------------------------------------------------------------------------

  void _dispatchViewEvent(int viewId, String eventName) {
    if (_windows.keys.contains(viewId)) {
      _notifyObservers((o) => o.onWindowEvent(_realToShifted(viewId), eventName));
    }
    if (_dialogs.keys.contains(viewId)) {
      _notifyObservers((o) => o.onDialogEvent(_realToShifted(viewId), eventName));
    }
    final list = _listeners[viewId];
    if (list == null) return;
    for (final l in List<WindowListenerCallbacks>.from(list)) {
      l.onWindowEvent(eventName);
      _dispatchListenerEvent(l, eventName);
    }
  }

  void _dispatchListenerEvent(WindowListenerCallbacks listener, String eventName) {
    switch (eventName) {
      case 'focus':
        listener.onWindowFocus();
      case 'blur':
        listener.onWindowBlur();
      case 'maximize':
        listener.onWindowMaximize();
      case 'unmaximize':
        listener.onWindowUnmaximize();
      case 'minimize':
        listener.onWindowMinimize();
      case 'restore':
        listener.onWindowRestore();
      case 'resize':
        listener.onWindowResize();
      case 'resized':
        listener.onWindowResized();
      case 'move':
        listener.onWindowMove();
      case 'moved':
        listener.onWindowMoved();
      case 'enter-full-screen':
        listener.onWindowEnterFullScreen();
      case 'leave-full-screen':
        listener.onWindowLeaveFullScreen();
      case 'close':
        listener.onWindowClose();
    }
  }

  bool _isLastMacosRootView(int id) =>
      ((_anchorCandidates(excludingViewId: id).isEmpty) && _saveLastWindowToReopen && _realAnchorId == id);

  Future<void> _preConfirmCloseCallable(int viewId, {bool isForce = false}) async {
    await _nativeChannel.setPreConfirmClose(viewId, true);

    if (isForce) {
      _saveLastWindowToReopen = false;
      await applyNativeLifecyclePolicy();
      await _nativeChannel.forceCloseView(viewId);
    } else {
      if (Platform.isMacOS) {
        // Hide the anchor instead of closing it when macOS dock restore is enabled and taskbar callback is null.
        if (_isLastMacosRootView(viewId)) {
          await _removeAllDialogsByParent(viewId);
          await _nativeChannel.hide(viewId);
          await _nativeChannel.setPreConfirmClose(viewId, false);
          cascadeCloseService.completeWindow(viewId);
          return;
        }
      }
      await _nativeChannel.softCloseWindow(viewId);
    }
  }

  Future<bool> _removeAllDialogsByParent(int parentId) async {
    final allDialogs = _directDialogChildIds(parentId)..sort();
    for (final dialogId in allDialogs.reversed) {
      await _nativeChannel.destroyModalDialog(dialogId);

      await _disposeView(dialogId);
    }
    return true;
  }

  Future<void> _removeViewsNone(int rootId) async {
    await _preConfirmCloseCallable(rootId);
  }

  Future<void> _removeViewsCascade(int rootId) async {
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();

    // debugPrint('cascade for $rootId');
    for (final id in descendants.reversed) {
      final closed =
          await _viewExistChecker<bool>(id, () async {
            cascadeCloseService.attachWindow(id);
            await _nativeChannel.softCloseWindow(id);
            return await cascadeCloseService.waitWindow(id);
          }) ??
          false;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
    if (descendantsAfter.isNotEmpty) {
      // do nothing because softClose cycle
      return;
    }

    await _viewExistChecker(rootId, () async => _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _removeSecondaryViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final closed =
          await _viewExistChecker<bool>(id, () async {
            cascadeCloseService.attachWindow(id);
            await _nativeChannel.forceCloseView(id);
            return await cascadeCloseService.waitWindow(id);
          }) ??
          false;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    if (loopCycle < maxLoopCycles) {
      final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
      if (descendantsAfter.isNotEmpty) {
        // repeat cycle because forceClose cycle
        unawaited(_removeSecondaryViewsForce(rootId, loopCycle: loopCycle + 1));
        return;
      }
    }
    await _viewExistChecker(rootId, () async => await _preConfirmCloseCallable(rootId), dialogSupports: true);
  }

  Future<void> _destroyAllViewsForce(int rootId, {int loopCycle = 1, int maxLoopCycles = 10}) async {
    cascadeCloseService.clear();
    final descendants = _descendantIdsDeepestFirst(rootId).toList()..sort();
    for (final id in descendants.reversed) {
      final closed =
          await _viewExistChecker<bool>(id, () async {
            cascadeCloseService.attachWindow(id);
            await _nativeChannel.forceCloseView(id);
            return await cascadeCloseService.waitWindow(id);
          }) ??
          false;
      if (!closed) return;
    }

    // checks views created while doing close cycle
    if (loopCycle < maxLoopCycles) {
      final descendantsAfter = _descendantIdsDeepestFirst(rootId).toList()..sort();
      if (descendantsAfter.isNotEmpty) {
        // repeat cycle because forceClose cycle
        unawaited(_destroyAllViewsForce(rootId, loopCycle: loopCycle + 1));
        return;
      }
    }

    await _viewExistChecker(
      rootId,
      () async => await _preConfirmCloseCallable(rootId, isForce: true),
      dialogSupports: true,
    );
  }

  Future<void> removeOrphanViewsForceAfterRestart(List<int> ids) async {
    cascadeCloseService.clear();
    for (final id in ids) {
      try {
        await _nativeChannel.forceCloseView(id);
        await _nativeChannel.destroyModalDialog(id);
      } catch (_) {}
    }
  }

  Future<void> applyOptions(int viewId, {required WindowOptions opts}) async => _applyOptions(viewId, opts);

  Future<void> _applyOptions(int viewId, WindowOptions opts) async {
    if (opts.size != null) {
      await _nativeChannel.setSize(viewId, size: opts.size!);
    }
    if (opts.alignment != null) {
      await _nativeChannel.setAlignment(viewId, alignment: opts.alignment!);
    }
    if (opts.backgroundColor != null) {
      await _nativeChannel.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.minimumSize != null) {
      await _nativeChannel.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      await _nativeChannel.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.title != null) await _nativeChannel.setTitle(viewId, title: opts.title!);
    if (opts.titleBarStyle != null) {
      await _nativeChannel.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility!,
        maximizeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: opts.windowButtonVisibility!,
      );
    }
    if (opts.alwaysOnTop != null) {
      await _nativeChannel.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
    if (opts.fullScreen != null) {
      await _nativeChannel.setFullScreen(viewId, isFullScreen: opts.fullScreen!);
    }
    if (opts.hideAppFromTaskbar ?? false) {
      await hideAppFromTaskbar(true);
    }
  }

  Future<void> _applyDialogOptions(int viewId, DialogOptions opts) async {
    if (!Platform.isWindows) {
      if (opts.size != null) {
        await _nativeChannel.setSize(viewId, size: opts.size!);
      }
    }
    if (opts.backgroundColor != null) {
      await _nativeChannel.setBackgroundColor(viewId, color: opts.backgroundColor!);
    }
    if (opts.showOnInit == true || opts.showOnInit == null) {
      await _nativeChannel.show(viewId);
    }
    if (opts.minimumSize != null) {
      await _nativeChannel.setMinSize(viewId, size: opts.minimumSize!);
    }
    if (opts.maximumSize != null) {
      await _nativeChannel.setMaxSize(viewId, size: opts.maximumSize!);
    }
    if (opts.isResizable != null) {
      await _nativeChannel.setResizable(viewId, opts.isResizable!);
    }
    if (opts.title != null) await _nativeChannel.setTitle(viewId, title: opts.title!);
    if (opts.titleBarStyle != null) {
      await _nativeChannel.setTitleBarStyle(
        viewId,
        style: opts.titleBarStyle!,
        closeVisibility: opts.windowButtonVisibility!,
        minimizeVisibility: false,
        maximizeVisibility: false,
      );
    }
    if (opts.alwaysOnTop != null) {
      await _nativeChannel.setAlwaysOnTop(viewId, isAlwaysOnTop: opts.alwaysOnTop!);
    }
  }

  void _addWindow(int viewId, _WindowEntry entry) {
    _windows[viewId] = entry;
    _windowsNotifier.value = _windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _addDialog<T>(int dialogId, _DialogEntry<T> entry) {
    _dialogs[dialogId] = entry;
    _dialogsNotifier.value = _dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeWindow(int viewId) {
    _utilityWindowIds.remove(viewId);
    _windows.remove(viewId)?.disposeEntryResources();
    _windowsNotifier.value = _windows.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  void _removeDialog(int dialogId) async {
    final dialog = _dialogs[dialogId];
    if (dialog == null) return;
    dialog.completeResult(_dialogsResults.remove(dialogId));
    dialog.disposeEntryResources();
    _dialogs.remove(dialogId);
    _dialogsNotifier.value = _dialogs.entries.map((e) => _realToShifted(e.key)).toList()..sort();
  }

  _ViewEntry? _viewEntryFor(int viewId) => _windows[viewId] ?? _dialogs[viewId];

  @override
  void patchViewShell(int viewId, ViewShellOverrides overrides) {
    final entry = _viewEntryFor(viewId);
    if (entry == null) return;
    final notifier = entry.viewShellOverrides;
    notifier.value = ViewShellOverrides.merge(notifier.value, overrides);
  }

  @override
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides) {
    _viewEntryFor(viewId)?.viewShellOverrides.value = overrides;
  }

  @override
  ViewShellOverrides? getViewShellOverrides(int viewId) => _viewEntryFor(viewId)?.viewShellOverrides.value;

  Future<void> _disposeView(int viewId) async {
    final entry = [..._windows.entries, ..._dialogs.entries].where((e) => e.key == viewId).firstOrNull;
    final shiftedViewId = _realToShifted(viewId);
    final isDialog = entry?.value is _DialogEntry;

    if (isDialog) {
      if (_dialogs.keys.contains(viewId)) {
        _notifyObservers((o) => o.onDialogClose(shiftedViewId));
      }
    } else {
      if (_windows.keys.contains(viewId)) {
        _notifyObservers((o) => o.onWindowClosed(shiftedViewId));
      }
    }
    // If this dialog had a modal flag, unblock its parent window.
    if (isDialog) {
      _modalStateService.unregisterDialog((entry?.value as _DialogEntry).parentId, realDialogId: viewId);
    }
    // Clean up the modal notifier for this view (it may have been a parent itself).
    _modalStateService.disposeView(viewId);
    _dialogModalPublicNotifiers.remove(viewId)?.dispose();

    final wasAnchor = viewId == _realAnchorId;
    if (wasAnchor && !isDialog) {
      _setAnchor(null);
    }
    _listeners.remove(viewId);
    if (isDialog) {
      _removeDialog(viewId);
    } else {
      _removeWindow(viewId);
    }
    communicator.disposeViewByShiftedId(shiftedViewId);
    if (wasAnchor && !isDialog) {
      _promoteAnchor();
    }
  }

  @override
  Future<int> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent}) async {
    if (parent != null && !_windows.containsKey(parent)) {
      throw ArgumentError.value(parent, 'Parent error', 'Parent window is not registered');
    }

    final comparedOpts = _compareGlobalAndNewOpts(preferred: newOpts, global: config.globalOptions);

    return _createWindow(opts: comparedOpts, parentId: parent, onCreated: onCreated);
  }

  @override
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required Future<void> Function(int) onCreated,
  }) async {
    if (!_windows.containsKey(parentRealId)) {
      throw ArgumentError.value(parentRealId, 'Parent error', 'Parent window is not registered');
    }

    if (_createCompleters.values.any((e) => !e.completer.isCompleted && e.isDialog && e.parentId == parentRealId)) {
      throw Exception('Create error: "Create dialog" was called while another dialog is creating in the same window');
    }

    final comparedOpts = _compareDialogGlobalAndNewOpts(preferred: newOpts, global: config.globalDialogOptions);
    if (comparedOpts.modal == true) {
      final hasModal = _modalStateService.getNotifier(parentRealId).value.firstWhereOrNull((e) => e.isModal) != null;
      if (hasModal) {
        throw Exception('Create error: One window can has only one modal dialog');
      }
    }
    final dialogId = await _createDialog(opts: comparedOpts, parentId: parentRealId, onCreated: onCreated);

    return dialogId;
  }

  Future<void> _createComplete(int token, int newViewId) async {
    _createCompleters[token]?.complete(newViewId);
    await _nativeChannel.setPreConfirmClose(newViewId, false);
  }

  /// `excludeTokens` - current view tokens, so don't wait yourself
  Future<void> _waitAllCreatingViews({List<int> excludeTokens = const []}) async {
    if (_createCompleters.entries.any((e) => !e.value.isCompleted)) {
      try {
        for (final key in _createCompleters.keys.toList()..sort()) {
          if (excludeTokens.contains(key)) continue;

          final completer = _createCompleters[key];
          if (!(completer?.isCompleted ?? true)) {
            await completer?.future;
          }
        }
      } catch (_) {
        // error in _createCompleters map is non-critical, do nothing
      }
    }
  }

  Future<int?> _waitCompleter(int token, {int timeoutMs = 10000}) async {
    return await _createCompleters[token]?.future.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () {
        _createCompleters[token]?.complete(_CreateViewError.timeout.code);
        return _CreateViewError.timeout.code;
      },
    );
  }

  Future<int> _createWindow({
    required WindowOptions opts,
    int? parentId,
    required Future<void> Function(int) onCreated,
  }) async {
    final int token = _nextToken++;
    _createCompleters[token] = _CreateCompleter.window(token, parentId: parentId);
    final int windowFinishedToken = _nextToken++;
    _createCompleters[windowFinishedToken] = _CreateCompleter.window(token, parentId: parentId);

    // wait all other creating views
    await _waitAllCreatingViews(excludeTokens: [token, windowFinishedToken]);

    if (parentId != null) {
      _childCreatePending.putIfAbsent(token, () => parentId);
    }

    Offset? pos;
    final windowSize = Size(opts.size?.width ?? 800.0, opts.size?.height ?? 600.0);
    if (opts.alignment != null) {
      pos = await calcWindowPosition(windowSize, opts.alignment!);
    }

    try {
      await _nativeChannel.createWindowRequest(
        token: token,
        title: opts.title ?? '',
        focusOnShow: opts.focusOnShow ?? true,
        isUtility: opts.isUtility,
        linuxDesktopOverlay: opts.linuxDesktopOverlay,
        linuxDesktopOverlayRole: opts.linuxDesktopOverlayRole,
        backgroundColor: opts.backgroundColor,
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        pos: pos,
        parentId: parentId,
      );
    } catch (e, st) {
      _createCompleters[windowFinishedToken]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(windowFinishedToken);

      _createCompleters[token]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(token);
      throw Exception('Failed to create new window, tokenId: $token. Error: $e, stack: $st');
    }

    final newViewId = await _waitCompleter(token);
    _createCompleters.remove(token);
    if (parentId != null) {
      _childCreatePending.remove(token);
    }

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      throw Exception(error.message(token));
    }

    await _applyOptions(newViewId!, opts);

    if (opts.isUtility) _utilityWindowIds.add(newViewId);
    await onCreated(newViewId);

    _createCompleters[windowFinishedToken]?.complete();
    _createCompleters.remove(windowFinishedToken);

    return newViewId;
  }

  WindowOptions _compareGlobalAndNewOpts({WindowOptions? preferred, required WindowOptions global}) {
    if (preferred == null) return global;
    return WindowOptions(
      size: preferred.size ?? global.size,
      focusOnShow: preferred.focusOnShow ?? global.focusOnShow,
      isUtility: preferred.isUtility,
      linuxDesktopOverlay: preferred.linuxDesktopOverlay,
      linuxDesktopOverlayRole: preferred.linuxDesktopOverlayRole,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      alignment: preferred.alignment ?? global.alignment,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
      hideAppFromTaskbar: preferred.hideAppFromTaskbar ?? global.hideAppFromTaskbar,
      titleBarStyle: preferred.titleBarStyle ?? global.titleBarStyle,
      windowButtonVisibility: preferred.windowButtonVisibility ?? global.windowButtonVisibility,
      title: preferred.title ?? global.title,
      fullScreen: preferred.fullScreen ?? global.fullScreen,
      alwaysOnTop: preferred.alwaysOnTop ?? global.alwaysOnTop,
    );
  }

  DialogOptions _compareDialogGlobalAndNewOpts({DialogOptions? preferred, required DialogOptions global}) {
    if (preferred == null) return global;
    return DialogOptions(
      size: preferred.size ?? global.size,
      minimumSize: preferred.minimumSize ?? global.minimumSize,
      maximumSize: preferred.maximumSize ?? global.maximumSize,
      isResizable: preferred.isResizable ?? global.isResizable,
      backgroundColor: preferred.backgroundColor ?? global.backgroundColor,
      titleBarStyle: preferred.titleBarStyle ?? global.titleBarStyle,
      modal: preferred.modal ?? global.modal,
      windowButtonVisibility: preferred.windowButtonVisibility ?? global.windowButtonVisibility,
      title: preferred.title ?? global.title,
      alwaysOnTop: preferred.alwaysOnTop ?? global.alwaysOnTop,
      showOnInit: preferred.showOnInit ?? global.showOnInit,
    );
  }

  /// Creates a native dialog and waits for the `viewCreated` event.
  ///
  /// Modal dialogs block the parent at the OS level (macOS sheet, Windows owner
  /// chain, Linux transient + input lock). Modeless dialogs are positioned over
  /// the parent and do not block it natively.
  Future<int> _createDialog({
    required DialogOptions opts,
    required int parentId,
    required Future<void> Function(int) onCreated,
  }) async {
    final int token = _nextToken++;
    _createCompleters[token] = _CreateCompleter.dialog(token, parentId: parentId);
    final int modalFinishedToken = _nextToken++;
    _createCompleters[modalFinishedToken] = _CreateCompleter.dialog(token, parentId: parentId);

    // wait all other creating views
    await _waitAllCreatingViews(excludeTokens: [token, modalFinishedToken]);

    _childCreatePending.putIfAbsent(token, () => parentId);

    final windowSize = Size(opts.size?.width ?? 400.0, opts.size?.height ?? 300.0);

    try {
      final modal = opts.modal ?? false;
      Offset? pos;
      if (!modal) {
        final parentBounds = await _nativeChannel.getBounds(parentId);
        pos = await calcWindowPositionByParent(Alignment.center, windowSize: windowSize, parentBounds: parentBounds);
        // Native sheet - positioned by the OS; no Dart-side alignment needed.
      }
      await _nativeChannel.createModalDialogRequest(
        token: token,
        title: opts.title ?? '',
        titleBarStyleStr: opts.titleBarStyle?.name ?? 'normal',
        windowButtonVisibility: opts.windowButtonVisibility ?? true,
        windowSize: windowSize,
        isModal: modal,
        pos: pos,
        parentId: parentId,
      );
    } catch (e, st) {
      _createCompleters[modalFinishedToken]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(modalFinishedToken);

      _createCompleters[token]?.complete(_CreateViewError.unhandled.code);
      _createCompleters.remove(token);
      throw Exception('Failed to create dialog window, tokenId: $token. Error: $e, stack: $st');
    }

    final newViewId = await _waitCompleter(token);

    _createCompleters.remove(token);
    _childCreatePending.remove(token);

    if (_CreateViewError.values.map((e) => e.code).contains(newViewId)) {
      final error = _CreateViewError.values.firstWhere(
        (e) => e.code == newViewId,
        orElse: () => _CreateViewError.unhandled,
      );
      throw Exception(error.message(token));
    }

    _modalStateService.registerDialog(parentId, dialogId: newViewId!, isModal: opts.modal ?? false);

    await _applyDialogOptions(newViewId, opts);

    await onCreated(newViewId);

    if (opts.modal == true) {
      // delay so modal shows correct
      await Future.delayed(Duration(milliseconds: 35));
    }
    _createCompleters[modalFinishedToken]?.complete();
    _createCompleters.remove(modalFinishedToken);
    return newViewId;
  }

  @override
  void addListener(int viewId, WindowListenerCallbacks listener) {
    _listeners.putIfAbsent(viewId, () => ObserverList<WindowListenerCallbacks>()).add(listener);
  }

  @override
  void removeListener(int viewId, WindowListenerCallbacks listener) {
    _listeners[viewId]?.remove(listener);
  }

  @override
  bool get isEnabledDynamicAnchor => config.generalParams.enableDynamicAnchor;

  @override
  Future<void> setTaskbarMenu({required List<TaskbarMenuItem> items}) async {
    _taskbarMenuCallbacks = [for (final item in items) item.onPressed];
    final encoded = [for (var i = 0; i < items.length; i++) await items[i].toJson(i)];
    await _nativeChannel.setTaskbarMenu(encoded);
  }

  void _invokeTaskbarMenuCallback(int id) {
    if (id < 0 || id >= _taskbarMenuCallbacks.length) return;
    _taskbarMenuCallbacks[id]?.call();
  }

  @override
  Future<bool> setPublicAnchorId(int viewId) async {
    if (config.generalParams.enableDynamicAnchor) return false;

    final realView = _shiftedToReal(viewId);
    if (_anchorCandidates().contains(realView)) {
      await _setAnchor(realView, force: true);
      return true;
    }

    return false;
  }

  @override
  int? getPublicAnchorId() {
    if (_realAnchorId == null) return null;

    return _realToShifted(_realAnchorId!);
  }

  @override
  Future<void> blur(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.blur(viewId), dialogSupports: true);
  }

  @override
  Future<void> cancelCascadeClose(int viewId) async {
    await _cancelCascade(viewId);
  }

  @override
  Future<void> center(int viewId) async {
    await setAlignment(viewId, Alignment.center);
  }

  @override
  WindowInfo windowType(int viewId) {
    final dialog = _dialogs[viewId];
    return (isDialog: dialog != null, isModal: dialog?.isModal ?? false);
  }

  @override
  Future<void> closeView<T>(int viewId, {T? dialogRes}) async {
    if (_dialogs.containsKey(viewId)) {
      _dialogsResults[viewId] = dialogRes;
      await _viewExistChecker(
        viewId,
        () async => await _nativeChannel.destroyModalDialog(viewId),
        dialogSupports: true,
      );
      await _disposeView(viewId);
    } else {
      await _viewExistChecker(viewId, () async => await _nativeChannel.softCloseWindow(viewId));
    }
  }

  @override
  Future<void> focus(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.focus(viewId), dialogSupports: true);
  }

  @override
  Future<Rect> getBounds(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getBounds(viewId), dialogSupports: true) ??
        Rect.zero;
  }

  @override
  Future<double> getOpacity(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getOpacity(viewId), dialogSupports: true) ??
        1;
  }

  @override
  Future<Offset> getPosition(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.getPosition(viewId),
          dialogSupports: true,
        ) ??
        Offset.zero;
  }

  @override
  Future<Size> getSize(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getSize(viewId), dialogSupports: true) ??
        Size.zero;
  }

  @override
  Future<String> getTitle(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.getTitle(viewId), dialogSupports: true) ??
        '';
  }

  @override
  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})>
  getTitleBarStyle(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.getTitleBarStyle(viewId),
          dialogSupports: true,
        ) ??
        (style: TitleBarStyle.normal, closeVisibility: true, maximizeVisibility: true, minimizeVisibility: true);
  }

  @override
  Future<bool> hasShadow(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.hasShadow(viewId), dialogSupports: true) ??
        true;
  }

  @override
  Future<void> hide(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.hide(viewId), dialogSupports: true);
  }

  @override
  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId}) async {
    if (Platform.isMacOS) {
      final id = _lifecycleViewId;
      if (id == null) return;
      await _viewExistChecker(
        id,
        () async => await _nativeChannel.hideAppFromTaskbar(id, isHideAppFromTaskbar: isHideAppFromTaskbar),
        dialogSupports: true,
      );
    } else {
      if (viewId == null) {
        for (final view in windowEntries) {
          await _viewExistChecker(
            view.key,
            () async => await _nativeChannel.hideAppFromTaskbar(view.key, isHideAppFromTaskbar: isHideAppFromTaskbar),
            dialogSupports: true,
          );
        }
        return;
      }
      await _viewExistChecker(
        viewId,
        () async => await _nativeChannel.hideAppFromTaskbar(viewId, isHideAppFromTaskbar: isHideAppFromTaskbar),
        dialogSupports: true,
      );
    }
  }

  @override
  Future<void> hideFromCollection(int viewId, bool isHideFromCollection) async {
    if (!Platform.isMacOS) return;
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.hideFromCollection(viewId, isHideFromCollection),
      dialogSupports: true,
    );
  }

  @override
  Future<bool> isAlwaysOnTop(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isAlwaysOnTop(viewId),
          dialogSupports: true,
        ) ??
        false;
  }

  @override
  Future<bool> isClosable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isClosable(viewId), dialogSupports: true) ??
        true;
  }

  @override
  Future<bool> isFocused(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isFocused(viewId), dialogSupports: true) ??
        true;
  }

  @override
  Future<bool> isOnActiveSpace(int viewId) async {
    if (!Platform.isMacOS) return true;
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isOnActiveSpace(viewId),
          dialogSupports: true,
        ) ??
        true;
  }

  @override
  Future<bool> isFullScreen(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isFullScreen(viewId)) ?? false;
  }

  @override
  Future<bool> isHideAppFromTaskbar() async {
    if (Platform.isWindows || Platform.isLinux) {
      return await _nativeChannel.isHideAppFromTaskbar();
    }
    final id = _lifecycleViewId;
    if (id == null) return false;
    return await _viewExistChecker(id, () async => await _nativeChannel.isHideAppFromTaskbar(), dialogSupports: true) ??
        false;
  }

  @override
  Future<bool> isHideAppTabFromTaskbar(int viewId) async {
    if (!Platform.isWindows) {
      return isHideAppFromTaskbar();
    }
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isHideAppTabFromTaskbar(viewId),
          dialogSupports: true,
        ) ??
        false;
  }

  @override
  Future<bool> isHideFromCollection(int viewId) async {
    if (!Platform.isMacOS) return false;
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isHideFromCollection(viewId),
          dialogSupports: true,
        ) ??
        false;
  }

  @override
  Future<bool> isMaximizable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMaximizable(viewId)) ?? true;
  }

  @override
  Future<bool> isMaximized(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMaximized(viewId)) ?? false;
  }

  @override
  Future<bool> isMinimizable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMinimizable(viewId)) ?? true;
  }

  @override
  Future<bool> isMinimized(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMinimized(viewId)) ?? false;
  }

  @override
  Future<bool> isMovable(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isMovable(viewId), dialogSupports: true) ??
        true;
  }

  @override
  Future<bool> isPreventClose(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isPreventClose(viewId)) ?? false;
  }

  @override
  Future<bool> isResizable(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isResizable(viewId),
          dialogSupports: true,
        ) ??
        true;
  }

  @override
  Future<bool> isVisible(int viewId) async {
    return await _viewExistChecker(viewId, () async => await _nativeChannel.isVisible(viewId), dialogSupports: true) ??
        true;
  }

  @override
  Future<bool> isVisibleOnAllWorkspaces(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isVisibleOnAllWorkspaces(viewId),
          dialogSupports: true,
        ) ??
        true;
  }

  @override
  Future<void> maximize(int viewId, {bool vertically = false}) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.maximize(viewId));
  }

  @override
  Future<void> minimize(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.minimize(viewId));
  }

  @override
  Future<void> popUpWindowMenu(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.popUpWindowMenu(viewId), dialogSupports: true);
  }

  @override
  Future<void> restore(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.restore(viewId));
  }

  @override
  Future<void> setAlignment(int viewId, Alignment alignment, {bool insideParent = false}) async {
    final dialog = _dialogs[viewId];
    if (dialog != null && insideParent) {
      final parentBounds = await _nativeChannel.getBounds(dialog.parentId);
      final windowSize = await _nativeChannel.getSize(viewId);
      final pos = await calcWindowPositionByParent(alignment, windowSize: windowSize, parentBounds: parentBounds);
      await _viewExistChecker(
        viewId,
        () async => await _nativeChannel.setPosition(viewId, pos: pos),
        dialogSupports: true,
      );
      return;
    }
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setAlignment(viewId, alignment: alignment),
      dialogSupports: !(dialog?.isModal ?? false),
    );
  }

  @override
  Future<void> setAlwaysOnTop(int viewId, bool isAlwaysOnTop) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setAlwaysOnTop(viewId, isAlwaysOnTop: isAlwaysOnTop),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setAsFrameless(int viewId) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setAsFrameless(viewId),
      dialogSupports: !(_dialogs[viewId]?.isModal ?? true),
    );
  }

  @override
  Future<void> setAspectRatio(int viewId, double ratio) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setAspectRatio(viewId, ratio));
  }

  @override
  Future<void> setBackgroundColor(int viewId, Color color) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setBackgroundColor(viewId, color: color),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setBadgeLabel(int viewId, String? label) async {
    if (!Platform.isMacOS) return;
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setBadgeLabel(viewId, label: label),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setBrightness(int viewId, Brightness brightness) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setBrightness(viewId, brightness),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setGlobalBrightness(Brightness brightness) async {
    final allViewIds = [..._dialogs.keys, ..._windows.keys]..sort();
    for (final viewId in allViewIds) {
      await _viewExistChecker(
        viewId,
        () async => await _nativeChannel.setBrightness(viewId, brightness),
        dialogSupports: true,
      );
    }
  }

  @override
  Future<void> setClosable(int viewId, bool isClosable) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setClosable(viewId, isClosable),
      dialogSupports: true,
    );
  }

  @override
  CloseMode getAppCloseMode() => closeMode;

  @override
  Future<void> setAppCloseMode(CloseMode closeMode) async {
    this.closeMode = closeMode;
    await applyNativeLifecyclePolicy();
  }

  @override
  Future<void> setFullScreen(int viewId, bool isFullScreen) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setFullScreen(viewId, isFullScreen: isFullScreen));
  }

  @override
  Future<void> setHasShadow(int viewId, bool value) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setHasShadow(viewId, value), dialogSupports: true);
  }

  @override
  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setIgnoreMouseEvents(viewId, ignore, forward: forward),
      dialogSupports: true,
    );
  }

  @override
  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(int viewId) async {
    return await _viewExistChecker(
          viewId,
          () async => await _nativeChannel.isIgnoreMouseEvents(viewId),
          dialogSupports: true,
        ) ??
        (mouseMoveEvents: false, ignore: false);
  }

  @override
  Future<void> setMaximizable(int viewId, bool isMaximizable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMaximizable(viewId, isMaximizable));
  }

  @override
  Future<void> setMaximumSize(int viewId, Size size) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setMaxSize(viewId, size: size),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setMinimizable(int viewId, bool isMinimizable) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setMinimizable(viewId, isMinimizable));
  }

  @override
  Future<void> setMinimumSize(int viewId, Size size) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setMinSize(viewId, size: size),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setMovable(int viewId, bool isMovable) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setMovable(viewId, isMovable),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setOpacity(int viewId, double opacity) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setOpacity(viewId, opacity), dialogSupports: true);
  }

  @override
  Future<void> setPosition(int viewId, Offset position) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setPosition(viewId, pos: position),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setPreventClose(int viewId, bool isPreventClose) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setPreventClose(viewId, isPreventClose: isPreventClose),
    );
  }

  @override
  Future<void> setProgressBar(double progress) async {
    if (Platform.isLinux) return;
    final id = _lifecycleViewId;
    if (id == null) return;
    await _viewExistChecker(id, () async => await _nativeChannel.setProgressBar(progress), dialogSupports: true);
  }

  @override
  Future<void> setResizable(int viewId, bool isResizable) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setResizable(viewId, isResizable),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setSize(int viewId, Size size) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.setSize(viewId, size: size), dialogSupports: true);
  }

  @override
  Future<void> setTitle(int viewId, String title) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setTitle(viewId, title: title),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setTitleBarStyle(
    int viewId,
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) async {
    await _viewExistChecker(
      viewId,
      () async => await _nativeChannel.setTitleBarStyle(
        viewId,
        style: style,
        closeVisibility: closeVisibility,
        maximizeVisibility: maximizeVisibility,
        minimizeVisibility: minimizeVisibility,
      ),
      dialogSupports: true,
    );
  }

  @override
  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) async {
    if (!Platform.isMacOS) return;

    await _viewExistChecker(
      viewId,
      () async =>
          await _nativeChannel.setVisibleOnAllWorkspaces(viewId, visible, visibleOnFullScreen: visibleOnFullScreen),
      dialogSupports: true,
    );
  }

  @override
  Future<void> show(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.show(viewId), dialogSupports: true);
  }

  @override
  Future<void> startDragging(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.startDragging(viewId), dialogSupports: true);
  }

  @override
  Future<void> startResizing(int viewId, ResizeEdge edge) async {
    if (Platform.isMacOS) return;
    await _viewExistChecker(viewId, () async => await _nativeChannel.startResizing(viewId, edge), dialogSupports: true);
  }

  @override
  Future<void> unmaximize(int viewId) async {
    await _viewExistChecker(viewId, () async => await _nativeChannel.unmaximize(viewId));
  }

  @override
  Future<bool> closeApp({CloseMode? closeMode}) async {
    final mode = closeMode ?? config.generalParams.closeMode;
    return await _closeApp(mode);
  }

  /// Closes every registered window (all roots and their subtrees).
  /// if all views successfully closed by mode `mode` return `true` else `false`
  Future<bool> _closeApp(CloseMode mode) async {
    final allRoots = _rootWindowIds()..sort();

    _saveLastWindowToReopen = false;
    await applyNativeLifecyclePolicy();
    for (final root in allRoots.reversed) {
      cascadeCloseService.attachWindow(root);
      unawaited(_closeSubtreeByMode(root, mode));
      final closed = await cascadeCloseService.waitWindow(root);
      if (!closed) {
        if (Platform.isMacOS) {
          _saveLastWindowToReopen = config.macosParams.saveLastWindowToReopen;
          await applyNativeLifecyclePolicy();
        }
        return false;
      }
    }

    return true;
  }

  Future<T?> _viewExistChecker<T>(int viewId, Future<T> Function() func, {bool dialogSupports = false}) async {
    if (dialogSupports) {
      if (!_windows.containsKey(viewId) && !_dialogs.containsKey(viewId)) return null;
    } else {
      if (!_windows.containsKey(viewId)) return null;
    }

    if (!_hasLiveFlutterView(viewId)) return null;
    try {
      return await func();
    } on PlatformException catch (e) {
      // Race during cascade close: native window gone before didChangeMetrics.
      if (e.code == 'NO_WINDOW') return null;
      rethrow;
    }
  }

  bool _hasLiveFlutterView(int viewId) {
    return WidgetsBinding.instance.platformDispatcher.view(id: viewId) != null;
  }
}
