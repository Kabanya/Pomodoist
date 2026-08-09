import Cocoa
import FlutterMacOS

func resolveFlutterViewController(
  mainWindow: NSWindow?,
  windows: [NSWindow]
) -> FlutterViewController? {
  if let controller = mainWindow?.contentViewController as? FlutterViewController {
    return controller
  }

  return windows.lazy
    .compactMap { $0.contentViewController as? FlutterViewController }
    .first
}
