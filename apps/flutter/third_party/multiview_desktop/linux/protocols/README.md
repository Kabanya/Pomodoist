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
