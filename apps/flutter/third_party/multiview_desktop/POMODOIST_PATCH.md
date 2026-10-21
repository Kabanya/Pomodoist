# Local multiview_desktop patch

Upstream: multiview_desktop 1.2.1 from pub.dev (MIT; LICENSE retained).
The upstream `test/fixtures/plus.png` is retained because the package manifest declares it as a Flutter asset and the taskbar menu tests load it. Keep its repository ignore exception so desktop asset bundling works from a fresh checkout.

The application needs passive companion windows: `WindowOptions.focusOnShow=false` creates a hidden view and `show()` orders it without activating the application. Existing windows retain their default behavior. Exposes the native Flutter view ID and existing screen retrieval API for the companion adapter.

Utility windows (`isUtility=true`) are excluded from main-window anchor promotion. This preserves the main macOS window for Dock/Focus restoration even when hidden utilities exist. Closing the last real Windows window disposes utilities immediately. Pomo and Quick Add opt into this policy. Passive native geometry changes also avoid activation.

On macOS, restore hidden windows only through an explicit Dock reopen. Generic app activation (including a delayed activation from interacting with Pomo) must not restore the main window after the companion is hidden. The activation observer was removed; the existing Dock reopen handler retains restoration.

When the implicit window is hidden while other desktop windows remain, keep frames enabled by deferring an `inactive` transition until all `hidden` notifications finish. Notify the binding and its observers together so lifecycle listeners can later resume without an invalid `hidden` to `resumed` transition. Skip the deferred transition if windows close or the app already returns to the foreground.
