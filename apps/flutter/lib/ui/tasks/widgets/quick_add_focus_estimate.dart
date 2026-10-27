import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';

class QuickAddFocusEstimateChip extends StatefulWidget {
  const QuickAddFocusEstimateChip({
    super.key,
    required this.estimate,
    required this.manual,
    required this.workSeconds,
    required this.enabled,
    required this.onChanged,
    this.touchTargets = false,
    this.desktop = false,
    this.iconsOnly = false,
  });

  final int? estimate;
  final bool manual;
  final int? workSeconds;
  final bool enabled;
  final bool touchTargets;
  final bool desktop;
  final bool iconsOnly;
  final ValueChanged<int?> onChanged;

  @override
  State<QuickAddFocusEstimateChip> createState() =>
      _QuickAddFocusEstimateChipState();
}

class _QuickAddFocusEstimateChipState extends State<QuickAddFocusEstimateChip> {
  final _popover = ShadPopoverController();
  final _input = TextEditingController();
  final _trigger = GlobalKey();
  final _triggerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _popover.addListener(_visibilityChanged);
  }

  void _visibilityChanged() {
    if (!_popover.isOpen) _triggerFocus.requestFocus();
    setState(() {});
  }

  @override
  void didUpdateWidget(QuickAddFocusEstimateChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _popover.isOpen) _popover.hide();
    if (oldWidget.estimate != widget.estimate &&
        parseQuickAddFocusEstimate(_input.text) != widget.estimate) {
      _input.text = '${widget.estimate ?? 1}';
    }
  }

  @override
  void dispose() {
    _popover.removeListener(_visibilityChanged);
    _popover.dispose();
    _input.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_popover.isOpen) {
      _input.text = '${(widget.estimate ?? 1).clamp(1, 999)}';
      _input.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _input.text.length,
      );
    }
    _popover.toggle();
  }

  void _step(int delta) {
    final count = parseQuickAddFocusEstimate(_input.text);
    if (!widget.enabled || count == null) return;
    final next = (count + delta).clamp(1, 999);
    _input.text = '$next';
    widget.onChanged(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final box = _trigger.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: media.size.center(Offset.zero),
            width: 1,
            height: 1,
          );
    final space = pickerAvailableSpace(
      anchor,
      media.size,
      viewPadding: media.viewPadding,
      viewInsets: media.viewInsets,
    );
    final width = math.max(1.0, math.min(320.0, space.width - 26));
    final height = math.max(1.0, space.height - 26);
    final centerX = space.width <= width + 26
        ? space.center.dx
        : anchor.center.dx.clamp(
            space.left + (width + 26) / 2,
            space.right - (width + 26) / 2,
          );
    final style = colors.quickAddStyle(
      colors.quickAddTokenColor(QuickAddTokenKind.focusEstimate),
    );
    final foreground = style.color!;
    final label = widget.estimate == null
        ? l10n.quickAddFocusEstimate
        : l10n.quickAddEstimatedPomodoros(widget.estimate!);
    return ShadPopover(
      controller: _popover,
      anchor: ShadGlobalAnchor(Offset(centerX, space.top)),
      padding: const EdgeInsets.all(12),
      decoration: ShadDecoration(
        color: colors.surface,
        border: ShadBorder.all(
          color: colors.border,
          radius: BorderRadius.circular(12),
        ),
      ),
      popover: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: SingleChildScrollView(
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, _) {
                final count = parseQuickAddFocusEstimate(value.text);
                final formatter = NumberFormat('0.##', l10n.localeName);
                final workSeconds = widget.workSeconds;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.quickAddFocusEstimate,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ShadButton.secondary(
                          width: 48,
                          height: 48,
                          padding: EdgeInsets.zero,
                          enabled: widget.enabled && count != null && count > 1,
                          onPressed: () => _step(-1),
                          child: Semantics(
                            label: l10n.quickAddDecreaseEstimate,
                            child: const Icon(LucideIcons.minus, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            label: l10n.quickAddFocusEstimate,
                            child: ShadInput(
                              controller: _input,
                              autofocus: true,
                              enabled: widget.enabled,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (text) {
                                final next = parseQuickAddFocusEstimate(text);
                                if (widget.enabled && next != null) {
                                  widget.onChanged(next);
                                }
                              },
                              onSubmitted: (_) {
                                if (widget.enabled && count != null) {
                                  widget.onChanged(count);
                                  _popover.hide();
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ShadButton.secondary(
                          width: 48,
                          height: 48,
                          padding: EdgeInsets.zero,
                          enabled:
                              widget.enabled && count != null && count < 999,
                          onPressed: () => _step(1),
                          child: Semantics(
                            label: l10n.quickAddIncreaseEstimate,
                            child: const Icon(LucideIcons.plus, size: 20),
                          ),
                        ),
                      ],
                    ),
                    if (count == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.quickAddEstimateRange,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    if (count != null && workSeconds != null && workSeconds > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          l10n.quickAddEstimateFocusTime(
                            formatter.format(count),
                            formatter.format(workSeconds / 60),
                            formatter.format(count * workSeconds / 60),
                          ),
                          style: TextStyle(color: colors.secondaryText),
                        ),
                      ),
                    if (!widget.manual && widget.estimate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.quickAddEstimateAutomatic,
                          style: TextStyle(color: colors.secondaryText),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: 8),
                    ShadButton.ghost(
                      height: 48,
                      enabled: widget.enabled && widget.manual,
                      foregroundColor: colors.accent,
                      onPressed: () {
                        widget.onChanged(null);
                        _popover.hide();
                      },
                      child: Text(l10n.quickAddClearEstimate),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            label: widget.iconsOnly ? label : null,
            expanded: _popover.isOpen,
            child: ShadButton.outline(
              key: _trigger,
              focusNode: _triggerFocus,
              size: ShadButtonSize.sm,
              height: widget.touchTargets ? 48 : (widget.desktop ? 40 : null),
              width: widget.iconsOnly ? 40 : null,
              padding: widget.iconsOnly ? EdgeInsets.zero : null,
              enabled: widget.enabled,
              onPressed: widget.enabled ? _toggle : null,
              foregroundColor: foreground,
              hoverForegroundColor: foreground,
              pressedForegroundColor: foreground,
              backgroundColor: style.backgroundColor,
              hoverBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              pressedBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              decoration: ShadDecoration(
                border: ShadBorder.all(
                  color: colors.quickAddBorder(
                    foreground,
                    active: _popover.isOpen,
                  ),
                  radius: BorderRadius.circular(8),
                ),
              ),
              leading: Icon(
                LucideIcons.timer,
                size: widget.touchTargets || widget.desktop ? 18 : 14,
              ),
              child: widget.iconsOnly
                  ? null
                  : Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
