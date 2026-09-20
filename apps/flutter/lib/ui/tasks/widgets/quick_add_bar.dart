import 'package:pomodoist/ui/voice/view_models/voice_quick_add_view_model.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadIconButton, ShadSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/onboarding/widgets/onboarding_gate.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_text_controller.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_details.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_panel_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_panel_clearance.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_quick_add_session.dart';

part 'quick_add_input.dart';
part 'quick_add_composer.dart';
part 'quick_add_voice_host.dart';
part 'quick_add_voice_panel.dart';
part 'quick_add_voice_panels.dart';
part 'quick_add_voice_drafts.dart';

const _quickAddIconTransitionDuration = Duration(milliseconds: 120);

const _quickAddSuccessHoldDuration = Duration(milliseconds: 800);

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
  final _identity = Object();
  bool get _busy =>
      ref.read(quickAddViewModelProvider(_identity)).result.isLoading;
  bool _showSuccess = false;
  bool _hasFocus = false;

  void _syncDraft() => ref
      .read(quickAddViewModelProvider(_identity).notifier)
      .updateDraft(_controller.text);

  @override
  void dispose() {
    _successTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      quickAddViewModelProvider(_identity).select((state) => state.result),
    );
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                      onChanged: (_) => _syncDraft(),
                      onSubmitted: (_) => _submit(),
                    ),
                    QuickAddDetails(
                      controller: _controller,
                      defaultDate: widget.defaultDate,
                      projectId: widget.projectId,
                      priority: widget.defaultPriority,
                      enabled: !_busy,
                      onChanged: _syncDraft,
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
    _syncDraft();
    _beginCreation();
    final task = await ref
        .read(quickAddViewModelProvider(_identity).notifier)
        .submit(
          priority: widget.defaultPriority,
          defaultDate: widget.defaultDate,
          projectId: widget.projectId,
          kanbanStatusId: widget.kanbanStatusId,
          labelId: widget.labelId,
        );
    if (!mounted) return;
    if (task != null) {
      _controller.clear();
      widget.onTaskCreated?.call([task]);
    } else if (ref.read(quickAddViewModelProvider(_identity)).result.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
    }
    _finishCreation(task != null);
  }

  void _beginCreation() {
    _successTimer?.cancel();
    setState(() {
      _showSuccess = false;
    });
  }

  void _finishCreation(bool succeeded) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
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
