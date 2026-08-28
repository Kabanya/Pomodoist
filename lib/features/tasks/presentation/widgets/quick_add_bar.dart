import 'dart:async';
import 'dart:math' as math;

import 'package:app_voice/app_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../app/account_providers.dart';
import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/db/app_database.dart';
import '../../../billing/billing.dart';
import '../../../focus/presentation/focus_view_mode.dart';
import '../../../onboarding/onboarding_gate.dart';
import '../../../planning/data/task_decomposer.dart';
import '../../domain/task_models.dart';
import 'quick_add_text_controller.dart';

const _voiceSheetBorderRadius = BorderRadius.vertical(top: Radius.circular(28));
const _voiceSmartModePreferenceKey = 'voice.smartMode';
const _voiceMaxDuration = Duration(seconds: 59);

Future<List<DecomposedTaskDraft>?> showVoiceQuickAddSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  var billing = ref.read(billingControllerProvider);
  if (billing.loading) {
    await ref.read(billingControllerProvider.notifier).reload();
    billing = ref.read(billingControllerProvider);
  }
  if (!context.mounted) {
    return null;
  }
  if (!billing.hasActiveEntitlement) {
    return showModalBottomSheet<List<DecomposedTaskDraft>>(
      context: context,
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
  return showModalBottomSheet<List<DecomposedTaskDraft>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _VoiceQuickAddSheet(),
  );
}

