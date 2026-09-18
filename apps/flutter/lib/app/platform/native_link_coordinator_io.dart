import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'native_link_coordinator_core.dart';
import 'windows_native_link_source.dart';

NativeLinkCoordinator createNativeLinkCoordinator() {
  final appLinks = AppLinks();
  if (Platform.isWindows) {
    final nativeLinks = WindowsNativeLinkSource(
      beforeEmit: _exchangeWindowsAccountAuthCallback,
    )..start();
    return NativeLinkCoordinator(
      loadInitialLink: appLinks.getInitialLink,
      loadLinkStream: () => nativeLinks.links,
      disposeLinkSource: nativeLinks.dispose,
    );
  }
  return NativeLinkCoordinator(
    loadInitialLink: appLinks.getInitialLink,
    loadLinkStream: () => appLinks.uriLinkStream,
  );
}

Future<void> _exchangeWindowsAccountAuthCallback(Uri uri) async {
  if (!isWindowsAccountAuthCallback(uri)) return;
  await Supabase.instance.client.auth.getSessionFromUrl(uri);
}
