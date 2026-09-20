part of 'part_vm.dart';

int partRepositoryHash(Ref ref) => ref.watch(partFixtureProvider).hashCode;
