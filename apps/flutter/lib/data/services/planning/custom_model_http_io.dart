import 'dart:convert';
import 'dart:io';

const networkErrorMessage =
    'Could not connect to the model provider. Check the address and connection.';

Future<(int, String)> postChat(
  Uri url,
  String apiKey,
  String body,
  Duration timeout,
) async {
  final client = HttpClient();
  if (url.scheme == 'http') {
    // The caller allows cleartext only on loopback. Keep it on this device.
    client.findProxy = (_) => 'DIRECT';
  }
  Future<(int, String)> send() async {
    final request = await client.postUrl(url);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (apiKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    request.add(utf8.encode(body));
    final response = await request.close();
    final status = response.statusCode;
    if (status < 200 || status >= 300) return (status, '');
    return (status, await utf8.decoder.bind(response).join());
  }

  try {
    return await send().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
