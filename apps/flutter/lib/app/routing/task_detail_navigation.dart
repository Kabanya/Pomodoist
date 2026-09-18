import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The mounted detail editor participates in navigation before it is disposed.
final taskDetailSaveGuardProvider = Provider((ref) => TaskDetailSaveGuard());

class TaskDetailSaveGuard {
  Future<bool> Function()? save;
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
