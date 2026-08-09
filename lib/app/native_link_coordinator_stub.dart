import 'native_link_coordinator_core.dart';

NativeLinkCoordinator createNativeLinkCoordinator() {
  return NativeLinkCoordinator(
    loadInitialLink: () async => null,
    linkStream: const Stream<Uri>.empty(),
  );
}
