import 'dart:async';
import 'dart:math' as math;

import 'package:app_voice/app_voice.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadIconButton, ShadSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../app/account_providers.dart';
import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/widgets/app_date_time_picker.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../billing/billing.dart';
import '../../../focus/presentation/focus_view_mode.dart';
import '../../../onboarding/onboarding_gate.dart';
import '../../../planning/data/task_decomposer.dart';
import '../../../planning/data/voice_quick_add_service.dart';
export '../../../planning/data/voice_quick_add_service.dart'
    show createVoiceQuickAddTasks;
import '../../../planning/domain/quick_add_parser.dart';
import '../../../voice/application/voice_quick_add_controller.dart';
import '../../../voice/data/voice_transcription_mode.dart';
import '../../domain/task_models.dart';
import 'quick_add_text_controller.dart';
import 'quick_add_details.dart';
import 'voice_panel_motion.dart';
import 'voice_panel_clearance.dart';
import 'voice_quick_add_session.dart';

const _voiceSheetBorderRadius = BorderRadius.all(Radius.circular(12));
const _quickAddIconTransitionDuration = Duration(milliseconds: 120);
const _quickAddSuccessHoldDuration = Duration(milliseconds: 800);

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
  var billing = ref.read(billingControllerProvider);
  if (billing.loading) {
    await ref.read(billingControllerProvider.notifier).reload();
    billing = ref.read(billingControllerProvider);
  }
  if (!context.mounted || !overlay.mounted) return null;
  if (!billing.hasActiveEntitlement) {
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

class QuickAddInput extends ConsumerStatefulWidget {
  const QuickAddInput({
    required this.controller,
    required this.decoration,
    this.textFieldKey,
    this.focusNode,
    this.style,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final QuickAddTextController controller;
  final InputDecoration decoration;
  final Key? textFieldKey;
  final FocusNode? focusNode;
  final TextStyle? style;
  final int? maxLines;
  final bool autofocus;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<QuickAddInput> createState() => _QuickAddInputState();
}

class _QuickAddInputState extends ConsumerState<QuickAddInput> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  TextEditingValue? _lastValueWithSuggestions;
  TextEditingValue? _valueBeforeSelection;
  String? _hiddenForText;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant QuickAddInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _hiddenForText = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    final labels = ref.watch(labelsProvider).value ?? const <LabelItem>[];
    final hint = ref.watch(quickAddHintTextProvider);
    final decoration = hint == null
        ? widget.decoration
        : widget.decoration.copyWith(hintText: hint);
    return RawAutocomplete<_QuickAddSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option.name,
      optionsBuilder: (value) {
        if (_hiddenForText == value.text) {
          _lastValueWithSuggestions = null;
          return const <_QuickAddSuggestion>[];
        }
        final suggestions = _suggestions(value, projects, labels).toList();
        _lastValueWithSuggestions = suggestions.isEmpty ? null : value;
        return suggestions;
      },
      onSelected: _insertSuggestion,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            final suggestions = _suggestions(
              controller.value,
              projects,
              labels,
            );
            final hasSuggestions =
                _hiddenForText != controller.text && suggestions.isNotEmpty;
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                hasSuggestions) {
              setState(() => _hiddenForText = controller.text);
              return KeyEventResult.handled;
            }
            if ((event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.tab) &&
                hasSuggestions) {
              _valueBeforeSelection = controller.value;
              onFieldSubmitted();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: widget.textFieldKey,
            controller: controller,
            focusNode: focusNode,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: widget.maxLines,
            style: widget.style,
            textInputAction: widget.textInputAction,
            decoration: decoration,
            onSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 220,
                minWidth: 220,
                maxWidth: 360,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final option = items[index];
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == index;
                  return ListTile(
                    key: ValueKey(
                      'quick-add-suggestion-${option.marker}${option.name}',
                    ),
                    dense: true,
                    leading: Text(option.marker),
                    title: Text(option.name),
                    tileColor: highlighted
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    onTap: () {
                      _valueBeforeSelection = widget.controller.value;
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTextChanged() {
    if (_hiddenForText != null && _hiddenForText != widget.controller.text) {
      setState(() => _hiddenForText = null);
    }
  }

  Iterable<_QuickAddSuggestion> _suggestions(
    TextEditingValue value,
    List<ProjectItem> projects,
    List<LabelItem> labels,
  ) {
    final token = _ActiveQuickAddToken.from(value);
    if (token == null) {
      return const <_QuickAddSuggestion>[];
    }
    final query = token.query.toLowerCase();
    final names = isQuickAddProjectMarker(token.marker)
        ? projects
              .where(
                (project) =>
                    project.id != inboxProjectId && !project.isArchived,
              )
              .map((project) => project.name)
        : labels.map((label) => label.name);
    return names
        .where((name) => name.toLowerCase().startsWith(query))
        .take(6)
        .map((name) => _QuickAddSuggestion(token.marker, name));
  }

  void _insertSuggestion(_QuickAddSuggestion suggestion) {
    final value =
        _valueBeforeSelection ??
        _lastValueWithSuggestions ??
        widget.controller.value;
    _valueBeforeSelection = null;
    final token = _ActiveQuickAddToken.from(value);
    if (token == null) {
      return;
    }
    final replacement =
        '${suggestion.marker}${_quickAddTokenValue(suggestion.name)} ';
    final text = value.text.replaceRange(token.start, token.end, replacement);
    final offset = token.start + replacement.length;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _lastValueWithSuggestions = null;
    _hiddenForText = text;
    widget.onChanged?.call(text);
  }
}

class _ActiveQuickAddToken {
  const _ActiveQuickAddToken({
    required this.marker,
    required this.query,
    required this.start,
    required this.end,
  });

  final String marker;
  final String query;
  final int start;
  final int end;

  static _ActiveQuickAddToken? from(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = value.text;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      return null;
    }
    var start = cursor;
    while (start > 0 && text[start - 1].trim().isNotEmpty) {
      start--;
    }
    var end = cursor;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    final beforeCursor = text.substring(start, cursor);
    if (beforeCursor.isEmpty) {
      return null;
    }
    final marker = beforeCursor[0];
    if (!isQuickAddProjectMarker(marker) && marker != '@') {
      return null;
    }
    final query = beforeCursor.length > 1 && beforeCursor[1] == '"'
        ? beforeCursor.substring(2)
        : beforeCursor.substring(1);
    return _ActiveQuickAddToken(
      marker: marker,
      query: query,
      start: start,
      end: end,
    );
  }
}

class _QuickAddSuggestion {
  const _QuickAddSuggestion(this.marker, this.name);

  final String marker;
  final String name;
}

String _quickAddTokenValue(String name) {
  return RegExp(r'[\s"\\]').hasMatch(name)
      ? quickAddQuotedMetadataValue(name)
      : name;
}

class QuickAddComposer extends ConsumerStatefulWidget {
  const QuickAddComposer({
    required this.onCompleted,
    required this.onCancel,
    this.initialText = '',
    this.defaultDate,
    this.projectId,
    this.labelId,
    this.onVoiceModeChanged,
    this.onVoiceSessionChanged,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onCancel;
  final String initialText;
  final DateTime? defaultDate;
  final String? projectId;
  final String? labelId;
  final ValueChanged<bool>? onVoiceModeChanged;
  final ValueChanged<bool>? onVoiceSessionChanged;

  @override
  ConsumerState<QuickAddComposer> createState() => _QuickAddComposerState();
}

class _QuickAddComposerState extends ConsumerState<QuickAddComposer> {
  final _controller = QuickAddTextController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.value = TextEditingValue(
      text: widget.initialText,
      selection: TextSelection.collapsed(offset: widget.initialText.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Focus(
        autofocus: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuickAddInput(
              textFieldKey: const Key('sidebar-quick-add-input'),
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.quickAddHint,
                prefixIcon: const Icon(LucideIcons.listPlus),
                suffixIcon: IconButton(
                  key: const Key('sidebar-quick-add-voice'),
                  tooltip: l10n.voiceQuickAdd,
                  onPressed: _busy ? null : _openVoiceSheet,
                  icon: const Icon(LucideIcons.mic),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            QuickAddDetails(
              controller: _controller,
              defaultDate: widget.defaultDate,
              projectId: widget.projectId,
              enabled: !_busy,
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                ShadButton.ghost(
                  enabled: !_busy,
                  onPressed: _busy ? null : _cancel,
                  child: Text(l10n.commonCancel),
                ),
                ShadButton(
                  key: const Key('sidebar-quick-add-submit'),
                  enabled: !_busy,
                  onPressed: _busy ? null : _submit,
                  leading: _busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.appColors.onAccent,
                          ),
                        )
                      : const Icon(LucideIcons.plus),
                  child: Text(l10n.commonAdd),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _cancel() {
    if (!_busy) widget.onCancel();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(quickAddServiceProvider)
          .createTask(
            input,
            defaultDate: widget.defaultDate,
            projectId: widget.projectId,
            labelId: widget.labelId,
          );
      if (mounted) widget.onCompleted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVoiceSheet() async {
    widget.onVoiceSessionChanged?.call(true);
    final created = await showVoiceQuickAddSheet(
      context,
      ref,
      defaultDate: widget.defaultDate,
      projectId: widget.projectId,
      labelId: widget.labelId,
      onExpandedChanged: (expanded) {
        if (mounted) widget.onVoiceModeChanged?.call(expanded);
      },
    );
    if (!mounted) return;
    widget.onVoiceSessionChanged?.call(false);
    if (created != null && created.isNotEmpty) widget.onCompleted();
  }
}

class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({
    this.defaultPriority,
    this.defaultDate,
    this.projectId,
    this.kanbanStatusId,
    this.labelId,
    this.inputKey,
    this.voiceButtonKey,
    this.submitButtonKey,
    this.onTaskCreated,
    super.key,
  });

  final int? defaultPriority;
  final DateTime? defaultDate;
  final String? projectId;
  final String? kanbanStatusId;
  final String? labelId;
  final Key? inputKey;
  final Key? voiceButtonKey;
  final Key? submitButtonKey;
  final ValueChanged<List<String>>? onTaskCreated;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = QuickAddTextController();
  final _focusNode = FocusNode();
  Timer? _successTimer;
  bool _busy = false;
  bool _showSuccess = false;
  bool _hasFocus = false;

  @override
  void dispose() {
    _successTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _hasFocus = value),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.hover),
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: _hasFocus ? colors.accent : colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    QuickAddInput(
                      focusNode: _focusNode,
                      enabled: !_busy,
                      textFieldKey: widget.inputKey,
                      controller: _controller,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: l10n.quickAddHint,
                        prefixIcon: const Icon(LucideIcons.listPlus),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    QuickAddDetails(
                      controller: _controller,
                      defaultDate: widget.defaultDate,
                      projectId: widget.projectId,
                      priority: widget.defaultPriority,
                      enabled: !_busy,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: l10n.voiceQuickAdd,
                child: ShadIconButton.ghost(
                  key: widget.voiceButtonKey,
                  width: 40,
                  height: 40,
                  enabled: !_busy,
                  onPressed: _busy ? null : _openVoiceSheet,
                  icon: const Icon(LucideIcons.mic),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: l10n.commonAdd,
                child: ShadIconButton.secondary(
                  key: widget.submitButtonKey,
                  width: 40,
                  height: 40,
                  enabled: !_busy,
                  onPressed: _busy ? null : _submit,
                  icon: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : _quickAddIconTransitionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _busy
                        ? const SizedBox.square(
                            key: Key('quick-add-submit-progress'),
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _showSuccess
                        ? const Icon(
                            LucideIcons.check,
                            key: Key('quick-add-submit-success'),
                          )
                        : const Icon(
                            LucideIcons.plus,
                            key: Key('quick-add-submit-idle'),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVoiceSheet() async {
    final created = await showVoiceQuickAddSheet(
      context,
      ref,
      defaultPriority: widget.defaultPriority,
      defaultDate: widget.defaultDate,
      projectId: widget.projectId,
      kanbanStatusId: widget.kanbanStatusId,
      labelId: widget.labelId,
    );
    if (!mounted || created == null || created.isEmpty) return;
    widget.onTaskCreated?.call(created);
    _finishCreation(true);
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) {
      return;
    }
    _beginCreation();
    var succeeded = false;
    try {
      final task = await ref
          .read(quickAddServiceProvider)
          .createTask(
            input,
            priority: widget.defaultPriority,
            defaultDate: widget.defaultDate,
            projectId: widget.projectId,
            kanbanStatusId: widget.kanbanStatusId,
            labelId: widget.labelId,
          );
      _controller.clear();
      widget.onTaskCreated?.call([task]);
      succeeded = true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) {
        _finishCreation(succeeded);
      }
    }
  }

  void _beginCreation() {
    _successTimer?.cancel();
    setState(() {
      _busy = true;
      _showSuccess = false;
    });
  }

  void _finishCreation(bool succeeded) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _busy = false;
      _showSuccess = succeeded && !reduceMotion;
    });
    if (succeeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _focusNode.requestFocus();
      });
    }
    if (!_showSuccess) {
      return;
    }
    _successTimer = Timer(
      _quickAddIconTransitionDuration + _quickAddSuccessHoldDuration,
      () {
        if (mounted) {
          setState(() => _showSuccess = false);
        }
      },
    );
  }
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
  late final VoiceQuickAddController _voice;
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
    _voice = VoiceQuickAddController(
      initialController: ref.read(voiceRecognitionControllerProvider),
      waitForMode: () =>
          ref.read(voiceTranscriptionModeProvider.notifier).ready,
      effectiveMode: () => effectiveVoiceTranscriptionMode(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        preferred: ref.read(voiceTranscriptionModeProvider),
        signedIn: ref.read(accountClientProvider)?.currentUserId != null,
      ),
      replaceController: () {
        ref.invalidate(voiceRecognitionControllerProvider);
        return ref.read(voiceRecognitionControllerProvider);
      },
      setMode: (mode) =>
          ref.read(voiceTranscriptionModeProvider.notifier).setMode(mode),
      signedIn: () => ref.read(accountClientProvider)?.currentUserId != null,
      preferences: () => ref.read(sharedPreferencesProvider.future),
      decomposer: () => ref.read(taskDecomposerProvider),
      locale: () => Localizations.localeOf(context).toLanguageTag(),
      onDrafts: _setTaskDrafts,
      onAnalysisStart: _startAnalysisProgress,
      onAnalysisFinish: _finishAnalysisProgress,
    )..addListener(_voiceChanged);
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _analysisProgressController = AnimationController(vsync: this);
    unawaited(_voice.loadSmartMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onExpandedChanged?.call(true);
      _installBackHandler();
      unawaited(_voice.restoreRecording());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _voice.dispose();
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
    if (await _voice.closeVoice() && mounted) widget._session.finish(null);
  }

  String? get _error {
    final error = _voice.error;
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

  set _error(String? value) => _voice.error = value;

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
    if (_voice.saving || !_voice.canStart || _acceptedTasks.isEmpty) return;
    setState(() => _voice.saving = true);
    try {
      final created = await ref
          .read(appDatabaseProvider)
          .transaction(
            () => createVoiceQuickAddTasks(
              ref.read(quickAddServiceProvider),
              _acceptedTasks,
              defaultPriority: widget.defaultPriority,
              defaultDate: widget.defaultDate,
              projectId: widget.projectId,
              kanbanStatusId: widget.kanbanStatusId,
              labelId: widget.labelId,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.tasksCreated(created.length))),
      );
      widget._session.finish(created);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.taskCreateFailed);
    } finally {
      if (mounted) setState(() => _voice.saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final processing =
        _voice.isTranscribing || _voice.analyzing || _voice.saving;
    final recording = _voice.status == VoiceRecognitionStatus.recording;
    final failed =
        _error != null ||
        _voice.status == VoiceRecognitionStatus.error ||
        _voice.status == VoiceRecognitionStatus.unsupportedPlatform;
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
              ? _voice.stop
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

  Widget _expandedPanel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(380, constraints.maxHeight),
          ),
          child: _expandedPanelContent(context),
        ),
      ),
    );
  }

  Widget _expandedPanelContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final acceptedTasks = _acceptedTasks;
    final acceptedTaskCount = _taskCount(acceptedTasks);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: _voiceSheetBorderRadius,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(380, MediaQuery.sizeOf(context).height * .86),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VoicePanelSwipeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _VoicePulse(
                      animation: _pulseController,
                      active:
                          _voice.motionActive &&
                          !MediaQuery.disableAnimationsOf(context),
                      listeningLevel:
                          _voice.status == VoiceRecognitionStatus.recording
                          ? _voice.amplitudeLevel
                          : null,
                      icon: _voice.analyzing
                          ? LucideIcons.sparkles
                          : _voice.isTranscribing
                          ? LucideIcons.audioLines
                          : LucideIcons.mic,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.voiceTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _statusLabel(context),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('voice-collapse'),
                      tooltip: l10n.voiceCollapse,
                      onPressed: () => _setExpanded(false),
                      icon: const Icon(LucideIcons.chevronDown),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      onPressed: _voice.saving ? null : _closeVoice,
                      icon: const Icon(LucideIcons.x),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    l10n.voiceSmartMode,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  ShadSwitch(
                    key: const Key('voice-smart-mode'),
                    value: _voice.smartMode,
                    enabled: !_voice.motionActive,
                    onChanged: _voice.motionActive ? null : _voice.setSmartMode,
                  ),
                  const Spacer(),
                  if (_voice.status == VoiceRecognitionStatus.recording)
                    Text(
                      _recordingTimeLabel,
                      key: const Key('voice-recording-countdown'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: AppTheme.monoTextStyle.fontFamily,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _VoiceProcessingSteps(activeIndex: _processingStepIndex),
              const SizedBox(height: 16),
              Flexible(
                child: AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.state),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _body(colorScheme),
                ),
              ),
              if (_voice.voiceController.canRetryTranscription &&
                  !_voice.captureActive &&
                  !_voice.isTranscribing) ...[
                const SizedBox(height: 10),
                Text(l10n.voiceRecordingSaved),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _voice.canStart ? _voice.start : null,
                    icon: const Icon(LucideIcons.mic),
                    label: Text(
                      _voice.transcript.isEmpty &&
                              _draftControllers.isEmpty &&
                              !_voice.voiceController.canRetryTranscription
                          ? l10n.voiceRecord
                          : l10n.voiceAgain,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _voice.captureActive &&
                            _voice.isCapturing &&
                            !_voice.stopping
                        ? _voice.stop
                        : null,
                    icon: const Icon(LucideIcons.square),
                    label: Text(l10n.voiceStop),
                  ),
                  if (_voice.voiceController.canRetryTranscription &&
                      !_voice.captureActive &&
                      !_voice.isTranscribing) ...[
                    FilledButton.icon(
                      key: const Key('voice-retry-transcription'),
                      onPressed: _voice.canStart
                          ? () => _voice.start(retry: true)
                          : null,
                      icon: const Icon(LucideIcons.rotateCw),
                      label: Text(l10n.voiceRetryTranscription),
                    ),
                  ],
                  if (_voice.needsPermissionRequest ||
                      _voice.settingsDestination != null)
                    OutlinedButton.icon(
                      key: const Key('voice-recover-access'),
                      onPressed: _voice.canStart ? _voice.recoverAccess : null,
                      icon: const Icon(LucideIcons.settings2),
                      label: Text(_recoveryLabel),
                    ),
                  if (_voice.canUseCloudFallback)
                    OutlinedButton.icon(
                      key: const Key('voice-use-cloud-transcription'),
                      onPressed: _voice.canStart
                          ? _voice.useCloudTranscription
                          : null,
                      icon: const Icon(LucideIcons.cloud),
                      label: Text(l10n.voiceUseCloudTranscription),
                    ),
                  if (_error != null &&
                      _voice.transcript.trim().isNotEmpty &&
                      !_voice.captureActive &&
                      !_voice.isTranscribing &&
                      !_voice.analyzing)
                    TextButton.icon(
                      onPressed: () =>
                          _voice.decomposeTranscript(_voice.transcript),
                      icon: const Icon(LucideIcons.rotateCw),
                      label: Text(l10n.voiceRetryAnalysis),
                    ),
                  FilledButton.icon(
                    onPressed:
                        _voice.saving ||
                            acceptedTaskCount == 0 ||
                            _voice.captureActive ||
                            _voice.isCapturing ||
                            _voice.isTranscribing ||
                            _voice.analyzing
                        ? null
                        : _save,
                    icon: const Icon(LucideIcons.check),
                    label: Text(l10n.voiceAddCount(acceptedTaskCount)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ColorScheme colorScheme) {
    if (_voice.analyzing) {
      return _AnalysisPanel(
        key: const ValueKey('analysis'),
        transcript: _voice.transcript,
        progress: _analysisProgressController,
        activity: _pulseController,
      );
    }
    if (_draftControllers.isNotEmpty) {
      return _TaskDraftList(
        key: const ValueKey('drafts'),
        controllers: _draftControllers,
        defaultDate: widget.defaultDate,
        projectId: widget.projectId,
        priority: widget.defaultPriority,
        enabled: !_voice.saving && !_voice.motionActive,
        onChanged: () => _setSheetState(() {}),
        onRemove: _removeTask,
      );
    }
    if (_voice.transcript.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty-transcript'));
    }
    return _TranscriptPanel(
      key: const ValueKey('transcript'),
      text: _voice.transcript,
      muted: false,
      colorScheme: colorScheme,
    );
  }

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (_voice.status) {
      VoiceRecognitionStatus.idle => l10n.voiceStatusIdle,
      VoiceRecognitionStatus.requestingPermission =>
        l10n.voiceStatusRequestingPermission,
      VoiceRecognitionStatus.recording => l10n.voiceStatusRecording,
      VoiceRecognitionStatus.transcribing => l10n.voiceStatusTranscribing,
      VoiceRecognitionStatus.canceled => l10n.voiceStatusCanceled,
      VoiceRecognitionStatus.unsupportedPlatform => l10n.voiceStatusUnsupported,
      VoiceRecognitionStatus.error => l10n.voiceStatusError,
      VoiceRecognitionStatus.completed =>
        _voice.analyzing ? l10n.voiceStatusAnalyzing : l10n.voiceStatusReview,
    };
  }

  String get _recordingTimeLabel {
    final minutes = _voice.recordingSecondsRemaining ~/ 60;
    final seconds = (_voice.recordingSecondsRemaining % 60).toString().padLeft(
      2,
      '0',
    );
    return '$minutes:$seconds';
  }

  String get _recoveryLabel {
    final l10n = context.l10n;
    if (_voice.needsPermissionRequest) return l10n.voiceAllowAccess;
    return switch (_voice.settingsDestination) {
      VoiceSettingsDestination.microphone => l10n.voiceOpenMicrophoneSettings,
      VoiceSettingsDestination.speech => l10n.voiceOpenSpeechSettings,
      VoiceSettingsDestination.dictation => l10n.voiceEnableDictation,
      null => l10n.voiceAllowAccess,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _voice.canStart) {
      unawaited(_voice.refreshAccess());
    }
  }

  String _voiceErrorMessage(String message) {
    final l10n = context.l10n;
    if (message.contains('setActive: Session activation failed')) {
      return l10n.voiceMicrophoneUnavailable;
    }
    if (_voice.voiceMode == VoiceTranscriptionMode.cloud &&
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
    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
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

int _taskCount(Iterable<DecomposedTaskDraft> tasks) {
  var count = 0;
  for (final task in tasks) {
    count += 1 + _taskCount(task.subtasks);
  }
  return count;
}

class _VoicePulse extends StatelessWidget {
  const _VoicePulse({
    required this.animation,
    required this.active,
    required this.listeningLevel,
    required this.icon,
  });

  final Animation<double> animation;
  final bool active;
  final double? listeningLevel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = active ? animation.value : 0.0;
        return SizedBox.square(
          dimension: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + value * .04,
                child: Opacity(
                  opacity: active ? .18 * (1 - value) : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.state),
                curve: Curves.easeOutCubic,
                width: active ? 58 : 52,
                height: active ? 58 : 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: active
                        ? colorScheme.primary.withValues(alpha: .28)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: listeningLevel == null
                    ? Icon(
                        icon,
                        color: active
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      )
                    : _VoiceAmplitudeBars(level: listeningLevel!),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceAmplitudeBars extends StatelessWidget {
  const _VoiceAmplitudeBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    const factors = [.45, .75, 1.0, .75, .45];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final effectiveLevel = reduceMotion ? .45 : level;
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return ExcludeSemantics(
      child: Row(
        key: const Key('voice-amplitude-bars'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < factors.length; index += 1) ...[
            AnimatedContainer(
              key: Key('voice-amplitude-bar-$index'),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              width: 3,
              height: 4 + 28 * effectiveLevel * factors[index],
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (index < factors.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

class _VoiceProcessingSteps extends StatelessWidget {
  const _VoiceProcessingSteps({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.voiceStepRecord,
      l10n.voiceStepAnalyze,
      l10n.voiceStepReview,
    ];
    const icons = [
      LucideIcons.mic,
      LucideIcons.sparkles,
      LucideIcons.listChecks,
    ];

    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: _VoiceProcessingStep(
              icon: icons[index],
              label: labels[index],
              active: index == activeIndex,
              complete: index < activeIndex,
            ),
          ),
      ],
    );
  }
}

class _VoiceProcessingStep extends StatelessWidget {
  const _VoiceProcessingStep({
    required this.icon,
    required this.label,
    required this.active,
    required this.complete,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = active || complete;
    final foreground = highlighted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return AnimatedDefaultTextStyle(
      duration: AppMotion.duration(context, AppMotion.state),
      curve: Curves.easeOutCubic,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: foreground,
        fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.state),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? colorScheme.primaryContainer
                  : complete
                  ? colorScheme.primary.withValues(alpha: .10)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              border: Border.all(
                color: highlighted
                    ? colorScheme.primary.withValues(alpha: .42)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    super.key,
    required this.text,
    required this.muted,
    required this.colorScheme,
  });

  final String text;
  final bool muted;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: muted
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({
    super.key,
    required this.transcript,
    required this.progress,
    required this.activity,
  });

  final String transcript;
  final Animation<double> progress;
  final Animation<double> activity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const Key('voice-analysis-status'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: .62),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: .24),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.voiceAnalyzing,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _TranscriptPreview(text: transcript),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LinearProgressIndicator(
                  minHeight: 3,
                  value: progress.value,
                );
              },
            ),
            const SizedBox(height: 14),
            const _SkeletonLine(widthFactor: .92),
            const SizedBox(height: 8),
            const _SkeletonLine(widthFactor: .74),
            const SizedBox(height: 8),
            const _SkeletonLine(widthFactor: .82),
          ],
        ),
      ),
    );
  }
}

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final content = Text(
      text,
      key: const Key('voice-transcript-visualization'),
      style: Theme.of(context).textTheme.bodyLarge,
    );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.state,
      curve: AppMotion.curve,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: content,
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(99),
        ),
        child: const SizedBox(height: 12),
      ),
    );
  }
}

class _VoiceTaskDraftController {
  _VoiceTaskDraftController({
    required String quickAdd,
    String? description,
    List<DecomposedTaskDraft> subtasks = const [],
  }) : quickAdd = QuickAddTextController(text: quickAdd),
       description = TextEditingController(text: description ?? ''),
       subtasks = [
         for (final subtask in subtasks)
           _VoiceTaskDraftController(
             quickAdd: subtask.quickAdd,
             description: subtask.description,
             subtasks: subtask.subtasks,
           ),
       ];

  final QuickAddTextController quickAdd;
  final TextEditingController description;
  final List<_VoiceTaskDraftController> subtasks;

  void dispose() {
    quickAdd.dispose();
    description.dispose();
    for (final subtask in subtasks) {
      subtask.dispose();
    }
  }
}

class _TaskDraftList extends StatelessWidget {
  const _TaskDraftList({
    super.key,
    required this.controllers,
    required this.onChanged,
    required this.onRemove,
    this.defaultDate,
    this.projectId,
    this.priority,
    this.enabled = true,
  });

  final List<_VoiceTaskDraftController> controllers;
  final DateTime? defaultDate;
  final String? projectId;
  final int? priority;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: controllers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          key: ValueKey(controllers[index]),
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.duration(context, AppMotion.task),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - value)),
                child: child,
              ),
            );
          },
          child: _TaskDraftItem(
            controller: controllers[index],
            depth: 0,
            index: index,
            onChanged: onChanged,
            defaultDate: defaultDate,
            projectId: projectId,
            priority: priority,
            enabled: enabled,
            onRemove: () => onRemove(index),
          ),
        );
      },
    );
  }
}

