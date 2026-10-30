import 'dart:async';

/// One leased primary app instance; the server owns expiry and request identity.
class AgentAppSettingsRuntime {
  AgentAppSettingsRuntime({
    required this.deviceId,
    required this.instanceId,
    required this.name,
    required this.platform,
    required this.capabilities,
    required this.isCurrent,
    required this.invoke,
    required this.snapshot,
    required this.apply,
    required this.readJournal,
    required this.writeJournal,
    this.hints,
  });

  final String deviceId, instanceId, name, platform;
  final Map<String, dynamic> capabilities;
  final bool Function() isCurrent;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) invoke;
  final Future<Map<String, dynamic>> Function() snapshot;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) apply;
  final Future<Map<String, dynamic>?> Function() readJournal;
  final Future<void> Function(Map<String, dynamic>?) writeJournal;
  final Stream<void>? hints;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  bool _disposed = false, _registered = false, _reconciled = false;
  Future<void>? _running;
  Map<String, dynamic>? _completion;
  bool get _current => !_disposed && isCurrent();

  void start() {
    if (_disposed || _timer != null) return;
    _subscription = hints?.listen(
      (_) => unawaited(pulse()),
      onError: (Object _) {},
    );
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(pulse()),
    );
    unawaited(pulse());
  }

  Future<void> pulse() {
    if (!_current) return Future.value();
    return _running ??= _pulse().whenComplete(() => _running = null);
  }

  Map<String, dynamic> _body(String action) => {
    'action': action,
    'deviceId': deviceId,
    'instanceId': instanceId,
  };

  Future<void> _pulse() async {
    try {
      final registration = await invoke({
        ..._body('register'),
        'name': name,
        'platform': platform,
        'capabilities': capabilities,
      });
      if (!_current || registration['registered'] != true) {
        _registered = false;
        return;
      }
      _registered = true;
      if (!_reconciled) {
        final journal = await readJournal();
        if (!_current) return;
        if (journal != null &&
            journal['instanceId'] != instanceId &&
            journal['phase'] == 'executing') {
          final actual = await snapshot();
          if (!_current) return;
          // The previous outcome stays uncertain; never attribute new state to it.
          await writeJournal({
            ...journal,
            'phase': 'uncertain',
            'actual': actual,
          });
        }
        _reconciled = true;
      }
      if (_completion != null) await _finish();
      if (!_current || _completion != null) return;
      for (var count = 0; count < 100 && _current; count++) {
        final response = await invoke(_body('claim'));
        if (!_current) return;
        final commands = response['commands'];
        if (commands is! List || commands.isEmpty) return;
        final command = Map<String, dynamic>.from(commands.single as Map);
        final requestId = command['request_id'];
        if (requestId is! String) {
          throw const FormatException('Missing request ID.');
        }
        Map<String, dynamic> result;
        try {
          if (command['operation'] == 'read') {
            result = await snapshot();
          } else {
            await writeJournal({
              'requestId': requestId,
              'instanceId': instanceId,
              'phase': 'executing',
              'setting': command['setting'],
            });
            if (!_current) return;
            result = await apply(command);
          }
        } catch (_) {
          // Native/network exceptions can contain URLs or filesystem paths.
          result = {
            'status': 'error',
            'code': 'apply_failed',
            'message':
                'The setting could not be saved. Read current settings before retrying.',
          };
        }
        if (!_current) return;
        _completion = {'requestId': requestId, 'result': result};
        if (command['operation'] != 'read') {
          await writeJournal({
            'requestId': requestId,
            'instanceId': instanceId,
            'phase': 'completed',
            'result': result,
          });
        }
        await _finish();
        if (!_current || _completion != null) return;
      }
    } catch (_) {
      // Retry transport/acknowledgment, never the local side effect.
    }
  }

  Future<void> _finish() async {
    final completion = _completion;
    if (!_current || completion == null) return;
    await invoke({..._body('finish'), ...completion});
    if (!_current) return;
    _completion = null;
    await writeJournal(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    if (_registered && isCurrent()) {
      unawaited(
        invoke(_body('disconnect')).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}
