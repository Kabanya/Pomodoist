import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const networkErrorMessage =
    'The browser could not connect to the model provider. Check the address, connection and the provider’s CORS settings.';

Future<(int, String)> postChat(
  Uri url,
  String apiKey,
  String body,
  Duration timeout,
) async {
  final workerUrl = Uri.parse(
    web.document.baseURI,
  ).resolve('custom_model_worker.js');
  final worker = web.Worker(workerUrl.toString().toJS);
  final result = Completer<(int, String)>();
  try {
    worker.onmessage = (web.MessageEvent event) {
      if (result.isCompleted) return;
      final reply = _Reply(event.data as JSObject);
      if (reply.status case final status?) {
        result.complete((status, reply.body ?? ''));
      } else {
        result.completeError(StateError('Provider connection failed.'));
      }
    }.toJS;
    worker.onerror = (web.Event event) {
      if (!result.isCompleted) {
        result.completeError(StateError('Provider worker failed.'));
      }
    }.toJS;
    worker.postMessage(
      {'url': url.toString(), 'key': apiKey, 'body': body}.jsify(),
    );
    return await result.future.timeout(timeout);
  } finally {
    worker.terminate();
  }
}

extension type _Reply(JSObject _) implements JSObject {
  external int? get status;
  external String? get body;
}
