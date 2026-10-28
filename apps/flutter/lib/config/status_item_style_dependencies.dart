import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository_native.dart';

final statusItemStyleRepositoryProvider =
    Provider.autoDispose<StatusItemStyleRepository>((ref) {
      final repository = NativeStatusItemStyleRepository();
      ref.onDispose(repository.dispose);
      return repository;
    });
