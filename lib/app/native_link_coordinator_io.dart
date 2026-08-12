import 'package:app_links/app_links.dart';

import 'native_link_coordinator_core.dart';

NativeLinkCoordinator createNativeLinkCoordinator() {
  final appLinks = AppLinks();
  return NativeLinkCoordinator(
    loadInitialLink: appLinks.getInitialLink,
    linkStream: appLinks.uriLinkStream,
  );
}
