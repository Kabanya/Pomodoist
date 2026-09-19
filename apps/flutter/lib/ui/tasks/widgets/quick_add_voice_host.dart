part of 'quick_add_bar.dart';

const _voiceSheetBorderRadius = BorderRadius.all(Radius.circular(12));

final _voiceSessions = Expando<VoiceQuickAddSessionSlot<_VoiceHostSession>>();

VoiceQuickAddSessionSlot<_VoiceHostSession> _voiceSessionOf(
  OverlayState overlay,
) => _voiceSessions[overlay] ??= VoiceQuickAddSessionSlot<_VoiceHostSession>();

ValueListenable<bool> voiceQuickAddActiveOf(BuildContext context) =>
    _voiceSessionOf(Overlay.of(context, rootOverlay: true));

class _VoiceHostSession {
  _VoiceHostSession(this.overlay, this.route);

  final OverlayState overlay;
  final ModalRoute<dynamic>? route;
  final key = GlobalKey<_VoiceQuickAddHostState>();
  final result = Completer<List<String>?>();
  late final OverlayEntry entry;

  void finish(List<String>? ids, {bool remove = true}) {
    if (result.isCompleted) return;
    _voiceSessionOf(overlay).finish(this);
    result.complete(ids);
    if (remove) {
      entry.remove();
      entry.dispose();
    }
  }
}