class _TaskDraftItem extends ConsumerWidget {
  const _TaskDraftItem({
    required this.controller,
    required this.depth,
    required this.index,
    required this.onChanged,
    required this.onRemove,
    this.defaultDate,
    this.projectId,
    this.inheritedProjectName,
    this.priority,
    this.enabled = true,
  });

  final _VoiceTaskDraftController controller;
  final DateTime? defaultDate;
  final String? projectId;
  final String? inheritedProjectName;
  final int? priority;
  final bool enabled;
  final int depth;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = ref
        .watch(quickAddParserProvider)
        .parse(
          controller.quickAdd.text,
          now: ref.read(clockProvider).now(),
          defaultDate: defaultDate,
        );
    final horizontalOffset = depth * 20.0;
    return Padding(
      padding: EdgeInsets.only(left: horizontalOffset),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fields(context)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: context.l10n.voiceRemoveTask,
                onPressed: enabled ? onRemove : null,
                icon: const Icon(LucideIcons.trash2),
              ),
            ],
          ),
          for (
            var childIndex = 0;
            childIndex < controller.subtasks.length;
            childIndex++
          ) ...[
            const SizedBox(height: 10),
            _TaskDraftItem(
              controller: controller.subtasks[childIndex],
              depth: depth + 1,
              index: childIndex,
              onChanged: onChanged,
              defaultDate: defaultDate,
              projectId: parsed.project == null ? projectId : null,
              inheritedProjectName: parsed.project ?? inheritedProjectName,
              priority: priority,
              enabled: enabled,
              onRemove: () {
                controller.subtasks.removeAt(childIndex).dispose();
                onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _fields(BuildContext context) {
    return Column(
      children: [
        QuickAddInput(
          controller: controller.quickAdd,
          enabled: enabled,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.voiceTaskLabel(index + 1),
            prefixIcon: Icon(
              depth == 0
                  ? LucideIcons.circleCheck
                  : LucideIcons.cornerDownRight,
            ),
          ),
        ),
        QuickAddDetails(
          controller: controller.quickAdd,
          defaultDate: defaultDate,
          projectId: projectId,
          inheritedProjectName: inheritedProjectName,
          priority: priority,
          enabled: enabled,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: enabled,
          controller: controller.description,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.taskComment,
            hintText: context.l10n.taskCommentHint,
            prefixIcon: const Icon(LucideIcons.alignLeft),
          ),
        ),
      ],
    );
  }
}
