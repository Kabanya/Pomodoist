import 'dart:async';

import 'package:dio/dio.dart';

import 'update_contracts.dart';
import 'update_release.dart';

/// Dedicated unauthenticated client: never share account/auth interceptors with
/// GitHub. All pages are considered because publication order is not SemVer order.
class GitHubUpdateSource implements UpdateSource {
  GitHubUpdateSource({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Pomodoist-Desktop-Updater',
    },
  ));
  final Dio _dio;
  CancelToken? _request;

  @override
  Future<UpdateOffer?> findUpdate({required UpdateVersion current,
    required UpdateTarget target, required UpdateChannel channel}) async {
    final token = CancelToken();
    _request = token;
    final deadline = Timer(const Duration(seconds: 45), () => token.cancel('timeout'));
    final releases = <Object?>[];
    try {
      for (var page = 1; page <= 100; page++) {
        final response = await _dio.get<List<dynamic>>(
          'https://api.github.com/repos/Kabanya/Pomodoist/releases',
          queryParameters: {'per_page': 100, 'page': page}, cancelToken: token,
        );
        final data = response.data;
        if (data == null) throw const UpdateFailure('GitHub returned an empty release response.');
        releases.addAll(data);
        if (data.length < 100) {
          return selectUpdate(releases, current: current, target: target, channel: channel);
        }
      }
      throw const UpdateFailure('Too many releases to safely select an update. Try again later.');
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 403 || status == 429) {
        throw const UpdateFailure('GitHub rate limit reached. Please try again later.');
      }
      throw const UpdateFailure('Could not check GitHub releases. Check your connection and try again.');
    } finally {
      deadline.cancel();
      if (identical(_request, token)) _request = null;
    }
  }

  @override
  void dispose() {
    _request?.cancel('disposed');
    _dio.close(force: true);
  }
}
