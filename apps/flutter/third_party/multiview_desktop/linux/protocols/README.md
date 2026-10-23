# Relative pointer protocol

These files vendor the MIT-licensed `relative-pointer-unstable-v1` protocol from
[wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/unstable/relative-pointer/relative-pointer-unstable-v1.xml).
Their generated headers and implementation retain the upstream copyright and
permission notice.

They were generated with `wayland-scanner 1.26.0` using `client-header` and
`private-code`. The implementation has a `.cc` extension because this plugin is a
C++ project; it includes its client declarations and uses explicit `extern` on
the two constant interface definitions to preserve their linkage without C++
visibility warnings. No protocol scanner or protocol XML package is needed to
build the application. The plugin explicitly links `wayland-client >= 1.20`
(`libwayland-dev` on Debian-family distributions, `wayland` on Arch).

Pomo uses the accelerated logical deltas with GDK's borrowed `wl_pointer` only
during an active drag. It does not lock/confine the pointer, replace GDK listeners,
or disconnect the GTK-owned Wayland display.

## Logical output geometry

The MIT-licensed `xdg-output-unstable-v1.xml` is copied from the official
[wayland-protocols source](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/unstable/xdg-output/xdg-output-unstable-v1.xml).
Its copyright and permission notice are preserved; the local SPDX identifier is
MIT. The matching client header/private code use the same scanner and C++
linkage adaptation described above, so no new build/runtime package is required.

Pomo binds manager version 2 to receive independent, atomic `xdg_output.done`
events. GTK's `wl_output` listener is never replaced. New registry/output objects
use GTK's default event queue asynchronously, without an independent display
reader or blocking roundtrip. Connector names and committed logical rectangles
remain authoritative during live output rearrangement even when bundled GTK3's
monitor geometry becomes stale. Existing preference IDs remain unchanged.
