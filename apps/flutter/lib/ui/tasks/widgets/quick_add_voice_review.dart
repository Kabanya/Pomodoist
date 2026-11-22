part of 'quick_add_bar.dart';

extension _MobileVoiceReview on _VoiceQuickAddHostState {
  Widget _mobileReview(BuildContext context) {
    final l10n = context.l10n;
    final accepted = _taskCount(_acceptedTasks);
    final formatter = AppDateFormatter.of(context);
    final date = formatter.format(
      _reviewDate,
      automatic: () => DateFormat.yMMMMd(l10n.localeName).format(_reviewDate),
    );
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const PageStorageKey('voice-mobile-review'),
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  children: [
                    VoicePanelSwipeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.voiceReviewTitle,
                                    style: theme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const Key('voice-collapse'),
                                  tooltip: l10n.voiceCollapse,
                                  onPressed: () => _setExpanded(false),
                                  icon: const Icon(
                                    LucideIcons.chevronDown,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.commonClose,
                                  onPressed: _voice.saving ? null : _closeVoice,
                                  icon: const Icon(LucideIcons.x, size: 20),
                                ),
                              ],
                            ),
                            Text(
                              l10n.voiceReviewCount(accepted),
                              style: theme.bodyLarge?.copyWith(
                                color: colors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.calendar,
                                  size: 18,
                                  color: colors.secondaryText,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(date)),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    for (final (index, controller) in _draftControllers.indexed)
                      _TaskDraftItem(
                        key: ObjectKey(controller),
                        controller: controller,
                        depth: 0,
                        index: index,
                        reviewNumber: (index + 1).toString().padLeft(2, '0'),
                        opened: _openReviewDraft,
                        onToggle: (draft) => _setSheetState(
                          () => _openReviewDraft =
                              identical(draft, _openReviewDraft) ? null : draft,
                        ),
                        defaultDate: widget.defaultDate,
                        projectId: widget.projectId,
                        priority: widget.defaultPriority,
                        enabled: !_voice.saving,
                        onChanged: () => _setSheetState(() {}),
                        onRemove: () => _removeTask(index),
                      ),
                    if (_voice.canRetryTranscription)
                      TextButton.icon(
                        key: const Key('voice-retry-transcription'),
                        onPressed: _voice.canStart
                            ? () => _voiceActions.start(retry: true)
                            : null,
                        icon: const Icon(LucideIcons.rotateCw),
                        label: Text(l10n.voiceRetryTranscription),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 4,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: colors.surfaceTint,
                        minimumSize: Size(
                          (MediaQuery.sizeOf(context).width - 32) * .33,
                          44,
                        ),
                      ),
                      onPressed: _voice.canRecord ? _startVoice : null,
                      icon: const Icon(LucideIcons.mic, size: 19),
                      label: Text(l10n.voiceAgain),
                    ),
                    FilledButton.icon(
                      key: const Key('voice-add-all'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size(
                          ((MediaQuery.sizeOf(context).width - 32) * .67)
                              .floorToDouble(),
                          44,
                        ),
                      ),
                      onPressed: _voice.saving || accepted == 0 ? null : _save,
                      icon: const Icon(LucideIcons.check, size: 19),
                      label: Text(l10n.voiceReviewAdd(accepted)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
