import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/voice/view_models/whisper_model_view_model.dart';

class WhisperModelStatus extends ConsumerWidget {
  const WhisperModelStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(whisperModelSettingsProvider).choice.model;
    final ready = ref.watch(whisperReadyProvider(model));
    return Text(
      ready.isLoading
          ? model.label
          : '${model.label} · ${ready.value == true ? context.l10n.whisperReady : context.l10n.whisperNeedsDownload}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class WhisperDownloadDialog extends ConsumerStatefulWidget {
  const WhisperDownloadDialog({required this.model, super.key});
  final WhisperModel model;
  @override
  ConsumerState<WhisperDownloadDialog> createState() => _DownloadState();
}

class _DownloadState extends ConsumerState<WhisperDownloadDialog> {
  bool busy = false;
  bool failed = false;
  int percent = 0;

  Future<void> download() async {
    if (busy) return;
    setState(() {
      busy = true;
      percent = 0;
      failed = false;
    });
    try {
      await ref.read(whisperModelActionsProvider).download(widget.model, (
        value,
      ) {
        final next = (100 * value).floor();
        if (mounted && next != percent) setState(() => percent = next);
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final model = widget.model;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(l10n.whisperDownloadTitle(model.label)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed
                  ? l10n.voiceModelDownloadFailed
                  : l10n.whisperDownloadBody(model.megabytes),
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: percent / 100,
                semanticsLabel: model.label,
              ),
              Text('$percent%'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.whisperNotNow),
          ),
          FilledButton(
            onPressed: busy ? null : download,
            child: Text(
              failed
                  ? l10n.commonRetry
                  : l10n.whisperDownloadButton(model.megabytes),
            ),
          ),
        ],
      ),
    );
  }
}
