import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadInput;

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/task_detail_navigation.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_shell.dart' show showQuickAddDialog;
import '../../focus/domain/focus_models.dart';
import '../../focus/presentation/focus_view_mode.dart';
import '../domain/task_models.dart';
import 'task_search.dart';

/// Stable identities keep keyboard selection attached to the same local result.
List<({String id, String title})> taskSearchPaletteResults(
  Iterable<TaskItem> tasks,
  Iterable<ProjectItem> projects,
  String query,
) {
  final search = query.trim().toLowerCase();
  return [
    if (search.isNotEmpty) ...[
      for (final task in filterTaskSearch(tasks, query: query).take(6))
        (id: 'task:${task.id}', title: task.content),
      for (final project
          in projects
              .where(
                (project) =>
                    !project.isDeleted &&
                    !project.isArchived &&
                    project.name.toLowerCase().contains(search),
              )
              .take(3))
        (id: 'project:${project.id}', title: project.name),
    ],
  ];
}

String? taskSearchPaletteSelection(
  List<String> ids,
  String? selected,
  int offset,
) {
  if (ids.isEmpty) return null;
  final index = ids.indexOf(selected ?? '');
  if (index < 0) {
    return offset == 0 ? null : (offset < 0 ? ids.last : ids.first);
  }
  return ids[(index + offset) % ids.length];
}

bool taskSearchPaletteCanActivate(
  List<String> currentIds,
  String id,
  String renderedQuery,
  String currentQuery,
) => renderedQuery == currentQuery && currentIds.contains(id);

Future<void> showTaskSearchPalette(BuildContext context) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final container = ProviderScope.containerOf(context);
  final result = await showDialog<({String id, String query})>(
    context: context,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
    builder: (_) => const _TaskSearchPalette(),
  );
  if (previousFocus?.context != null) previousFocus!.requestFocus();
  if (!context.mounted || result == null) return;
  if (result.id.startsWith('task:')) {
    final id = result.id.substring(5);
    final tasks = container
        .read(tasksByQueryProvider(const TaskQuery.all()))
        .value;
    if (tasks?.any(
          (task) => task.id == id && !task.isDeleted && !task.isCompleted,
        ) ??
        false) {
      openTaskDetails(context, id);
    }
  } else if (result.id.startsWith('project:')) {
    final id = result.id.substring(8);
    final projects = container.read(projectsProvider).value;
    if (projects?.any(
          (project) =>
              project.id == id && !project.isDeleted && !project.isArchived,
        ) ??
        false) {
      context.go(Uri(pathSegments: ['', 'project', id]).toString());
    }
  } else if (result.id == 'create') {
    await showQuickAddDialog(context, initialText: result.query);
  } else if (result.id == 'focus') {
    context.go('/focus');
  } else if (result.id == 'all') {
    context.go(
      Uri(path: '/search', queryParameters: {'q': result.query}).toString(),
    );
  }
}

class _TaskSearchPalette extends ConsumerStatefulWidget {
  const _TaskSearchPalette();

  @override
  ConsumerState<_TaskSearchPalette> createState() => _TaskSearchPaletteState();
}

class _TaskSearchPaletteState extends ConsumerState<_TaskSearchPalette> {
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  final _rowKeys = <String, GlobalKey>{};
  String? _selected;
  bool _selectFirstOnBuild = true;
  String _renderedQuery = '';
  bool _busy = false;
  String? _error;

  List<({String id, String title})> _results() => taskSearchPaletteResults(
    ref.read(tasksByQueryProvider(const TaskQuery.all())).value ?? [],
    ref.read(projectsProvider).value ?? [],
    _controller.text,
  );

