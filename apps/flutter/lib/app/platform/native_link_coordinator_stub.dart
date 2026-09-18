import 'native_link_coordinator_core.dart';

NativeLinkCoordinator createNativeLinkCoordinator() {
  return NativeLinkCoordinator(
    loadInitialLink: () async => null,
    loadLinkStream: () => const Stream<Uri>.empty(),
  );
}
