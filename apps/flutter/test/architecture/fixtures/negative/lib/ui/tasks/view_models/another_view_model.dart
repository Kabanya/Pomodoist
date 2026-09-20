import 'package:flutter_riverpod/flutter_riverpod.dart';

final anotherViewModelProvider = NotifierProvider<AnotherViewModel, int>(
  AnotherViewModel.new,
);

class AnotherViewModel extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {}
}
