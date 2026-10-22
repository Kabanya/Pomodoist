#!/usr/bin/env python3
"""Generate the reviewed Thermion 0.5.0 X11 fix in the build directory only."""
import hashlib
from pathlib import Path
import sys

# Pin the exact upstream 0.5.0 translation unit. A
# dependency update must review these changes rather than silently mispatch it.
UPSTREAM_SHA256 = '30acb5e1afd32740e66472c051576f5f8b35ac0d321d45c2bf2784b9a25a561d'
CONTEXT_CAPTURE = "  // === Use Flutter's render context ==="
X11_BRIDGE = '''  // X11's GTK context can be GLX while Flutter's raster context is EGL.
  // Use an independent desktop GL share group on the same native EGLDisplay,
  // then reuse Thermion's existing EGLImage -> GL_TEXTURE_2D bridge.
  pomodoist::X11UtilityContext utility;
  if (pomodoist::TryCreateX11UtilityContext(&utility)) {
    self->flutter_egl_context = utility.context;
    self->utility_egl_context = utility.context;
    self->egl_display = utility.display;
    self->egl_config = utility.config;
    self->use_direct_opengl = TRUE;
    self->backend_type = BACKEND_OPENGL;
    self->thermion_platform = ThermionPlatformEGLHeadless_Create(utility.display);
    std::cerr << "[ThermionGL] Created X11 EGLImage utility context="
              << (void*)utility.context << " display=" << (void*)utility.display << std::endl;
    return;
  }

'''


def replace_once(source: str, anchor: str, replacement: str) -> str:
    if source.count(anchor) != 1:
        raise ValueError(f'Thermion source patch anchor changed: {anchor[:70]}')
    return source.replace(anchor, replacement, 1)


def patch_source(source: str) -> str:
    source = replace_once(source, '#include <epoxy/gl.h>',
                          '#include <epoxy/gl.h>\n#include "thermion/x11_context.h"')
    start_marker = '// RAII guard: saves the current EGL context/surfaces and restores on destruction.'
    end_marker = '#define FLUTTER_FILAMENT_PLUGIN(obj)'
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise ValueError('Thermion native context guard anchor changed')
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    source = source[:start] + source[end:]
    # Every temporary utility binding must restore both EGL and native GLX.
    source = source.replace('EglContextGuard guard(display);',
                            'pomodoist::NativeGlContextGuard guard(display, self->utility_egl_context);')
    source = source.replace('EglContextGuard guard(self->egl_display);',
                            'pomodoist::NativeGlContextGuard guard(self->egl_display, self->utility_egl_context);')
    source = replace_once(source, CONTEXT_CAPTURE, X11_BRIDGE + CONTEXT_CAPTURE)
    source = replace_once(source,
        'EGLint imageAttribs[] = { EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE };',
        'EGLint imageAttribs[] = { EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };')
    return source


def prepare_source(source: Path, destination: Path) -> None:
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != UPSTREAM_SHA256:
        raise ValueError('Reviewed thermion_flutter 0.5.0 source changed; update the Linux bridge patch explicitly')
    patched = patch_source(original.decode())
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists() or destination.read_text() != patched:
        destination.write_text(patched)


if __name__ == '__main__':
    try:
        prepare_source(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, IndexError) as error:
        print(f'Thermion Linux source override: {error}', file=sys.stderr)
        sys.exit(1)
