import 'file_error_message.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'dart:async';
import 'package:pomodoist/ui/files/widgets/file_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/files/view_models/files_view_model.dart';

class FilesPanel extends ConsumerStatefulWidget {
  const FilesPanel({
    this.projectId,
    this.taskId,
    this.compact = false,
    super.key,
  }) : assert((projectId == null) != (taskId == null));
  final String? projectId, taskId;
  final bool compact;
  @override
  ConsumerState<FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends ConsumerState<FilesPanel> {
  String _search = '';
  FileTypeFilter _type = FileTypeFilter.all;
  FileTarget get _target =>
      FileTarget(projectId: widget.projectId, taskId: widget.taskId);
  FilesViewModel get _model =>
      ref.read(filesViewModelProvider(_target).notifier);
  String _error(Object? error) => fileErrorMessage(context.l10n, error);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showActionFeedback(
          context,
          message: _error(error),
          icon: LucideIcons.circleAlert,
          sound: ActionFeedbackSound.none,
        );
      }
    }
  }

  Future<void> _delete(FileAttachment file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(context.l10n.filesDelete),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text('${context.l10n.filesDeleteConfirm}\n${file.name}'),
      ),
    );
    if (confirmed == true && mounted) await _run(() => _model.delete(file));
  }

  Future<void> _open(FileAttachment file) async {
    if (!file.isImage) {
      await _run(() => _model.download(file));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonClose),
          ),
          ShadButton(
            onPressed: () => unawaited(_run(() => _model.download(file))),
            child: Text(context.l10n.filesDownload),
          ),
        ],
        child: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(context).height * .6,
          child: _FileImage(file: file, fit: BoxFit.contain),
        ),
      ),
    );
  }

  String _typeLabel(FileTypeFilter type) => switch (type) {
    FileTypeFilter.all => context.l10n.filesAllTypes,
    FileTypeFilter.images => context.l10n.filesImages,
    FileTypeFilter.documents => context.l10n.filesDocuments,
    FileTypeFilter.other => context.l10n.filesOther,
  };
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final target = _target;
    final files = ref.watch(filesProvider(target));
    final capabilities = ref.watch(fileCapabilitiesProvider(target));
    final transfer = ref.watch(fileUploadProvider(target)).value;
    final view = ref.watch(filesViewModelProvider(target));
    final signedIn = ref.watch(filesSignedInProvider);
    final groups = projectFileGroups(
      files.value ?? [],
      search: _search,
      type: _type,
      byTask: view.byTask && widget.projectId != null,
    );
    final reason = capabilities.value?.reason;
    final toolbar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controls(
          view,
          capabilities.value?.canUpload == true &&
              (transfer == null || transfer.error != null),
        ),
        if (!signedIn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.filesSignIn),
          ),
        if (signedIn && (reason != null || capabilities.hasError))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error(
                      reason == null ? capabilities.error : FileFailure(reason),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _model.refresh,
                  tooltip: l10n.filesRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                ),
              ],
            ),
          ),
        if (transfer != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${transfer.finishing ? l10n.filesFinish : l10n.filesUpload}: ${transfer.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: transfer.progress),
                if (transfer.error != null)
                  Row(
                    children: [
                      Expanded(child: Text(_error(transfer.error))),
                      TextButton(
                        onPressed: () => unawaited(_run(_model.retryUpload)),
                        child: Text(l10n.filesRetry),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
    Widget content;
    if (files.isLoading) {
      content = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (files.hasError) {
      content = Row(
        children: [
          Expanded(child: Text(l10n.filesLoadError)),
          TextButton(onPressed: _model.refresh, child: Text(l10n.filesRetry)),
        ],
      );
    } else if (groups.every((group) => group.files.isEmpty)) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.filesEmpty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups) ...[
            if (view.byTask && widget.projectId != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  group.taskId == null
                      ? l10n.filesProjectGroup
                      : group.name ?? l10n.filesByTask,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            if (widget.compact)
              _taskFiles(group.files, capabilities.value?.canDelete == true)
            else if (view.gallery)
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final file in group.files)
                      SizedBox(
                        width: constraints.maxWidth < 220
                            ? constraints.maxWidth
                            : 220,
                        child: _card(
                          file,
                          capabilities.value?.canDelete == true,
                        ),
                      ),
                  ],
                ),
              )
            else
              for (final file in group.files)
                _row(file, capabilities.value?.canDelete == true),
          ],
        ],
      );
    }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [toolbar, content],
    );
    return widget.compact
        ? body
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: body,
          );
  }

  Widget _controls(FileViewState view, bool canAdd) {
    final l10n = context.l10n;
    final add = ShadButton(
      height: 44,
      onPressed: canAdd ? () => unawaited(_run(_model.upload)) : null,
      leading: const Icon(LucideIcons.plus, size: 16),
      child: Text(l10n.filesAdd),
    );
    if (widget.compact) {
      return Wrap(
        spacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.filesTitle, style: Theme.of(context).textTheme.titleSmall),
          TextButton.icon(
            onPressed: canAdd ? () => unawaited(_run(_model.upload)) : null,
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.primaryText,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text(l10n.filesAdd),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final search = ShadInput(
          leading: const Icon(LucideIcons.search, size: 16),
          placeholder: Text(l10n.filesSearch),
          onChanged: (value) => setState(() => _search = value),
        );
        final grouping = ShadSelect<bool>(
          initialValue: view.byTask,
          key: ValueKey(view.byTask),
          onChanged: (value) {
            if (value != null) {
              unawaited(_run(() => _model.setView(byTask: value)));
            }
          },
          selectedOptionBuilder: (context, value) => Text(
            '${l10n.filesGrouping}: ${value ? l10n.filesByTask : l10n.filesAllTogether}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          options: [
            ShadOption(value: false, child: Text(l10n.filesAllTogether)),
            ShadOption(value: true, child: Text(l10n.filesByTask)),
          ],
        );
        final modes = SizedBox(
          width: (260 * scale).clamp(0, constraints.maxWidth),
          child: ShadTabs<bool>(
            scrollable: true,
            value: view.gallery,
            onChanged: (value) =>
                unawaited(_run(() => _model.setView(gallery: value))),
            tabs: [
              ShadTab(
                value: false,
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.list, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.filesList),
                  ],
                ),
              ),
              ShadTab(
                value: true,
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.layoutGrid, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.filesGallery),
                  ],
                ),
              ),
            ],
          ),
        );
        final filter = ShadSelect<FileTypeFilter>(
          initialValue: _type,
          onChanged: (value) {
            if (value != null) setState(() => _type = value);
          },
          selectedOptionBuilder: (context, value) => Text(_typeLabel(value)),
          options: [
            for (final type in FileTypeFilter.values)
              ShadOption(value: type, child: Text(_typeLabel(type))),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxWidth >= 1000 * scale)
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  grouping,
                  const SizedBox(width: 8),
                  modes,
                ],
              )
            else ...[
              search,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [grouping, modes],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [filter, add],
            ),
          ],
        );
      },
    );
  }

  Widget _taskFiles(
    List<FileAttachment> files,
    bool canDelete,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final images = files.where((file) => file.isImage);
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 300 * scale ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (final file in images)
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          button: true,
                          label: '${context.l10n.filesPreview}: ${file.name}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => unawaited(_open(file)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 112,
                                child: _FileImage(file: file),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            _taskFileMenu(file, canDelete),
                          ],
                        ),
                        _metadata(file),
                      ],
                    ),
                  ),
              ],
            ),
          for (final file in files.where((file) => !file.isImage))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    fileIcon(file.name, file.contentType),
                    size: 24,
                    color: context.appColors.secondaryText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: context.appColors.primaryText,
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: () => unawaited(_open(file)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          _metadata(file),
                        ],
                      ),
                    ),
                  ),
                  _taskFileMenu(file, canDelete),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _taskFileMenu(FileAttachment file, bool canDelete) => AppActionMenu(
    width: 44,
    tooltip: context.l10n.taskMore,
    items: [
      ShadContextMenuItem(
        leading: const Icon(LucideIcons.download, size: 16),
        onPressed: () => unawaited(_run(() => _model.download(file))),
        child: Text(context.l10n.filesDownload),
      ),
      if (canDelete)
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.trash2, size: 16),
          onPressed: () => unawaited(_delete(file)),
          child: Text(context.l10n.filesDelete),
        ),
    ],
    child: const Icon(LucideIcons.ellipsis, size: 16),
  );

  Widget _metadata(FileAttachment file) => Text(
    [
      if (file.taskName != null && widget.projectId != null) file.taskName!,
      file.authorName,
      file.bytes < 1000000
          ? '${(file.bytes / 1000).toStringAsFixed(0)} KB'
          : '${(file.bytes / 1000000).toStringAsFixed(1)} MB',
      DateFormat.yMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).add_jm().format(file.createdAt.toLocal()),
    ].where((value) => value.isNotEmpty).join(' · '),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.appColors.secondaryText),
  );
  Widget _actions(FileAttachment file, bool canDelete) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: () => unawaited(_run(() => _model.download(file))),
        tooltip: context.l10n.filesDownload,
        icon: const Icon(LucideIcons.download, size: 16),
      ),
      if (canDelete)
        IconButton(
          onPressed: () => unawaited(_delete(file)),
          tooltip: context.l10n.filesDelete,
          icon: const Icon(LucideIcons.trash2, size: 16),
        ),
    ],
  );
  Widget _row(FileAttachment file, bool canDelete) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: file.isImage
              ? _FileImage(file: file)
              : Icon(fileIcon(file.name, file.contentType), size: 24),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            onPressed: () => unawaited(_open(file)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                _metadata(file),
              ],
            ),
          ),
        ),
        _actions(file, canDelete),
      ],
    ),
  );
  Widget _card(FileAttachment file, bool canDelete) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            onPressed: () => unawaited(_open(file)),
            child: Column(
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: file.isImage
                      ? _FileImage(file: file)
                      : Icon(fileIcon(file.name, file.contentType), size: 40),
                ),
                const SizedBox(height: 8),
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _metadata(file),
          Align(
            alignment: Alignment.centerRight,
            child: _actions(file, canDelete),
          ),
        ],
      ),
    ),
  );
}

class _FileImage extends ConsumerWidget {
  const _FileImage({required this.file, this.fit = BoxFit.cover});
  final FileAttachment file;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = filePreviewProvider(file.previewKey);
    final preview = ref.watch(provider);
    final url = preview.isLoading || preview.hasError ? null : preview.value;
    if (url == null) {
      return Icon(
        preview.hasError ? LucideIcons.imageOff : LucideIcons.image,
        size: 24,
        semanticLabel: context.l10n.filesPreview,
      );
    }
    final controller = ref.read(provider.notifier);
    return Image.network(
      url,
      fit: fit,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) {
        // Image errors arrive during build; update provider state afterwards.
        scheduleMicrotask(() => controller.imageFailed(url, error, stack));
        return const Icon(LucideIcons.imageOff, size: 24);
      },
    );
  }
}
