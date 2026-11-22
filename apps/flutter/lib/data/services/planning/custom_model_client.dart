import 'dart:async';
import 'dart:convert';

import 'package:pomodoist/domain/models/settings/custom_model_config.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

import 'custom_model_http_io.dart'
    if (dart.library.js_interop) 'custom_model_http_web.dart'
    as transport;
import 'task_decomposer.dart';
import 'task_decomposition_prompt.dart';

/// Sends only the supplied task text and planning context to the chosen model.
class CustomModelClient {
  const CustomModelClient({
    this.fastTimeout = const Duration(seconds: 45),
    this.smartTimeout = const Duration(seconds: 120),
  });

  final Duration fastTimeout;
  final Duration smartTimeout;

  static Uri parseBaseUrl(String input) {
    const invalid = FormatException('Invalid model base URL.');
    final value = input.trim();
    if (RegExp(r'[\s\\\x00-\x1f\x7f]').hasMatch(value)) throw invalid;
    final authority = RegExp(
      r'^https?://([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (authority == null || authority.contains(RegExp(r'[@%<>"^|{}`]'))) {
      throw invalid;
    }

    try {
      final url = Uri.parse(value);
      if (url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment ||
          authority.endsWith(':') ||
          url.port < 1 ||
          url.port > 65535) {
        throw invalid;
      }
      final host = url.host;
      final ipv6Loopback = host.contains(':') && _isLoopbackIpv6(host);
      if (url.scheme == 'http' &&
          host != 'localhost' &&
          !ipv6Loopback &&
          !_isLoopbackIpv4(host)) {
        throw invalid;
      }
      return url.replace(
        host: ipv6Loopback ? '::1' : null,
        path: url.path.replaceFirst(RegExp(r'/+$'), ''),
      );
    } on FormatException {
      // Uri.parse exceptions may include credentials or the original input.
      throw invalid;
    }
  }

  static bool _isLoopbackIpv6(String host) {
    final bytes = Uri.parseIPv6Address(host);
    return bytes.last == 1 && bytes.take(15).every((byte) => byte == 0);
  }

  static bool _isLoopbackIpv4(String host) {
    try {
      final bytes = Uri.parseIPv4Address(host);
      return bytes.first == 127 && bytes.join('.') == host;
    } on FormatException {
      return false;
    }
  }

  Future<List<DecomposedTaskDraft>> decompose({
    required Uri baseUrl,
    required String model,
    required String apiKey,
    required String transcript,
    required DateTime now,
    required String locale,
    required bool smartMode,
  }) async {
    if (transcript.trim().isEmpty) return const [];
    late final Uri base;
    try {
      base = parseBaseUrl(baseUrl.toString());
    } on FormatException {
      throw const CustomModelException(
        ModelCheck.configuration,
        'Invalid model base URL.',
      );
    }
    if (model.trim().isEmpty || apiKey.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const CustomModelException(
        ModelCheck.configuration,
        'Invalid model settings.',
      );
    }
    final url = base.replace(path: '${base.path}/chat/completions');
    final body = jsonEncode({
      'model': model.trim(),
      'messages': [
        {
          'role': 'system',
          'content': smartMode
              ? '$taskDecompositionPrompt\nBefore answering, verify that all tasks, explicit child steps, dates, and priorities are represented accurately.'
              : taskDecompositionPrompt,
        },
        {
          'role': 'user',
          'content':
              'Locale: $locale\nCurrent local time: ${taskDecompositionLocalTime(now)}\n\nTranscript:\n${transcript.trim()}',
        },
      ],
    });
    final (int status, String response) result;
    try {
      result = await transport.postChat(
        url,
        apiKey.trim(),
        body,
        smartMode ? smartTimeout : fastTimeout,
      );
    } on TimeoutException {
      throw const CustomModelException(
        ModelCheck.timeout,
        'The model request timed out.',
      );
    } on FormatException {
      throw const CustomModelException(
        ModelCheck.invalidResponse,
        'The model returned an invalid response.',
      );
    } catch (_) {
      throw CustomModelException(
        ModelCheck.network,
        transport.networkErrorMessage,
      );
    }
    final (status, response) = result;
    if (status == 401 || status == 403) {
      throw const CustomModelException(
        ModelCheck.unauthorized,
        'The provider rejected the API key or model access.',
      );
    }
    if (status == 429) {
      throw const CustomModelException(
        ModelCheck.rateLimited,
        'The provider rate limit was reached.',
      );
    }
    if (status < 200 || status >= 300) {
      throw CustomModelException(
        ModelCheck.provider,
        'The model provider returned HTTP $status.',
      );
    }
    try {
      final tasks = decodeDeepSeekTaskResponse(response);
      if (tasks.isNotEmpty) return tasks;
    } on FormatException {
      // The raw response may contain the transcript, provider details or secrets.
    }
    throw const CustomModelException(
      ModelCheck.invalidResponse,
      'The model returned no readable task drafts.',
    );
  }
}
