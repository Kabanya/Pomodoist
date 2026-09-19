import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'quick_add_metadata_edit.dart';

typedef QuickAddDetailsState = ({
  List<ProjectItem> projects,
  List<ProjectItem> allProjects,
  DateTime day,
});
final quickAddDetailsViewModelProvider =
    NotifierProvider.autoDispose<
      QuickAddDetailsViewModel,
      QuickAddDetailsState
    >(QuickAddDetailsViewModel.new);

class QuickAddDetailsViewModel extends Notifier<QuickAddDetailsState> {
  late QuickAddParser _parser;
  @override
  QuickAddDetailsState build() {
    _parser = ref.watch(quickAddParserProvider);
    final clock = ref.watch(clockProvider);
    final day = ref.watch(
      focusTickerProvider.select((tick) {
        final date = (tick.value ?? clock.now()).toLocal();
        return DateTime(date.year, date.month, date.day);
      }),
    );
    final projects =
        (ref.watch(projectsProvider).value ?? const <ProjectItem>[])
            .where((p) => !p.isDeleted)
            .toList();
    return (
      allProjects: List.unmodifiable(projects),
      projects: List.unmodifiable(projects.where((p) => !p.isArchived)),
      day: day,
    );
  }

  DateTime now() => ref.read(clockProvider).now();
  Duration get defaultTimedBlockDuration => _parser.defaultTimedBlockDuration;
  QuickAddAnalysis analyze(
    String text, {
    DateTime? now,
    DateTime? defaultDate,
    bool includeInvalidScheduling = false,
  }) => _parser.analyze(
    text,
    now: now ?? this.now(),
    defaultDate: defaultDate,
    includeInvalidScheduling: includeInvalidScheduling,
  );
  ParsedQuickAdd parse(String text, {DateTime? now, DateTime? defaultDate}) =>
      _parser.parse(text, now: now ?? this.now(), defaultDate: defaultDate);
  String? projectToken(String name) =>
      quickAddProjectToken(name, _parser, now: now());
}