Future<List<String>?> showVoiceQuickAddSheet(
  BuildContext context,
  WidgetRef ref, {
  int? defaultPriority,
  DateTime? defaultDate,
  String? projectId,
  String? kanbanStatusId,
  String? labelId,
  ValueChanged<bool>? onExpandedChanged,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final sessions = _voiceSessionOf(overlay);
  final existing = sessions.current;
  if (existing != null) {
    overlay.rearrange([existing.entry], below: existing.entry);
    existing.key.currentState?._setExpanded(true);
    await existing.result.future;
    return null;
  }
  final access = await ref.read(voiceAccessViewModelProvider.notifier).check();
  if (!context.mounted || !overlay.mounted) return null;
  if (!access) {
    return showModalBottomSheet<List<String>>(
      context: context,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.panel),
        reverseDuration: AppMotion.duration(context, AppMotion.panel),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: LaunchOfferPaywall(
          compact: true,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
  // A second opener may have completed the entitlement check first.
  final pending = sessions.current;
  if (pending != null) {
    overlay.rearrange([pending.entry], below: pending.entry);
    pending.key.currentState?._setExpanded(true);
    await pending.result.future;
    return null;
  }
  FocusManager.instance.primaryFocus?.unfocus();
  final session = _VoiceHostSession(overlay, ModalRoute.of(context));
  session.entry = OverlayEntry(
    maintainState: true,
    builder: (_) => VoiceQuickAddHost._(
      key: session.key,
      session: session,
      defaultPriority: defaultPriority,
      defaultDate: defaultDate,
      projectId: projectId,
      kanbanStatusId: kanbanStatusId,
      labelId: labelId,
      onExpandedChanged: onExpandedChanged,
    ),
  );
  overlay.insert(session.entry);
  sessions.open(session);
  return session.result.future;
}

class VoiceQuickAddHost extends ConsumerStatefulWidget {
  const VoiceQuickAddHost._({
    required _VoiceHostSession session,
    this.defaultPriority,
    this.defaultDate,
    this.projectId,
    this.kanbanStatusId,
    this.labelId,
    this.onExpandedChanged,
    super.key,
  }) : _session = session;

  final _VoiceHostSession _session;
  final int? defaultPriority;
  final DateTime? defaultDate;
  final String? projectId;
  final String? kanbanStatusId;
  final String? labelId;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  ConsumerState<VoiceQuickAddHost> createState() => _VoiceQuickAddHostState();
}

class _VoiceQuickAddHostState extends ConsumerState<VoiceQuickAddHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final AnimationController _analysisProgressController;
  final _draftControllers = <_VoiceTaskDraftController>[];
  bool _expanded = true;
  LocalHistoryEntry? _backEntry;
  VoiceQuickAddState get _voice =>
      ref.read(voiceQuickAddViewModelProvider(widget._session));
  VoiceQuickAddViewModel get _voiceActions =>
      ref.read(voiceQuickAddViewModelProvider(widget._session).notifier);
  String? _saveError;
  ProviderSubscription<VoiceQuickAddState>? _voiceSubscription;
  int get _processingStepIndex {
    if (_draftControllers.isNotEmpty) {
      return 2;
    }
    if (_voice.analyzing ||
        _voice.isTranscribing ||
        (!_voice.captureActive && _voice.transcript.trim().isNotEmpty)) {
      return 1;
    }
    return 0;
  }

  List<DecomposedTaskDraft> get _acceptedTasks {
    final tasks = <DecomposedTaskDraft>[];
    for (final controller in _draftControllers) {
      final task = _acceptedTask(controller);
      if (task != null) {
        tasks.add(task);
      }
    }
    return tasks;
  }

  DecomposedTaskDraft? _acceptedTask(_VoiceTaskDraftController controller) {
    final quickAdd = controller.quickAdd.text.trim();
    if (quickAdd.isEmpty) {
      return null;
    }
    final description = controller.description.text.trim();
    final subtasks = <DecomposedTaskDraft>[];
    for (final subtask in controller.subtasks) {
      final task = _acceptedTask(subtask);
      if (task != null) {
        subtasks.add(task);
      }
    }
    return DecomposedTaskDraft(
      quickAdd: quickAdd,
      description: description.isEmpty ? null : description,
      subtasks: subtasks,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _analysisProgressController = AnimationController(vsync: this);
    _voiceSubscription = ref.listenManual(
      voiceQuickAddViewModelProvider(widget._session),
      (previous, next) {
        if (!mounted) return;
        if (previous?.draftRevision != next.draftRevision) {
          if (next.analyzing) {
            _setTaskDrafts(next.drafts);
          } else if (previous?.analyzing ?? false) {
            _setTaskDrafts(next.drafts);
            unawaited(_finishAnalysisProgress());
          } else {
            _setTaskDrafts(next.drafts);
          }
        }
        if (next.analyzing && !(previous?.analyzing ?? false)) {
          _startAnalysisProgress();
        }
        _voiceChanged();
      },
    );
    unawaited(_voiceActions.loadSmartMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onExpandedChanged?.call(true);
      _installBackHandler();
      unawaited(_voiceActions.restoreRecording());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voiceActions.setLocale(Localizations.localeOf(context).toLanguageTag());
    _syncPulse();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expanded = false;
    final back = _backEntry;
    _backEntry = null;
    back?.remove();
    widget._session.finish(null, remove: false);
    // The opener may have been disposed along with its route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onExpandedChanged?.call(false);
    });
    _voiceSubscription?.close();
    for (final controller in _draftControllers) {
      controller.dispose();
    }
    _pulseController.dispose();
    _analysisProgressController.dispose();
    super.dispose();
  }

  void _voiceChanged() {
    _setSheetState(() {});
  }

  Future<void> _closeVoice() async {
    if (await _voiceActions.closeVoice() && mounted) {
      widget._session.finish(null);
    }
  }

  String? get _error {
    final error = _saveError ?? _voice.error;
    final l10n = context.l10n;
    return switch (error) {
      null => null,
      VoiceQuickAddError.general => l10n.voiceStatusError,
      VoiceQuickAddError.settings => l10n.voiceSettingsFailed,
      VoiceQuickAddError.restricted => l10n.voiceAccessRestricted,
      VoiceQuickAddError.microphoneDenied => l10n.voiceMicrophoneDenied,
      VoiceQuickAddError.speechDenied => l10n.voiceSpeechDenied,
      VoiceQuickAddError.fallback => l10n.voiceFallbackError,
      VoiceQuickAddError.recognition => _voiceErrorMessage(
        _voice.recognitionErrorMessage,
      ),
      _ => error.toString(),
    };
  }

  void _installBackHandler() {
    if (_backEntry != null || !_expanded) return;
    if (Router.maybeOf(context) != null) return;
    final route = widget._session.route;
    if (route?.navigator == null) return;
    final entry = LocalHistoryEntry(
      onRemove: () {
        _backEntry = null;
        if (mounted && AppDateTimePicker.dismissFocused()) {
          _installBackHandler();
          return;
        }
        if (mounted && _expanded) _setExpanded(false);
      },
    );
    _backEntry = entry;
    route!.addLocalHistoryEntry(entry);
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _expanded = expanded);
    if (expanded) {
      _installBackHandler();
    } else {
      final back = _backEntry;
      _backEntry = null;
      back?.remove();
    }
    widget.onExpandedChanged?.call(expanded);
  }

  Future<void> _save() async {
    try {
      final created = await _voiceActions.save(
        _acceptedTasks,
        defaultPriority: widget.defaultPriority,
        defaultDate: widget.defaultDate,
        projectId: widget.projectId,
        kanbanStatusId: widget.kanbanStatusId,
        labelId: widget.labelId,
      );
      if (created == null || !mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.tasksCreated(created.length))),
      );
      widget._session.finish(created);
    } catch (_) {
      if (mounted) setState(() => _saveError = context.l10n.taskCreateFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(voiceQuickAddViewModelProvider(widget._session));
    final colors = Theme.of(context).colorScheme;
    final processing =
        _voice.isTranscribing || _voice.analyzing || _voice.saving;
    final recording = _voice.status == VoiceCaptureStatus.recording;
    final failed =
        _error != null ||
        _voice.status == VoiceCaptureStatus.error ||
        _voice.status == VoiceCaptureStatus.unsupportedPlatform;
    final ready = !processing && !recording && _draftControllers.isNotEmpty;
    final state = failed
        ? 'error'
        : processing
        ? 'processing'
        : recording
        ? 'recording'
        : ready
        ? 'ready'
        : 'idle';
    final color = failed
        ? colors.error
        : ready
        ? context.appColors.success
        : colors.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final panel = ValueListenableBuilder<double>(
      valueListenable: voicePanelBottomClearanceOf(context),
      builder: (context, bottom, _) => VoicePanelMotion(
        reservedInsets: EdgeInsets.only(bottom: bottom),
        expanded: _expanded,
        onCollapse: () => _setExpanded(false),
        onExpand: () => _setExpanded(true),
        panel: _expandedPanel(context),
        indicator: Semantics(
          liveRegion: true,
          label: failed ? context.l10n.voiceStatusError : _statusLabel(context),
          child: ExcludeSemantics(
            child: SizedBox.square(
              key: Key('voice-mini-$state'),
              dimension: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .08),
                        border: Border.all(color: color.withValues(alpha: .18)),
                      ),
                    ),
                  ),
                  if (processing)
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: reduceMotion ? .75 : null,
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
                  if (recording)
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value:
                            _voice.recordingSecondsRemaining /
                            voiceQuickAddMaxDuration.inSeconds,
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
                  if (recording && !failed)
                    _VoiceAmplitudeBars(level: _voice.amplitudeLevel)
                  else
                    Icon(
                      failed
                          ? LucideIcons.circleAlert
                          : ready
                          ? LucideIcons.check
                          : processing
                          ? LucideIcons.audioLines
                          : LucideIcons.mic,
                      color: color,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        ),
        stopButton: IconButton(
          key: const Key('voice-mini-stop'),
          tooltip: context.l10n.voiceStop,
          onPressed:
              _voice.captureActive && _voice.isCapturing && !_voice.stopping
              ? _voiceActions.stop
              : null,
          icon: const Icon(LucideIcons.square),
          color: colors.primary,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
        expandButton: IconButton(
          key: const Key('voice-expand'),
          tooltip: context.l10n.voiceExpand,
          onPressed: () => _setExpanded(true),
          icon: const Icon(LucideIcons.chevronUp),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
      ),
    );
    if (Router.maybeOf(context) == null) return panel;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_expanded) return false;
        _setExpanded(false);
        return true;
      },
      child: panel,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _voice.canStart) {
      unawaited(_voiceActions.refreshAccess());
    }
  }

  String _voiceErrorMessage(String message) {
    final l10n = context.l10n;
    if (message.contains('setActive: Session activation failed')) {
      return l10n.voiceMicrophoneUnavailable;
    }
    if (_voice.cloudMode &&
        const [
          'speech_unavailable',
          'speech_recognition_failed',
          'speech_network_unavailable',
        ].contains(_voice.voiceErrorCode)) {
      return l10n.voiceCloudServiceUnavailable;
    }
    return switch (_voice.voiceErrorCode) {
      'microphone_denied' || 'permission_denied' => l10n.voiceMicrophoneDenied,
      'speech_authorization_denied' ||
      'speech_permission_denied' => l10n.voiceSpeechDenied,
      'microphone_restricted' ||
      'speech_authorization_restricted' => l10n.voiceAccessRestricted,
      'speech_dictation_disabled' => l10n.voiceDictationDisabled,
      'speech_unavailable' ||
      'speech_recognition_failed' => l10n.voiceServiceUnavailable,
      'speech_locale_unsupported' => l10n.voiceLocaleUnsupported,
      'speech_network_unavailable' => l10n.voiceNetworkUnavailable,
      _ => l10n.voiceStatusError,
    };
  }

  void _startAnalysisProgress() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _analysisProgressController.value = .08;
      return;
    }
    _analysisProgressController
      ..stop()
      ..value = .08;
    unawaited(
      _analysisProgressController.animateTo(
        .92,
        duration: const Duration(seconds: 18),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _finishAnalysisProgress() async {
    if (MediaQuery.disableAnimationsOf(context)) {
      _analysisProgressController.value = 1;
      return;
    }
    try {
      await _analysisProgressController
          .animateTo(
            1,
            duration: AppMotion.duration(context, AppMotion.state),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
  }

  void _removeTask(int index) {
    _setSheetState(() {
      _draftControllers.removeAt(index).dispose();
    });
  }

  void _setTaskDrafts(List<DecomposedTaskDraft> tasks) {
    if (tasks.isEmpty) {
      _analysisProgressController
        ..stop()
        ..value = 0;
    }
    for (final controller in _draftControllers) {
      controller.dispose();
    }
    _draftControllers
      ..clear()
      ..addAll(
        tasks.map(
          (task) => _VoiceTaskDraftController(
            quickAdd: task.quickAdd,
            description: task.description,
            subtasks: task.subtasks,
          ),
        ),
      );
  }

  void _setSheetState(VoidCallback update) {
    if (!mounted) {
      return;
    }
    setState(update);
    _syncPulse();
  }

  void _syncPulse() {
    if (_voice.motionActive && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }
}
