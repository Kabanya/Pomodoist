import 'dart:async';
import 'dart:math' as math;

import 'package:app_voice/app_voice.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadIconButton, ShadSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../app/config/account_providers.dart';
import '../../../../app/config/app_l10n.dart';
import '../../../../app/config/providers.dart';
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
