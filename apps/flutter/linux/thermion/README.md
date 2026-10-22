# Thermion Linux bridge override

Pomodoist retains `thermion_flutter` 0.5.0. CMake reads the resolved package and
generates one modified plugin translation unit inside the build directory. The
package cache is never edited. An exact upstream source hash prevents an
unreviewed dependency change from silently applying this patch elsewhere.

## X11 / XWayland

On GTK's X11 backend, its UI thread can have a GLX context while Flutter's raster
thread uses EGL. Upstream Thermion treats a missing current EGL context as a
reason to use its GBM/DMA-BUF path. That path exposes `GL_TEXTURE_EXTERNAL_OES`;
Flutter 3.47's Impeller external texture wrapper consumes a 2D texture instead.
This can leave the rendered model absent on NVIDIA.

The project helper creates an independent desktop OpenGL utility context on the
EGL display obtained from GDK's existing X11 `Display*`. Filament shares with
that utility context. Thermion's existing EGLImage bridge imports its output as
`GL_TEXTURE_2D` on Flutter's separate render context. Image contents are preserved
when imported, including when the renderer produces a single paused frame.

Temporary utility operations release and restore any native GLX binding, or the
previous EGL display, context, surfaces and client API. The helper does not
terminate the EGL display shared with GDK/Flutter. Wayland retains the existing
context initialization path; its temporary bindings receive the same restoration
and image-preservation safeguards.

## Reviewed upstream source

The fresh official pub.dev 0.5.0 archive was checked against the version API's
archive checksum. It matches the source hash enforced by `prepare_source.py`:

- Package archive SHA-256:
  `a5890c72caa2116eb174b79c8307744b3c1cb69af946295df22c3c057cb2dc61`
- `linux/thermion_flutter_plugin.cc` SHA-256:
  `30acb5e1afd32740e66472c051576f5f8b35ac0d321d45c2bf2784b9a25a561d`
- Package metadata: <https://pub.dev/api/packages/thermion_flutter/versions/0.5.0>

## Validation

Source-generation tests require no display:

```sh
python3 -m unittest discover -s tool/linux -p 'test_thermion*.py' -v
```

The native regression test requires an existing X11/XWayland session and the
GTK, Epoxy and X11 development packages. It creates only offscreen GL buffers,
checks exact RGBA readback through an EGLImage into an unshared GLES texture,
and verifies both GLX and EGL/GLES state restoration:

```sh
c++ -std=c++17 -Wall -Werror \
  $(pkg-config --cflags gtk+-3.0 epoxy) \
  apps/flutter/linux/thermion/tests/x11_context_test.cc \
  $(pkg-config --libs gtk+-3.0 epoxy x11) \
  -o /tmp/pomodoist-thermion-x11-test
GDK_BACKEND=x11 /tmp/pomodoist-thermion-x11-test
```

The backend selection above applies only to this standalone test. The product
uses the actual GDK backend selected for its running process. App-level model
visibility, orientation and lifecycle remain separate runtime checks.
