import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/services/auth/email_auth_service.dart';

final sourceAdapterFixtureProvider = Provider<EmailAuthController>(
  (ref) => throw UnimplementedError(),
);

class SourceAdapterViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(sourceAdapterFixtureProvider).hashCode;
}
