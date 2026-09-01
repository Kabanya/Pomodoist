import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web container is public-client only', () async {
    final dockerfile = await File('deploy/web/Dockerfile').readAsString();
    final entrypoint = await File('deploy/web/entrypoint.sh').readAsString();
    final nginx = await File('deploy/web/nginx.conf').readAsString();
    final association = jsonDecode(
      await File('web/.well-known/apple-app-site-association').readAsString(),
    );

    expect(association, isA<Map<String, dynamic>>());
    expect(dockerfile, contains('COPY .fvmrc ./'));
    expect(dockerfile, contains(r'jq -r .flutter .fvmrc'));
    expect(dockerfile, contains(r'origin "refs/tags/$flutter_version"'));
    expect(dockerfile, contains('POMODOIST_BILLING_CHANNEL must be stripe'));
    expect(dockerfile, isNot(contains('account-sync-platform')));
    expect(entrypoint, contains('SUPABASE_ANON_KEY'));
    expect(entrypoint, isNot(contains('SERVICE_ROLE_KEY')));
    expect(nginx, contains(r'location ~* \.map$'));
    expect(nginx, contains('return 404'));
  });
}
