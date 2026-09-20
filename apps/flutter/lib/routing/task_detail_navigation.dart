import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The mounted detail editors participate in navigation before they dispose.
final taskDetailSaveGuardProvider = Provider((ref) => TaskDetailSaveGuard());

class TaskDetailSaveGuard {
  final Map<Object, Future<bool> Function()> _editors = {};

  bool get hasRegisteredEditors => _editors.isNotEmpty;

  void register(Object identity, Future<bool> Function() save) {
    _editors[identity] = save;
  }

  void unregister(Object identity) {
    _editors.remove(identity);
  }

  /// Saves every retained editor draft before navigation. A failed draft keeps
  /// its editor registered and blocks the route change.
  Future<bool> saveAll() async {
    var saved = true;
    for (final save in List<Future<bool> Function()>.of(_editors.values)) {
      if (!await save()) saved = false;
    }
    return saved;
  }
}

Uri taskDetailUri(Uri background, String? taskId) {
  if (background.pathSegments.firstOrNull == 'task') {
    return taskId == null
        ? Uri(path: '/today')
        : Uri(pathSegments: ['', 'task', taskId]);
  }
  final query = Map<String, dynamic>.from(background.queryParametersAll);
  if (taskId == null) {
    query.remove('task');
  } else {
    query['task'] = taskId;
  }
  return Uri(
    scheme: background.scheme,
    userInfo: background.userInfo,
    host: background.hasAuthority ? background.host : null,
    port: background.hasPort ? background.port : null,
    path: background.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: background.hasFragment ? background.fragment : null,
  );
}

void openTaskDetails(BuildContext context, String taskId) {
  final router = GoRouter.of(context);
  final current = router.state.uri;
  final target = taskDetailUri(current, taskId);
  if (target == current) return;
  if (current.queryParameters.containsKey('task')) {
    Router.neglect(context, () => router.go(target.toString()));
  } else {
    Router.navigate(context, () => router.go(target.toString()));
  }
}

void closeTaskDetails(BuildContext context) {
  final router = GoRouter.of(context);
  Router.neglect(
    context,
    () => router.go(taskDetailUri(router.state.uri, null).toString()),
  );
}
