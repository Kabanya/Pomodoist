part of 'quick_add_bar.dart';

extension _MobileVoiceRecorder on _VoiceQuickAddHostState {
  Widget _mobileRecorder(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context).textTheme;
    final colors = context.appColors;
    final step = _processingStepIndex;
    final recovery = _recoveryActions(context);
    final message =
        _error ??
        switch (_voice.status) {
          VoiceCaptureStatus.unsupportedPlatform ||
          VoiceCaptureStatus.canceled ||
          VoiceCaptureStatus.error => _statusLabel(context),
          _ => null,
        };
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VoicePanelSwipeArea(
                        child: Row(
                          children: [
                            IconButton(
                              key: const Key('voice-collapse'),
                              tooltip: l10n.voiceCollapse,
                              onPressed: () => _setExpanded(false),
                              icon: const Icon(LucideIcons.chevronDown),
                            ),
                            Expanded(
                              child: Text(
                                l10n.voiceRecorderTitle,
                                textAlign: TextAlign.center,
                                style: theme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.commonClose,
                              onPressed: _closeVoice,
                              icon: const Icon(LucideIcons.x),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        spacing: 6,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Expanded(
                              child: AnimatedContainer(
                                duration: AppMotion.duration(
                                  context,
                                  AppMotion.state,
                                ),
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i <= step
                                      ? colors.accentFill
                                      : colors.border,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.voiceRecorderStep(step + 1),
                        style: theme.labelMedium?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: _recordingControl(context),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_voice.canRetryTranscription &&
                          !_voice.captureActive &&
                          !_voice.isTranscribing)
                        Text(l10n.voiceRecordingSaved),
                      if (message != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            style: theme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (recovery.isNotEmpty)
                        Wrap(spacing: 8, runSpacing: 8, children: recovery),
                      _transcriptionModeRow(context),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.sparkles, size: 20),
                        title: Text(l10n.voiceSmartMode),
                        trailing: _smartModeSwitch(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordingControl(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final recording = _voice.status == VoiceCaptureStatus.recording;
    final processing = _voice.isTranscribing || _voice.analyzing;
    if (processing) {
      return Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _voice.analyzing
                  ? l10n.voiceStatusAnalyzing
                  : l10n.voiceStatusTranscribing,
              style: theme.titleMedium,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: AnimatedBuilder(
              animation: _analysisProgressController,
              builder: (context, _) => LinearProgressIndicator(
                value: _voice.analyzing
                    ? _analysisProgressController.value
                    : MediaQuery.disableAnimationsOf(context)
                    ? 0
                    : null,
              ),
            ),
          ),
          if (_voice.transcript.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_voice.transcript, textAlign: TextAlign.center),
          ],
        ],
      );
    }
    final elapsed = Duration(
      seconds:
          voiceQuickAddMaxDuration.inSeconds - _voice.recordingSecondsRemaining,
    );
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final action = recording
        ? (_voice.captureActive && !_voice.stopping ? _voiceActions.stop : null)
        : (_voice.canStart ? _startVoice : null);
    final pendingPermission =
        _voice.status == VoiceCaptureStatus.requestingPermission;
    return Column(
      children: [
        TextButton(
          key: const Key('voice-recorder-action'),
          onPressed: action,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 138,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(
                        begin: 1,
                        end: recording ? 1.12 : 1,
                      ).animate(_pulseController),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.accentTint,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 120),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accentFill,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: 94,
                        child: Icon(
                          recording ? LucideIcons.square : LucideIcons.mic,
                          size: 36,
                          color: colors.onAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                recording
                    ? l10n.voiceRecorderStop
                    : pendingPermission
                    ? l10n.voiceStatusRequestingPermission
                    : l10n.voiceRecorderTap,
                textAlign: TextAlign.center,
                style: theme.titleLarge,
              ),
            ],
          ),
        ),
        if (recording) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(l10n.voiceRecorderActive),
              Text(
                '${twoDigits(elapsed.inMinutes)}:${twoDigits(elapsed.inSeconds % 60)}',
                style: theme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              _VoiceAmplitudeBars(level: _voice.amplitudeLevel),
            ],
          ),
        ],
        if (_voice.transcript.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_voice.transcript, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}
