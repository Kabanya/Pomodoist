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
  final _numberFocus = FocusNode();
  bool _expanded = false;
  bool _editing = false;

  bool get _inline => !widget.desktop && MediaQuery.sizeOf(context).width < 820;
  int get _count =>
      parseQuickAddFocusEstimate(_input.text) ?? widget.estimate ?? 1;

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
    _numberFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    final opening = _inline ? !_expanded : !_popover.isOpen;
    if (opening) {
      _input.text = '${(widget.estimate ?? 1).clamp(1, 999)}';
      _editing = false;
    }
    if (_inline) {
      FocusScope.of(context).unfocus();
      setState(() => _expanded = opening);
    } else {
      _popover.toggle();
    }
  }

  void _select(int count) {
    if (!widget.enabled ||
        (count == _count && widget.manual && widget.estimate == count)) {
      return;
    }
    _input.text = '$count';
    widget.onChanged(count);
    setState(() {});
  }

  void _applyNumber() {
    final count = parseQuickAddFocusEstimate(_input.text);
    if (!widget.enabled || count == null) return;
    widget.onChanged(count);
    _numberFocus.unfocus();
    setState(() => _editing = false);
  }

  Widget _editor(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final count = parseQuickAddFocusEstimate(value.text);
        final formatter = NumberFormat('0.##', l10n.localeName);
        final workSeconds = widget.workSeconds;
        final scale = MediaQuery.textScalerOf(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(color: colors.border, height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.quickAddFocusEstimate,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ShadButton.ghost(
                  height: 48,
                  enabled: widget.enabled && widget.manual,
                  foregroundColor: colors.accent,
                  onPressed: () {
                    _numberFocus.unfocus();
                    widget.onChanged(null);
                    if (_inline) {
                      setState(() {
                        _editing = false;
                        _input.text = '${widget.estimate ?? 1}';
                      });
                    } else {
                      _popover.hide();
                    }
                  },
                  child: Text(l10n.quickAddClearEstimate),
                ),
              ],
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              Semantics(
                label: l10n.quickAddFocusEstimate,
                child: ShadInput(
                  placeholder: Text(l10n.quickAddFocusEstimate),
                  controller: _input,
                  focusNode: _numberFocus,
                  autofocus: true,
                  enabled: widget.enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _applyNumber(),
                ),
              ),
              if (count == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.quickAddEstimateRange,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ShadButton.ghost(
                height: 48,
                enabled: widget.enabled && count != null,
                onPressed: _applyNumber,
                child: Text(l10n.commonDone),
              ),
            ] else
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.quickAddDecreaseEstimate,
                    onPressed: widget.enabled && _count > 1
                        ? () => _select(_count - 1)
                        : null,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronRight
                          : LucideIcons.chevronLeft,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      enabled: widget.enabled,
                      slider: true,
                      label: l10n.quickAddFocusEstimate,
                      value: '$_count',
                      increasedValue: _count < 999 ? '${_count + 1}' : null,
                      decreasedValue: _count > 1 ? '${_count - 1}' : null,
                      onIncrease: widget.enabled && _count < 999
                          ? () => _select(_count + 1)
                          : null,
                      onDecrease: widget.enabled && _count > 1
                          ? () => _select(_count - 1)
                          : null,
                      child: ExcludeSemantics(
                        child: SizedBox(
                          height: scale.scale(54) + 12,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Leave room for three-digit counts and scaled text.
                              final fraction = math.min(
                                1.0,
                                math.max(
                                  .2,
                                  scale.scale(
                                        math.max(
                                          48,
                                          24.0 * _count.toString().length + 16,
                                        ),
                                      ) /
                                      constraints.maxWidth,
                                ),
                              );
                              return _EstimatePages(
                                key: ValueKey(fraction),
                                count: _count,
                                enabled: widget.enabled,
                                fraction: fraction,
                                onChanged: _select,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.quickAddIncreaseEstimate,
                    onPressed: widget.enabled && _count < 999
                        ? () => _select(_count + 1)
                        : null,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronLeft
                          : LucideIcons.chevronRight,
                      size: 20,
                    ),
                  ),
                ],
              ),
            if (count != null && workSeconds != null && workSeconds > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${l10n.quickAddEstimatedPomodoros(count)} · ${l10n.quickAddEstimateTotalTime(formatter.format(count * workSeconds / 60))}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.quickAddEstimateInterval(
                  formatter.format(workSeconds / 60),
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.secondaryText),
              ),
            ],
            if (!widget.manual && widget.estimate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.quickAddEstimateAutomatic,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.secondaryText),
                ),
              ),
            if (!_editing)
              ShadButton.ghost(
                height: 48,
                enabled: widget.enabled,
                foregroundColor: colors.accent,
                onPressed: () {
                  _input.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _input.text.length,
                  );
                  setState(() => _editing = true);
                },
                child: Text(l10n.quickAddEnterEstimate),
              ),
            Divider(color: colors.border, height: 24),
          ],
        );
      },
    );
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
    if (_inline && _expanded) return _editor(context);
    final trigger = _buildTrigger(context, label, foreground, style);
    if (_inline) {
      return Align(alignment: AlignmentDirectional.centerStart, child: trigger);
    }
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
            child: _editor(context),
          ),
        ),
      ),
      child: trigger,
    );
  }

  Widget _buildTrigger(
    BuildContext context,
    String label,
    Color foreground,
    TextStyle style,
  ) {
    final colors = context.appColors;
    return Tooltip(
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
            height: widget.touchTargets ? 48 : 40,
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
    );
  }
}

class _EstimatePages extends StatefulWidget {
  const _EstimatePages({
    super.key,
    required this.count,
    required this.enabled,
    required this.fraction,
    required this.onChanged,
  });

  final int count;
  final bool enabled;
  final double fraction;
  final ValueChanged<int> onChanged;

  @override
  State<_EstimatePages> createState() => _EstimatePagesState();
}

class _EstimatePagesState extends State<_EstimatePages> {
  late final _controller = PageController(
    initialPage: widget.count - 1,
    viewportFraction: widget.fraction,
    keepPage: false,
  );

  @override
  void didUpdateWidget(_EstimatePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count &&
        _controller.hasClients &&
        _controller.page?.round() != widget.count - 1) {
      _controller.jumpToPage(widget.count - 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final formatter = NumberFormat('0', context.l10n.localeName);
    return PageView.builder(
      controller: _controller,
      physics: widget.enabled ? null : const NeverScrollableScrollPhysics(),
      itemCount: 999,
      onPageChanged: (index) {
        if (widget.enabled) widget.onChanged(index + 1);
      },
      itemBuilder: (context, index) {
        final number = index + 1;
        final selected = number == widget.count;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () => widget.onChanged(number) : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatter.format(number),
                  maxLines: 1,
                  style: AppTheme.monoTextStyle.copyWith(
                    fontSize: selected ? 36 : 28,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? colors.accent : colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? colors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
