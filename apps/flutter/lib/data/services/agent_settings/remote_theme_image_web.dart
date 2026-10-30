import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:pomodoist/domain/models/settings/theme_image.dart';
import 'remote_theme_image_policy.dart'
    show readRemoteThemeImage, remoteThemeImageTimeout;

Future<Uint8List> downloadRemoteThemeImage(Uri uri) async {
  final abort = web.AbortController();
  final timeout = Timer(remoteThemeImageTimeout, () => abort.abort());
  web.ReadableStreamDefaultReader? reader;
  try {
    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            mode: 'cors',
            credentials: 'omit',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
            cache: 'no-store',
            signal: abort.signal,
            targetAddressSpace: 'public',
          ),
        )
        .toDart;
    if (response.status != 200 ||
        response.body == null ||
        !(response.headers.get('content-type') ?? '').toLowerCase().startsWith(
          'image/',
        )) {
      throw const FormatException('The URL must permit a CORS image download.');
    }
    if ((int.tryParse(response.headers.get('content-length') ?? '') ?? 0) >
        themeImageMaxBytes) {
      throw const ThemeImageTooLargeException();
    }
    // Browsers cannot inspect redirect targets; reject redirects before following.
    reader = response.body!.getReader() as web.ReadableStreamDefaultReader;
    Stream<List<int>> chunks() async* {
      while (true) {
        final chunk = await reader!.read().toDart;
        if (chunk.done) break;
        yield (chunk.value as JSUint8Array).toDart;
      }
    }

    return await readRemoteThemeImage(chunks());
  } finally {
    timeout.cancel();
    abort.abort();
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {
        /* The request may already be aborted. */
      }
    }
  }
}
