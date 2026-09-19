import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';

final quickAddViewModelProvider = NotifierProvider.autoDispose
    .family<QuickAddViewModel, AsyncValue<String?>, Object>(
      QuickAddViewModel.new,
    );

class QuickAddViewModel extends Notifier<AsyncValue<String?>> {
  QuickAddViewModel(this.identity);
  final Object identity;
  @override
  AsyncValue<String?> build() => const AsyncData(null);
  Future<String?> submit(
    String input, {
    int? priority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    if (state.isLoading || input.trim().isEmpty) return null;
    state = const AsyncLoading();
    final service = ref.read(quickAddServiceProvider);
    final result = await AsyncValue.guard(
      () async => (await service.createTask(
        input.trim(),
        priority: priority,
        defaultDate: defaultDate,
        projectId: projectId,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      )).getOrThrow(),
    );
    if (ref.mounted) state = result;
    return result.value;
  }
}

typedef QuickAddInputState = ({
  List<ProjectItem> projects,
  List<LabelItem> labels,
  String? hint,
});
final quickAddInputViewModelProvider =
    NotifierProvider.autoDispose<QuickAddInputViewModel, QuickAddInputState>(
      QuickAddInputViewModel.new,
    );

class QuickAddInputViewModel extends Notifier<QuickAddInputState> {
  @override
  QuickAddInputState build() => (
    projects: List.unmodifiable(
      ref.watch(projectsProvider).value ?? const <ProjectItem>[],
    ),
    labels: List.unmodifiable(
      ref.watch(labelsProvider).value ?? const <LabelItem>[],
    ),
    hint: ref.watch(quickAddHintTextProvider),
  );
  Iterable<QuickAddSuggestion> suggestions(TextEditingValue value) {
    final token = ActiveQuickAddToken.from(value);
    if (token == null) return const [];
    final query = token.query.toLowerCase();
    final names = isQuickAddProjectMarker(token.marker)
        ? state.projects
              .where((p) => p.id != inboxProjectId && !p.isArchived)
              .map((p) => p.name)
        : state.labels.map((l) => l.name);
    return names
        .where((name) => name.toLowerCase().startsWith(query))
        .take(6)
        .map((name) => QuickAddSuggestion(token.marker, name));
  }
}

class ActiveQuickAddToken {
  const ActiveQuickAddToken({
    required this.marker,
    required this.query,
    required this.start,
    required this.end,
  });

  final String marker;
  final String query;
  final int start;
  final int end;

  static ActiveQuickAddToken? from(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = value.text;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      return null;
    }
    var start = cursor;
    while (start > 0 && text[start - 1].trim().isNotEmpty) {
      start--;
    }
    var end = cursor;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    final beforeCursor = text.substring(start, cursor);
    if (beforeCursor.isEmpty) {
      return null;
    }
    final marker = beforeCursor[0];
    if (!isQuickAddProjectMarker(marker) && marker != '@') {
      return null;
    }
    final query = beforeCursor.length > 1 && beforeCursor[1] == '"'
        ? beforeCursor.substring(2)
        : beforeCursor.substring(1);
    return ActiveQuickAddToken(
      marker: marker,
      query: query,
      start: start,
      end: end,
    );
  }
}

class QuickAddSuggestion {
  const QuickAddSuggestion(this.marker, this.name);

  final String marker;
  final String name;
}

String quickAddTokenValue(String name) {
  return RegExp(r'[\s"\\]').hasMatch(name)
      ? quickAddQuotedMetadataValue(name)
      : name;
}
