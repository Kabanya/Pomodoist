import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'another_view_model.dart';

class OtherViewModelViewModel extends Notifier<int> {
  @override
  int build() => 0;

  void dispatch() => ref.read(anotherViewModelProvider.notifier).bump();
}