Future<List<String>> createVoiceQuickAddTasks(
  WidgetRef ref,
  Iterable<DecomposedTaskDraft> tasks, {
  int? defaultPriority,
  DateTime? defaultDate,
  String? projectId,
  String? kanbanStatusId,
}) async {
  final quickAdd = ref.read(quickAddServiceProvider);

  Future<List<String>> createAll(
    Iterable<DecomposedTaskDraft> drafts, {
    String? parentId,
    String? projectId,
    String? sectionId,
  }) async {
    final createdIds = <String>[];
    for (final draft in drafts) {
      final input = draft.quickAdd.trim();
      if (input.isEmpty) {
        continue;
      }
      final task = await quickAdd.createTaskWithContext(
        input,
        description: draft.description,
        parentId: parentId,
        projectId: projectId,
        sectionId: sectionId,
        priority: defaultPriority,
        defaultDate: defaultDate,
        kanbanStatusId: kanbanStatusId,
      );
      createdIds.add(task.id);
      createdIds.addAll(
        await createAll(
          draft.subtasks,
          parentId: task.id,
          projectId: task.projectId ?? projectId,
          sectionId: task.sectionId ?? sectionId,
        ),
      );
    }
    return createdIds;
  }

  return createAll(tasks, projectId: projectId);
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
            maxLines: widget.maxLines,
            style: widget.style,
            textInputAction: widget.textInputAction,
            decoration: decoration,
            onSubmitted: widget.onSubmitted,
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
    final names = token.marker == '#'
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
    if (marker != '#' && marker != '@') {
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
  return RegExp(r'\s').hasMatch(name) ? '"$name"' : name;
}

class QuickAddComposer extends ConsumerStatefulWidget {
  const QuickAddComposer({
    required this.onCompleted,
    required this.onCancel,
    this.onVoiceModeChanged,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onCancel;
  final ValueChanged<bool>? onVoiceModeChanged;

  @override
  ConsumerState<QuickAddComposer> createState() => _QuickAddComposerState();
}

class _QuickAddComposerState extends ConsumerState<QuickAddComposer> {
  final _controller = QuickAddTextController();
  bool _busy = false;

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
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.quickAddHint,
                prefixIcon: const Icon(Icons.add_task),
                suffixIcon: IconButton(
                  key: const Key('sidebar-quick-add-voice'),
                  tooltip: l10n.voiceQuickAdd,
                  onPressed: _busy ? null : _openVoiceSheet,
                  icon: const Icon(Icons.mic_none),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: Text(l10n.commonCancel),
                ),
                FilledButton.icon(
                  key: const Key('sidebar-quick-add-submit'),
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(l10n.commonAdd),
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
      await ref.read(quickAddServiceProvider).createTask(input);
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
    widget.onVoiceModeChanged?.call(true);
    final tasks = await showVoiceQuickAddSheet(context, ref);
    widget.onVoiceModeChanged?.call(false);
    if (!mounted || tasks == null || tasks.isEmpty) return;
    setState(() => _busy = true);
    try {
      final created = await createVoiceQuickAddTasks(ref, tasks);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final createdLabel = context.l10n.tasksCreated(created.length);
      widget.onCompleted();
      if (created.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(createdLabel)));
      }
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
}

class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({
    this.defaultPriority,
    this.defaultDate,
    this.projectId,
    this.kanbanStatusId,
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
  final Key? inputKey;
  final Key? voiceButtonKey;
  final Key? submitButtonKey;
  final ValueChanged<List<String>>? onTaskCreated;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = QuickAddTextController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: QuickAddInput(
                textFieldKey: widget.inputKey,
                controller: _controller,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l10n.quickAddHint,
                  prefixIcon: const Icon(Icons.add_task),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              key: widget.voiceButtonKey,
              tooltip: l10n.voiceQuickAdd,
              onPressed: _busy ? null : _openVoiceSheet,
              icon: const Icon(Icons.mic_none),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              key: widget.submitButtonKey,
              tooltip: l10n.commonAdd,
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVoiceSheet() async {
    final tasks = await showVoiceQuickAddSheet(context, ref);
    if (!mounted || tasks == null || tasks.isEmpty) {
      return;
    }
    await _createVoiceTasks(tasks);
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final task = await ref
          .read(quickAddServiceProvider)
          .createTask(
            input,
            priority: widget.defaultPriority,
            defaultDate: widget.defaultDate,
            projectId: widget.projectId,
            kanbanStatusId: widget.kanbanStatusId,
          );
      _controller.clear();
      widget.onTaskCreated?.call([task]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createVoiceTasks(List<DecomposedTaskDraft> tasks) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await createVoiceQuickAddTasks(
        ref,
        tasks,
        defaultPriority: widget.defaultPriority,
        defaultDate: widget.defaultDate,
        projectId: widget.projectId,
        kanbanStatusId: widget.kanbanStatusId,
      );
      if (mounted && created.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_createdLabel(created.length))));
        widget.onTaskCreated?.call(created);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _createdLabel(int count) {
    return context.l10n.tasksCreated(count);
  }
}

class _VoiceQuickAddSheet extends ConsumerStatefulWidget {
  const _VoiceQuickAddSheet();

  @override
  ConsumerState<_VoiceQuickAddSheet> createState() =>
      _VoiceQuickAddSheetState();
}

class _VoiceQuickAddSheetState extends ConsumerState<_VoiceQuickAddSheet>
    with TickerProviderStateMixin {
  late final VoiceRecognitionController _voiceController;
  late final AnimationController _pulseController;
  late final AnimationController _analysisProgressController;
  VoiceRecognitionStatus _status = VoiceRecognitionStatus.idle;
  StreamSubscription<VoiceRecognitionEvent>? _subscription;
  StreamSubscription<double>? _amplitudeSubscription;
  final _draftControllers = <_VoiceTaskDraftController>[];
  String _transcript = '';
  String? _error;
  bool _analyzing = false;
  bool _captureActive = false;
  bool _smartMode = false;
  bool _smartModeChanged = false;
  double _amplitudeLevel = 0;
  int _recordingSecondsRemaining = _voiceMaxDuration.inSeconds;
  Timer? _recordingTimer;

  bool get _isCapturing =>
      _status == VoiceRecognitionStatus.recording ||
      _status == VoiceRecognitionStatus.requestingPermission;

  bool get _isTranscribing => _status == VoiceRecognitionStatus.transcribing;

  bool get _canStart =>
      !_captureActive && !_isCapturing && !_isTranscribing && !_analyzing;

  bool get _motionActive =>
      _captureActive || _isCapturing || _isTranscribing || _analyzing;

  int get _processingStepIndex {
    if (_draftControllers.isNotEmpty) {
      return 2;
    }
    if (_analyzing ||
        _isTranscribing ||
        (!_captureActive && _transcript.trim().isNotEmpty)) {
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
    _voiceController = ref.read(voiceRecognitionControllerProvider);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _analysisProgressController = AnimationController(vsync: this);
    unawaited(_loadSmartMode());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _amplitudeSubscription?.cancel();
    _recordingTimer?.cancel();
    for (final controller in _draftControllers) {
      controller.dispose();
    }
    _pulseController.dispose();
    _analysisProgressController.dispose();
    if (_captureActive || _isCapturing || _isTranscribing) {
      unawaited(_voiceController.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _VoicePulse(
                    animation: _pulseController,
                    active: _motionActive,
                    listeningLevel: _status == VoiceRecognitionStatus.recording
                        ? _amplitudeLevel
                        : null,
                    icon: _analyzing
                        ? Icons.auto_awesome
                        : _isTranscribing
                        ? Icons.graphic_eq
                        : Icons.mic_none,
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
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    l10n.voiceSmartMode,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    key: const Key('voice-smart-mode'),
                    value: _smartMode,
                    onChanged: _motionActive ? null : _setSmartMode,
                  ),
                  const Spacer(),
                  if (_status == VoiceRecognitionStatus.recording)
                    Text(
                      _recordingTimeLabel,
                      key: const Key('voice-recording-countdown'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _body(colorScheme),
                ),
              ),
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
                    onPressed: _canStart ? _start : null,
                    icon: const Icon(Icons.mic_none),
                    label: Text(
                      _transcript.isEmpty && _draftControllers.isEmpty
                          ? l10n.voiceRecord
                          : l10n.voiceAgain,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _captureActive && _isCapturing ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.voiceStop),
                  ),
                  if (_error != null &&
                      _transcript.trim().isNotEmpty &&
                      !_captureActive &&
                      !_isTranscribing &&
                      !_analyzing)
                    TextButton.icon(
                      onPressed: () => _decomposeTranscript(_transcript),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.voiceRetryAnalysis),
                    ),
                  FilledButton.icon(
                    onPressed:
                        acceptedTaskCount == 0 ||
                            _captureActive ||
                            _isCapturing ||
                            _isTranscribing ||
                            _analyzing
                        ? null
                        : () => Navigator.of(context).pop(acceptedTasks),
                    icon: const Icon(Icons.check),
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
    if (_analyzing) {
      return _AnalysisPanel(
        key: const ValueKey('analysis'),
        transcript: _transcript,
        progress: _analysisProgressController,
        activity: _pulseController,
      );
    }
    if (_draftControllers.isNotEmpty) {
      return _TaskDraftList(
        key: const ValueKey('drafts'),
        controllers: _draftControllers,
        onChanged: () => _setSheetState(() {}),
        onRemove: _removeTask,
      );
    }
    if (_transcript.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty-transcript'));
    }
    return _TranscriptPanel(
      key: const ValueKey('transcript'),
      text: _transcript,
      muted: false,
      colorScheme: colorScheme,
    );
  }

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (_status) {
      VoiceRecognitionStatus.idle => l10n.voiceStatusIdle,
      VoiceRecognitionStatus.requestingPermission =>
        l10n.voiceStatusRequestingPermission,
      VoiceRecognitionStatus.recording => l10n.voiceStatusRecording,
      VoiceRecognitionStatus.transcribing => l10n.voiceStatusTranscribing,
      VoiceRecognitionStatus.canceled => l10n.voiceStatusCanceled,
      VoiceRecognitionStatus.unsupportedPlatform => l10n.voiceStatusUnsupported,
      VoiceRecognitionStatus.error => l10n.voiceStatusError,
      VoiceRecognitionStatus.completed =>
        _analyzing ? l10n.voiceStatusAnalyzing : l10n.voiceStatusReview,
    };
  }

  String get _recordingTimeLabel {
    final minutes = _recordingSecondsRemaining ~/ 60;
    final seconds = (_recordingSecondsRemaining % 60).toString().padLeft(
      2,
      '0',
    );
    return '$minutes:$seconds';
  }

  Future<void> _loadSmartMode() async {
    final preferences = await ref.read(sharedPreferencesProvider.future);
    if (!mounted || _smartModeChanged) {
      return;
    }
    _setSheetState(() {
      _smartMode = preferences?.getBool(_voiceSmartModePreferenceKey) ?? false;
    });
  }

  void _setSmartMode(bool value) {
    _smartModeChanged = true;
    _setSheetState(() => _smartMode = value);
    unawaited(_saveSmartMode(value));
  }

  Future<void> _saveSmartMode(bool value) async {
    final preferences = await ref.read(sharedPreferencesProvider.future);
    await preferences?.setBool(_voiceSmartModePreferenceKey, value);
  }

  void _startRecordingCountdown() {
    _recordingTimer?.cancel();
    _setSheetState(() {
      _recordingSecondsRemaining = _voiceMaxDuration.inSeconds;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _status != VoiceRecognitionStatus.recording) {
        timer.cancel();
        return;
      }
      _setSheetState(() {
        if (_recordingSecondsRemaining > 0) {
          _recordingSecondsRemaining -= 1;
        }
      });
      if (_recordingSecondsRemaining == 0) {
        timer.cancel();
      }
    });
  }

  void _stopRecordingCountdown() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _startAmplitudeMeter() {
    final previous = _amplitudeSubscription;
    if (previous != null) {
      unawaited(previous.cancel());
    }
    _amplitudeSubscription = _voiceController.amplitudeDbfs.listen((dbfs) {
      if (!mounted ||
          _status != VoiceRecognitionStatus.recording ||
          !dbfs.isFinite) {
        return;
      }
      _setSheetState(() {
        _amplitudeLevel = ((dbfs + 60) / 60).clamp(0.0, 1.0);
      });
    }, onError: (_) {});
  }

  void _stopAmplitudeMeter() {
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (_amplitudeLevel != 0) {
      _setSheetState(() => _amplitudeLevel = 0);
    }
  }

  Future<void> _start() async {
    if (!_canStart) {
      return;
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    _setSheetState(() {
      _captureActive = true;
      _status = VoiceRecognitionStatus.requestingPermission;
      _error = null;
      _transcript = '';
      _analyzing = false;
      _analysisProgressController
        ..stop()
        ..value = 0;
      _setTaskDrafts(const <DecomposedTaskDraft>[]);
    });
    _stopRecordingCountdown();
    _stopAmplitudeMeter();
    final previousSubscription = _subscription;
    _subscription = null;
    await previousSubscription?.cancel();
    if (!mounted) {
      return;
    }
    try {
      final stream = _voiceController.start(
        VoiceRecognitionConfig(locale: locale, maxDuration: _voiceMaxDuration),
      );
      _subscription = stream.listen(
        _handleEvent,
        onDone: () {
          if (mounted) {
            _stopRecordingCountdown();
            _stopAmplitudeMeter();
            _setSheetState(() {
              _captureActive = false;
              if (_isCapturing || _isTranscribing) {
                _status = VoiceRecognitionStatus.idle;
              }
            });
          }
        },
      );
    } catch (error) {
      _setSheetState(() {
        _captureActive = false;
        _status = VoiceRecognitionStatus.error;
        _error = _voiceErrorMessage(error.toString());
      });
    }
  }

  Future<void> _stop() async {
    await _voiceController.stop();
  }

  void _handleEvent(VoiceRecognitionEvent event) {
    if (!mounted) {
      return;
    }
    var shouldDecompose = false;
    _setSheetState(() {
      _status = event.status;
      switch (event.status) {
        case VoiceRecognitionStatus.completed:
          _captureActive = false;
          _transcript = event.finalText ?? _transcript;
          if (_transcript.trim().isNotEmpty) {
            shouldDecompose = true;
          }
        case VoiceRecognitionStatus.canceled:
          _captureActive = false;
        case VoiceRecognitionStatus.error:
        case VoiceRecognitionStatus.unsupportedPlatform:
          _captureActive = false;
          _error = event.error == null
              ? null
              : _voiceErrorMessage(event.error!.message);
        case VoiceRecognitionStatus.idle:
        case VoiceRecognitionStatus.requestingPermission:
        case VoiceRecognitionStatus.recording:
        case VoiceRecognitionStatus.transcribing:
          break;
      }
    });
    if (event.status == VoiceRecognitionStatus.recording) {
      _startRecordingCountdown();
      _startAmplitudeMeter();
    } else if (event.status == VoiceRecognitionStatus.transcribing ||
        event.status == VoiceRecognitionStatus.completed ||
        event.status == VoiceRecognitionStatus.canceled ||
        event.status == VoiceRecognitionStatus.error ||
        event.status == VoiceRecognitionStatus.unsupportedPlatform) {
      _stopRecordingCountdown();
      _stopAmplitudeMeter();
    }
    if (shouldDecompose) {
      unawaited(_decomposeTranscript(_transcript));
    }
  }

  String _voiceErrorMessage(String message) =>
      message.contains('setActive: Session activation failed')
      ? context.l10n.voiceMicrophoneUnavailable
      : context.l10n.voiceStatusError;

  Future<void> _decomposeTranscript(String transcript) async {
    _setSheetState(() {
      _analyzing = true;
      _error = null;
      _setTaskDrafts(const <DecomposedTaskDraft>[]);
    });
    _startAnalysisProgress();
    List<DecomposedTaskDraft> drafts;
    String? error;
    try {
      final tasks = await ref
          .read(taskDecomposerProvider)
          .decompose(
            transcript,
            now: DateTime.now(),
            locale: Localizations.localeOf(context).toLanguageTag(),
            smartMode: _smartMode,
          );
      if (!mounted) {
        return;
      }
      drafts = tasks.isEmpty ? fallbackQuickAddTasks(transcript) : tasks;
    } catch (exception) {
      if (!mounted) {
        return;
      }
      error = exception is TaskDecompositionException
          ? exception.message
          : context.l10n.voiceFallbackError;
      drafts = fallbackQuickAddTasks(transcript);
    }
    await _finishAnalysisProgress();
    if (!mounted) {
      return;
    }
    _setSheetState(() {
      _error = error;
      _setTaskDrafts(drafts);
      _analyzing = false;
    });
  }

  void _startAnalysisProgress() {
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
    try {
      await _analysisProgressController
          .animateTo(
            1,
            duration: const Duration(milliseconds: 180),
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
    if (_motionActive) {
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
                scale: 1 + value * .28,
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
                duration: const Duration(milliseconds: 220),
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
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(
                        alpha: active ? .18 : .08,
                      ),
                      blurRadius: active ? 24 : 12,
                      offset: const Offset(0, 10),
                    ),
                  ],
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
      Icons.mic_none,
      Icons.auto_awesome,
      Icons.checklist_outlined,
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
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: foreground,
        fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
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
                    Icons.auto_awesome,
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
            _KineticTranscript(text: transcript, activity: activity),
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

class _KineticTranscript extends StatelessWidget {
  const _KineticTranscript({required this.text, required this.activity});

  final String text;
  final Animation<double> activity;

  @override
  Widget build(BuildContext context) {
    final words = RegExp(
      r'\S+',
    ).allMatches(text).map((match) => match.group(0)!).toList();
    if (words.isEmpty) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(
      milliseconds: math.min(1400, 220 + (words.length - 1) * 70),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final activityAnimation = reduceMotion
        ? const AlwaysStoppedAnimation<double>(0)
        : activity;

    return Semantics(
      key: const Key('voice-transcript-visualization'),
      label: text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: activityAnimation,
          builder: (context, _) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
              duration: reduceMotion ? Duration.zero : duration,
              builder: (context, progress, _) {
                return Wrap(
                  spacing: 5,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < words.length; index += 1)
                      _word(
                        context,
                        colorScheme,
                        words[index],
                        index,
                        words.length,
                        duration,
                        progress,
                        activityAnimation.value,
                        reduceMotion,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _word(
    BuildContext context,
    ColorScheme colorScheme,
    String word,
    int index,
    int wordCount,
    Duration duration,
    double progress,
    double activity,
    bool reduceMotion,
  ) {
    final span = math.min(1.0, 220 / duration.inMilliseconds);
    final start = wordCount == 1 ? 0.0 : index / (wordCount - 1) * (1 - span);
    final local = ((progress - start) / span).clamp(0.0, 1.0);
    final value = Curves.easeOutCubic.transform(local);
    final position = wordCount == 1 ? .5 : index / (wordCount - 1);
    final emphasis = reduceMotion
        ? 0.0
        : (1 - (position - activity).abs() * 3).clamp(0.0, 1.0);
    final baseColor = Color.lerp(
      colorScheme.primary,
      colorScheme.onSurface,
      value,
    );
    return Opacity(
      key: Key('voice-transcript-word-$index'),
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - value)),
        child: Text(
          word,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Color.lerp(baseColor, colorScheme.primary, emphasis * .55),
            fontWeight: FontWeight.lerp(
              FontWeight.lerp(FontWeight.w700, FontWeight.w500, value),
              FontWeight.w700,
              emphasis * .45,
            ),
          ),
        ),
      ),
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
  }) : quickAdd = TextEditingController(text: quickAdd),
       description = TextEditingController(text: description ?? ''),
       subtasks = [
         for (final subtask in subtasks)
           _VoiceTaskDraftController(
             quickAdd: subtask.quickAdd,
             description: subtask.description,
             subtasks: subtask.subtasks,
           ),
       ];

  final TextEditingController quickAdd;
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
  });

  final List<_VoiceTaskDraftController> controllers;
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
          duration: Duration(milliseconds: 180 + index * 45),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: child,
              ),
            );
          },
          child: _TaskDraftItem(
            controller: controllers[index],
            depth: 0,
            index: index,
            onChanged: onChanged,
            onRemove: () => onRemove(index),
          ),
        );
      },
    );
  }
}

class _TaskDraftItem extends StatelessWidget {
  const _TaskDraftItem({
    required this.controller,
    required this.depth,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final _VoiceTaskDraftController controller;
  final int depth;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
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
        TextField(
          controller: controller.quickAdd,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.voiceTaskLabel(index + 1),
            prefixIcon: Icon(
              depth == 0 ? Icons.task_alt : Icons.subdirectory_arrow_right,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.description,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.taskComment,
            hintText: context.l10n.taskCommentHint,
            prefixIcon: const Icon(Icons.notes_outlined),
          ),
        ),
      ],
    );
  }
}
