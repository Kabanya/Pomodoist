part of 'quick_add_bar.dart';

extension _VoiceQuickAddHostPanel on _VoiceQuickAddHostState {
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
    final acceptedTaskCount = _taskCount(_acceptedTasks);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: _voiceSheetBorderRadius,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(380, MediaQuery.sizeOf(context).height * .86),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panelHeader(context),
              const SizedBox(height: 14),
              _voiceSmartModeRow(context),
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
                Text(context.l10n.voiceRecordingSaved),
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
              _panelActions(context, acceptedTaskCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelHeader(BuildContext context) {
    final l10n = context.l10n;
    return VoicePanelSwipeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _VoicePulse(
            animation: _pulseController,
            active:
                _voice.motionActive && !MediaQuery.disableAnimationsOf(context),
            listeningLevel: _voice.status == VoiceRecognitionStatus.recording
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
    );
  }

  Widget _voiceSmartModeRow(BuildContext context) {
    final l10n = context.l10n;
    return Row(
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
    );
  }

  Widget _panelActions(BuildContext context, int acceptedTaskCount) {
    final l10n = context.l10n;
    return Wrap(
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
              _voice.captureActive && _voice.isCapturing && !_voice.stopping
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
            onPressed: _voice.canStart ? () => _voice.start(retry: true) : null,
            icon: const Icon(LucideIcons.rotateCw),
            label: Text(l10n.voiceRetryTranscription),
          ),
        ],
        if (_voice.needsPermissionRequest || _voice.settingsDestination != null)
          OutlinedButton.icon(
            key: const Key('voice-recover-access'),
            onPressed: _voice.canStart ? _voice.recoverAccess : null,
            icon: const Icon(LucideIcons.settings2),
            label: Text(_recoveryLabel),
          ),
        if (_voice.canUseCloudFallback)
          OutlinedButton.icon(
            key: const Key('voice-use-cloud-transcription'),
            onPressed: _voice.canStart ? _voice.useCloudTranscription : null,
            icon: const Icon(LucideIcons.cloud),
            label: Text(l10n.voiceUseCloudTranscription),
          ),
        if (_error != null &&
            _voice.transcript.trim().isNotEmpty &&
            !_voice.captureActive &&
            !_voice.isTranscribing &&
            !_voice.analyzing)
          TextButton.icon(
            onPressed: () => _voice.decomposeTranscript(_voice.transcript),
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
}
