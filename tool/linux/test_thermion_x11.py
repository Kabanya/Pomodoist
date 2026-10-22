"""The build-local Thermion patch must fail closed and preserve upstream sources."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'apps/flutter/linux/thermion/prepare_source.py'


class ThermionX11SourceTest(unittest.TestCase):
    def load(self):
        spec = importlib.util.spec_from_file_location('thermion_x11_source', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_context_override_precedes_dmabuf_fallback_and_preserves_pixels(self):
        module = self.load()
        source = '''#include <epoxy/gl.h>
// RAII guard: saves the current EGL context/surfaces and restores on destruction.
struct EglContextGuard { int upstream_implementation; };
#define FLUTTER_FILAMENT_PLUGIN(obj) upstream_macro
void ensure_opengl_context() {
  // === Use Flutter's render context ===
  // Fallback: use the standalone LinuxOpenGLContext (GBM/DMA-BUF path)
  keep_original_fallback();
}
void texture() {
  EglContextGuard guard(display);
  EGLint imageAttribs[] = { EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE };
  keep_original_texture_bridge();
}
'''
        patched = module.patch_source(source)
        self.assertLess(patched.index('TryCreateX11UtilityContext'), patched.index('keep_original_fallback'))
        self.assertIn('self->flutter_egl_context = utility.context;', patched)
        self.assertIn('NativeGlContextGuard guard(display, self->utility_egl_context)', patched)
        self.assertIn('EGL_IMAGE_PRESERVED_KHR, EGL_TRUE', patched)
        self.assertIn('keep_original_texture_bridge();', patched)
        self.assertNotIn('upstream_implementation', patched)
        self.assertIn('upstream_implementation', source)

    def test_changed_upstream_source_is_rejected_without_writing_output(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'thermion_flutter_plugin.cc'
            output = Path(directory) / 'generated.cc'
            source.write_text('incompatible upstream version')
            with self.assertRaisesRegex(ValueError, '0.5.0'):
                module.prepare_source(source, output)
            self.assertFalse(output.exists())
            self.assertEqual(source.read_text(), 'incompatible upstream version')

    def test_missing_patch_anchor_is_rejected(self):
        module = self.load()
        with self.assertRaisesRegex(ValueError, 'anchor'):
            module.patch_source('unrecognized plugin source')


if __name__ == '__main__':
    unittest.main()
