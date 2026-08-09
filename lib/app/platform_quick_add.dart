import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const quickAddChannelName = 'pomodoist/quick_add';
const quickAddCreateTaskMethod = 'createTask';
const quickAddGetHintMethod = 'getQuickAddHint';

final platformQuickAddControllerProvider = Provider<PlatformQuickAddController>(
  (ref) {
    final controller = PlatformQuickAddController(ref);
    controller.initialize();
    ref.onDispose(controller.dispose);
    return controller;
  },
);

class PlatformQuickAddController {
  PlatformQuickAddController(
    this._ref, {
    MethodChannel channel = const MethodChannel(quickAddChannelName),
  }) : _channel = channel;

  final Ref _ref;
  final MethodChannel _channel;
  bool _initialized = false;

  void initialize() {
    if (_initialized) {
      return;
    }
    _channel.setMethodCallHandler(handleMethodCall);
    _initialized = true;
  }

  void dispose() {
    if (!_initialized) {
      return;
    }
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }

  @visibleForTesting
  Future<Object?> handleMethodCall(MethodCall call) {
    return switch (call.method) {
      quickAddCreateTaskMethod => _createTask(call.arguments),
      quickAddGetHintMethod => _effectiveHint(),
      _ => throw MissingPluginException(
        'No method ${call.method} on $quickAddChannelName',
      ),
    };
  }

  Future<String> _effectiveHint() async {
    return _ref.read(effectiveQuickAddHintProvider);
  }

  Future<String> _createTask(Object? arguments) async {
    if (arguments is! String) {
      throw PlatformException(
        code: 'invalid_arguments',
        message: 'Expected a task description string.',
      );
    }

    final input = arguments.trim();
    if (input.isEmpty) {
      throw PlatformException(
        code: 'empty_task',
        message: 'Task content is empty.',
      );
    }

    try {
      await _ref.read(appStartupProvider.future);
      return _ref.read(quickAddServiceProvider).createTask(input);
    } on PlatformException {
      rethrow;
    } catch (error) {
      throw PlatformException(
        code: 'create_task_failed',
        message: error.toString(),
      );
    }
  }
}
