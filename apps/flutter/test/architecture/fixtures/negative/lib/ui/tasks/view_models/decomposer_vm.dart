import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/planning/concrete_decomposer.dart';

final decomposerProvider = Provider((ref) => ConcreteDecomposer());
void run(Ref ref) {
  ref.read(decomposerProvider).run();
}
