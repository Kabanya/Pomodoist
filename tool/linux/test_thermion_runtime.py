"""Exercise real ELF lookup after Flutter-style install(FILES) relocation."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATHS = ROOT / 'apps/flutter/linux/thermion_runtime_paths.cmake'


class ThermionRuntimeTest(unittest.TestCase):
    def test_plugin_loads_sibling_native_asset_after_bundle_relocation(self):
        with tempfile.TemporaryDirectory(prefix='pomo ELF relocation ') as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            build = root / 'build'
            assets = root / 'native assets'
            bundle = root / 'original bundle'
            tools = root / 'tools'
            (source / 'asset.c').write_text('int thermion_value(void) { return 42; }\n')
            (source / 'plugin.c').write_text('extern int thermion_value(void);\nint plugin_value(void) { return thermion_value(); }\n')
            (source / 'loader.c').write_text('''#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) { fprintf(stderr, "%s\\n", dlerror()); return 1; }
  int (*value)(void) = (int (*)(void))dlsym(library, "plugin_value");
  if (!value) return 3;
  int result = value(); dlclose(library);
  printf("%d\\n", result); return result == 42 ? 0 : 4;
}
''')
            (source / 'CMakeLists.txt').write_text(f'''cmake_minimum_required(VERSION 3.19)
project(thermion_relocation C)
add_library(thermion_dart SHARED asset.c)
set_target_properties(thermion_dart PROPERTIES LIBRARY_OUTPUT_DIRECTORY "{assets}")
add_library(thermion_flutter_plugin SHARED plugin.c)
target_link_libraries(thermion_flutter_plugin PRIVATE thermion_dart)
include("{PATHS}")
pomodoist_configure_thermion_runtime_paths(thermion_flutter_plugin "{assets}")
add_executable(loader loader.c)
target_link_libraries(loader PRIVATE dl)
set_target_properties(loader PROPERTIES RUNTIME_OUTPUT_DIRECTORY "{tools}")
# Flutter bundles plugin target files without CMake's install RPATH rewriting.
install(FILES $<TARGET_FILE:thermion_flutter_plugin> $<TARGET_FILE:thermion_dart> DESTINATION lib)
''')
            def checked(*arguments):
                result = subprocess.run(arguments, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result
            checked('cmake', '-S', str(source), '-B', str(build), f'-DCMAKE_INSTALL_PREFIX={bundle}')
            checked('cmake', '--build', str(build))
            clean_environment = os.environ.copy()
            clean_environment.pop('LD_LIBRARY_PATH', None)
            def load(plugin):
                return subprocess.run([str(tools / 'loader'), str(plugin)], env=clean_environment,
                                      capture_output=True, text=True)
            development = load(build / 'libthermion_flutter_plugin.so')
            self.assertEqual(development.returncode, 0, development.stderr)
            checked('cmake', '--install', str(build))
            relocated = root / 'relocated bundle'
            shutil.move(bundle, relocated)
            shutil.rmtree(build)
            shutil.rmtree(assets)
            installed = load(relocated / 'lib/libthermion_flutter_plugin.so')
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertEqual(installed.stdout, '42\n')


if __name__ == '__main__':
    unittest.main()
