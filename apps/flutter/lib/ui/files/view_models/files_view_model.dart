import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';

final filesProvider = StreamProvider.autoDispose
    .family<List<FileAttachment>, FileTarget>(
      (ref, target) =>
          ref.watch(filesRepositoryProvider)?.watch(target) ?? Stream.value([]),
    );
final fileCapabilitiesProvider = FutureProvider.autoDispose
    .family<FileCapabilities?, FileTarget>(
      (ref, target) => ref.watch(filesRepositoryProvider)?.capabilities(target),
      retry: (_, _) => null,
    );
final fileUploadProvider = StreamProvider.autoDispose
    .family<FileUploadState?, FileTarget>(
      (ref, target) =>
          ref.watch(filesRepositoryProvider)?.watchUpload(target) ??
          Stream.value(null),
    );
final filePreviewProvider = AsyncNotifierProvider.autoDispose
    .family<FilePreview, String?, FilePreviewKey>(
      FilePreview.new,
      retry: (_, _) => null,
    );

class FilePreview extends AsyncNotifier<String?> {
  FilePreview(this.key);
  final FilePreviewKey key;
  int _generation = 0;
  bool _retried = false;
  Timer? _retryTimer;

  @override
  Future<String?> build() {
    final repository = ref.watch(filesRepositoryProvider);
    final generation = ++_generation;
    final urls = <String>{};
    _retried = false;
    ref.onDispose(() {
      ++_generation;
      _retryTimer?.cancel();
      for (final url in urls) {
        unawaited(NetworkImage(url).evict());
      }
    });
    Future<String?> load() async {
      try {
        final url = await repository?.downloadUrl(
          key.attachmentId,
          preview: true,
        );
        if (ref.mounted && generation == _generation && url != null) {
          urls.add(url);
        }
        return url;
      } catch (_) {
        if (ref.mounted && generation == _generation) _scheduleRetry();
        rethrow;
      }
    }

    _reload = () async {
      final result = await AsyncValue.guard(load);
      if (ref.mounted && generation == _generation) state = result;
    };
    return load();
  }

  late Future<void> Function() _reload;

  void _scheduleRetry() {
    if (_retried) return;
    _retried = true;
    _retryTimer = Timer(const Duration(seconds: 1), () {
      if (!ref.mounted) return;
      state = const AsyncLoading();
      unawaited(_reload());
    });
  }

  void imageFailed(String url, Object error, StackTrace? stack) {
    if (!ref.mounted ||
        state.isLoading ||
        state.hasError ||
        state.value != url) {
      return;
    }
    unawaited(NetworkImage(url).evict());
    state = AsyncError(error, stack ?? StackTrace.current);
    _scheduleRetry();
  }
}

final filesSignedInProvider = Provider<bool>(
  (ref) => ref.watch(filesRepositoryProvider) != null,
);

enum FileTypeFilter { all, images, documents, other }

class FileGroup {
  const FileGroup(this.taskId, this.name, this.files);
  final String? taskId, name;
  final List<FileAttachment> files;
}

List<FileGroup> projectFileGroups(
  List<FileAttachment> files, {
  String search = '',
  FileTypeFilter type = FileTypeFilter.all,
  bool byTask = false,
}) {
  final needle = search.trim().toLowerCase();
  final filtered =
      files
          .where(
            (file) =>
                (needle.isEmpty ||
                    file.name.toLowerCase().contains(needle) ||
                    (file.taskName?.toLowerCase().contains(needle) ?? false)) &&
                switch (type) {
                  FileTypeFilter.all => true,
                  FileTypeFilter.images => file.isImage,
                  FileTypeFilter.documents => file.isDocument,
                  FileTypeFilter.other => !file.isImage && !file.isDocument,
                },
          )
          .toList()
        ..sort((a, b) {
          final order = b.createdAt.compareTo(a.createdAt);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  if (!byTask) return [FileGroup(null, null, filtered)];
  final groups = <String?, List<FileAttachment>>{};
  for (final file in filtered) {
    (groups[file.taskId] ??= []).add(file);
  }
  final result = groups.entries
      .map(
        (entry) =>
            FileGroup(entry.key, entry.value.first.taskName, entry.value),
      )
      .toList();
  result.sort(
    (a, b) => a.taskId == null
        ? -1
        : b.taskId == null
        ? 1
        : b.files.first.createdAt.compareTo(a.files.first.createdAt),
  );
  return result;
}

typedef FileViewState = ({bool gallery, bool byTask});
final filesViewModelProvider = NotifierProvider.autoDispose
    .family<FilesViewModel, FileViewState, FileTarget>(FilesViewModel.new);

class FilesViewModel extends Notifier<FileViewState> {
  FilesViewModel(this.target);
  final FileTarget target;
  bool _edited = false;
  Future<void> _pendingSave = Future.value();
  @override
  FileViewState build() {
    if (target.projectId != null) unawaited(_load());
    return (gallery: false, byTask: false);
  }

  Future<void> _load() async {
    try {
      final value = await ref
          .read(fileViewPreferencesRepositoryProvider)
          .load(target.projectId!);
      if (ref.mounted && !_edited) state = value;
    } catch (_) {
      /* Optional local preferences retain the default layout. */
    }
  }

  Future<void> setView({bool? gallery, bool? byTask}) async {
    _edited = true;
    final value = (
      gallery: gallery ?? state.gallery,
      byTask: byTask ?? state.byTask,
    );
    state = value;
    if (target.projectId != null) {
      final preferences = ref.read(fileViewPreferencesRepositoryProvider);
      final save = _pendingSave.then(
        (_) => preferences.save(
          target.projectId!,
          gallery: value.gallery,
          byTask: value.byTask,
        ),
      );
      _pendingSave = save.catchError((Object _) {});
      await save;
    }
  }

  Future<void> upload() async {
    final repository = ref.read(filesRepositoryProvider);
    if (repository == null) throw const FileFailure('session_changed');
    try {
      await repository.pickAndUpload(target);
    } finally {
      if (ref.mounted) ref.invalidate(fileCapabilitiesProvider(target));
    }
  }

  Future<void> retryUpload() async {
    final repository = ref.read(filesRepositoryProvider);
    if (repository == null) throw const FileFailure('session_changed');
    try {
      await repository.retry(target);
    } finally {
      if (ref.mounted) ref.invalidate(fileCapabilitiesProvider(target));
    }
  }

  Future<void> delete(FileAttachment file) async {
    final repository = ref.read(filesRepositoryProvider);
    if (repository == null) throw const FileFailure('session_changed');
    await repository.delete(file);
    if (ref.mounted) ref.invalidate(fileCapabilitiesProvider(target));
  }

  Future<void> download(FileAttachment file) async {
    final repository = ref.read(filesRepositoryProvider);
    if (repository == null) throw const FileFailure('session_changed');
    await repository.download(file);
  }

  void refresh() {
    for (final file
        in ref.read(filesProvider(target)).value ?? <FileAttachment>[]) {
      ref.invalidate(filePreviewProvider(file.previewKey));
    }
    ref.invalidate(fileCapabilitiesProvider(target));
    ref.invalidate(filesProvider(target));
  }
}