  List<String> _ids() => [
    for (final result in _results()) result.id,
    'create',
    'focus',
    'all',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _activate(String id, String query) async {
    if (_busy ||
        !taskSearchPaletteCanActivate(_ids(), id, query, _controller.text) ||
        !_controller.value.composing.isCollapsed) {
      return;
    }
    if (id == 'focus') {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final run = await ref.read(activeFocusRunProvider.future);
        if (!mounted) return;
        if (run == null) {
          await ref.read(sharedPreferencesProvider.future);
          if (!mounted) return;
          final presets = await ref.read(focusPresetsProvider.future);
          if (!mounted) return;
          final preset = selectedFocusPresetOrDefault(
            presets,
            ref.read(lastFocusPresetIdProvider),
          );
          final currentRun = await ref
              .read(focusRepositoryProvider)
              .watchActiveRun()
              .first;
          if (!mounted) return;
          if (currentRun == null) {
            await ref
                .read(focusRepositoryProvider)
                .startRun(StartFocusRunInput(presetId: preset?.id));
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = context.l10n.focusActionFailed;
          });
        }
        return;
      }
      if (!mounted) return;
    }
    _busy = true;
    Navigator.of(context).pop((id: id, query: query));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!_busy) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected = taskSearchPaletteSelection(
          _ids(),
          _selected,
          event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _rowKeys[_selected]?.currentContext;
        if (mounted && rowContext != null) {
          Scrollable.ensureVisible(
            rowContext,
            alignment: .5,
            duration: AppMotion.duration(context, AppMotion.popup),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _selected != null) {
      _activate(_selected!, _renderedQuery);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final projects = ref.watch(projectsProvider);
    final run = ref.watch(activeFocusRunProvider);
    ref.watch(lastFocusPresetIdProvider);
    final results = _results();
    final l10n = context.l10n;
    final query = _controller.text;
    _renderedQuery = query;
    final ids = [
      for (final result in results) result.id,
      'create',
      'focus',
      'all',
    ];
    _selected = _selectFirstOnBuild
        ? ids.first
        : taskSearchPaletteSelection(ids, _selected, 0);
    _selectFirstOnBuild = false;
    final colors = context.appColors;

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.secondaryText),
      ),
    );
    Widget row(String id, String title, IconData icon) => Semantics(
      selected: _selected == id,
      child: ListTile(
        key: _rowKeys.putIfAbsent(id, GlobalKey.new),
        selected: _selected == id,
        selectedTileColor: colors.surfaceHover,
        leading: Icon(icon, size: 18),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        enabled: !_busy,
        onTap: () => _activate(id, query),
        onFocusChange: (focused) {
          if (focused) setState(() => _selected = id);
        },
      ),
    );

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: Focus(
              onKeyEvent: _onKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ShadInput(
                      controller: _controller,
                      focusNode: _inputFocus,
                      autofocus: true,
                      enabled: !_busy,
                      placeholder: Text(l10n.commandSearchPlaceholder),
                      leading: const Icon(LucideIcons.search, size: 18),
                      onChanged: (_) => setState(() {
                        _selected = null;
                        _selectFirstOnBuild = true;
                        _error = null;
                      }),
                    ),
                  ),
                  if (_busy || tasks.isLoading || projects.isLoading)
                    const LinearProgressIndicator(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (tasks.hasError || projects.hasError)
                          ListTile(
                            title: Text(l10n.taskListLoadError),
                            trailing: TextButton(
                              onPressed: () {
                                ref.invalidate(
                                  tasksByQueryProvider(const TaskQuery.all()),
                                );
                                ref.invalidate(projectsProvider);
                              },
                              child: Text(l10n.commonRetry),
                            ),
                          ),
                        if (query.trim().isNotEmpty &&
                            results.isEmpty &&
                            !tasks.isLoading &&
                            !projects.isLoading)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(l10n.commandSearchNoMatches),
                          ),
                        if (results.any(
                          (result) => result.id.startsWith('task:'),
                        ))
                          heading(l10n.commandSearchTasks),
                        for (final result in results.where(
                          (result) => result.id.startsWith('task:'),
                        ))
                          row(result.id, result.title, LucideIcons.circle),
                        if (results.any(
                          (result) => result.id.startsWith('project:'),
                        ))
                          heading(l10n.navProjects),
                        for (final result in results.where(
                          (result) => result.id.startsWith('project:'),
                        ))
                          row(result.id, result.title, LucideIcons.folder),
                        heading(l10n.commandSearchActions),
                        row(
                          'create',
                          query.trim().isEmpty
                              ? l10n.addTask
                              : l10n.searchCreateTask,
                          LucideIcons.plus,
                        ),
                        row(
                          'focus',
                          run.value == null ? l10n.startFocus : l10n.openFocus,
                          LucideIcons.timer,
                        ),
                        row(
                          'all',
                          l10n.commandSearchAllResults,
                          LucideIcons.search,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.commandSearchHint,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
