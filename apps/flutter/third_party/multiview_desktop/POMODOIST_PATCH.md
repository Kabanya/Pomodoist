# Local multiview_desktop patch

Upstream: multiview_desktop 1.2.1 from pub.dev (MIT; LICENSE retained).
The upstream `test/fixtures/plus.png` is retained because the package manifest declares it as a Flutter asset and the taskbar menu tests load it. Keep its repository ignore exception so desktop asset bundling works from a fresh checkout.

The application needs passive companion windows: `WindowOptions.focusOnShow=false` creates a hidden view and `show()` orders it without activating the application. Existing windows retain their default behavior. Exposes the native Flutter view ID and existing screen retrieval API for the companion adapter.

Utility windows (`isUtility=true`) are excluded from main-window anchor promotion. This preserves the main macOS window for Dock/Focus restoration even when hidden utilities exist. Closing the last real Windows window disposes utilities immediately. Pomo and Quick Add opt into this policy. Passive native geometry changes also avoid activation.

On macOS, restore hidden windows only through an explicit Dock reopen. Generic app activation (including a delayed activation from interacting with Pomo) must not restore the main window after the companion is hidden. The activation observer was removed; the existing Dock reopen handler retains restoration.

When the implicit window is hidden while other desktop windows remain, keep frames enabled by deferring an `inactive` transition until all `hidden` notifications finish. Notify the binding and its observers together so lifecycle listeners can later resume without an invalid `hidden` to `resumed` transition. Skip the deferred transition if windows close or the app already returns to the foreground.

On Linux, `linuxDesktopOverlay=true` is an explicit per-window Pomo opt-in, carried
with `isUtility`, `focusOnShow` and the background color in the creation request.
The GTK visual, FlView backing color, passive activation policy, and Wayland
surface role are applied before realization. Linux decodes `backgroundColorA/R/G/B`
for both creation and subsequent `setBackgroundColor` calls; legacy mismatched
`alpha/red/green/blue` names used to silently restore an opaque black backing. Main and Quick Add retain ordinary
GTK toplevel roles. Passive windows wait for explicit `show()` even after their
first Flutter frame, and showing them does not call `gtk_window_present`.

The runner's `pomodoist/pomo_window` channel delegates to exported plugin APIs;
it does not access the window registry. On X11, Pomo requires an RGBA visual and
an active compositor. On Wayland, it requires `gtk-layer-shell` and layer-shell
protocol version 4 for on-demand keyboard input. Only Pomo's mascot and compact
panel use a top layer, zero exclusive zone, and on-demand keyboard mode.
Unsupported native backends return an availability reason without changing GDK
backend selection. Input regions are Cairo/GDK input shapes, preserving alpha
and passing transparent exterior space through to other applications.

Linux environment, cursor, bounds and move coordinates use GTK logical pixels;
`scale` is informational, not a multiplier for global coordinates. Wayland bounds
track monitor-relative layer placement, since Wayland does not expose absolute
surface positions. Moves may include `displayId`; stale explicit IDs are rejected.
Monitor IDs use manufacturer, model and physical size and are cached on the
GdkMonitor object, so list reordering does not change them. Identical displays use
connection-lifetime suffixes; GTK3 provides no portable connector or serial API.
Work areas use GDK's reported values, which may equal monitor geometry on Wayland.
The compositor still applies its reserved zones to zero-exclusive-zone surfaces.

The Linux build links `gtk-layer-shell-0 >= 0.6`. The AppImage preparation copies
its runtime SONAME as a regular file and includes upstream LGPL, GPL, MIT and
source notices. Arch setup and Linux CI install the development/runtime package.
The dependency is dynamically linked and does not impose a layer-shell role on
ordinary windows.

Pure Linux geometry unit checks run with `tool/linux/test_pomo_geometry.sh` from
the repository root. Creation encoding is covered by
`test/native_channel_create_window_test.dart` in this package. Native builds,
app launches and compositor-specific interaction checks are a separate phase.
