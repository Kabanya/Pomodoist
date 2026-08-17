import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../tasks/data/csv_task_import.dart';

bool isCsvTaskImportSupported({bool? web, TargetPlatform? platform}) =>
    (web ?? kIsWeb) ||
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.windows => true,
      _ => false,
    };

class CsvTaskImportCard extends ConsumerStatefulWidget {
  const CsvTaskImportCard({this.pickFile, super.key});

  final Future<XFile?> Function()? pickFile;

  @override
  ConsumerState<CsvTaskImportCard> createState() => _CsvTaskImportCardState();
}

class _CsvTaskImportCardState extends ConsumerState<CsvTaskImportCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      key: const Key('csv-import-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.csvImportTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(l10n.csvImportSubtitle),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('csv-import-select-file'),
                  onPressed: _busy ? null : _selectFile,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(l10n.csvImportSelectFile),
                ),
                OutlinedButton.icon(
                  key: const Key('csv-import-human-guide'),
                  onPressed: () => _showGuide(
                    l10n.csvImportHumanGuideTitle,
                    l10n.csvImportHumanGuide,
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(l10n.csvImportHumanGuideButton),
                ),
                OutlinedButton.icon(
                  key: const Key('csv-import-agent-guide'),
                  onPressed: () => _showGuide(
                    l10n.csvImportAgentGuideTitle,
                    pomodoistCsvAgentInstructions,
                  ),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: Text(l10n.csvImportAgentGuideButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFile() async {
    setState(() => _busy = true);
    try {
      final file = await (widget.pickFile ?? _openCsvFile)();
      if (file == null || !mounted) return;
      final importer = ref.read(csvTaskImporterProvider);
      final preview = await importer.prepare(await file.readAsBytes());
      if (!mounted) return;
      final confirmed = await _showPreview(preview);
      if (!confirmed || !mounted) return;
      final result = await importer.commit(preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.csvImportSuccess}: ${result.taskIds.length}',
          ),
        ),
      );
    } on CsvTaskImportException catch (error) {
      if (mounted) await _showError(_formatIssues(error));
    } on Object catch (error) {
      if (mounted) {
        await _showError('${context.l10n.csvImportUnexpectedError}\n$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showPreview(CsvTaskImportPreview preview) async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('csv-import-preview-dialog'),
            title: Text(l10n.csvImportPreviewTitle),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${l10n.csvImportPreviewTasks}: ${preview.taskCount}'),
                  Text(
                    '${l10n.csvImportPreviewSubtasks}: ${preview.subtaskCount}',
                  ),
                  const SizedBox(height: 12),
                  _PreviewNames(
                    label: l10n.csvImportPreviewNewProjects,
                    values: preview.newProjects,
                    empty: l10n.csvImportNone,
                  ),
                  _PreviewNames(
                    label: l10n.csvImportPreviewNewLabels,
                    values: preview.newLabels,
                    empty: l10n.csvImportNone,
                  ),
                  _PreviewNames(
                    label: l10n.csvImportPreviewNewStatuses,
                    values: preview.newKanbanStatuses,
                    empty: l10n.csvImportNone,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.csvImportDuplicateWarning)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('csv-import-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.csvImportConfirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showGuide(String title, String text) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('csv-import-guide-dialog'),
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.csvImportCopied)));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(l10n.csvImportCopy),
          ),
          FilledButton(
            key: const Key('csv-import-guide-close'),
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Future<void> _showError(String message) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.csvImportErrorTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 420),
          child: SingleChildScrollView(child: SelectableText(message)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }
}

class _PreviewNames extends StatelessWidget {
  const _PreviewNames({
    required this.label,
    required this.values,
    required this.empty,
  });

  final String label;
  final List<String> values;
  final String empty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$label: ${values.isEmpty ? empty : values.join(', ')}'),
  );
}

Future<XFile?> _openCsvFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      mimeTypes: ['text/csv', 'application/csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
    ),
  ],
);

String _formatIssues(CsvTaskImportException error) => error.issues
    .map(
      (issue) =>
          issue.row > 0 ? 'Row ${issue.row}: ${issue.message}' : issue.message,
    )
    .join('\n');
