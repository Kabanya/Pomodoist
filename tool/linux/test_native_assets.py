"""Configure the Linux project with a build directory outside the Flutter app."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeAssetsTests(unittest.TestCase):
    def test_thermion_resolves_package_headers_and_flavored_native_assets(self):
        for flavor, relative in (("development", False), ("staging", True), ("production", False)):
            with self.subTest(flavor=flavor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / "apps/flutter/linux"
                for child in ("flutter", "runner", "cmake"):
                    (source / child).mkdir(parents=True)
                shutil.copyfile(ROOT / "apps/flutter/linux/CMakeLists.txt", source / "CMakeLists.txt")
                # Keep this fixture focused on package paths; the X11 source
                # override is covered separately by test_thermion_x11.py.
                (source / "thermion_runtime.cmake").write_text("# X11 override excluded from the path fixture.\n")
                # The real extension CMake build/install is exercised by
                # test_gnome_extension_bundle.py; keep this fixture on Thermion.
                (source / "gnome_extension.cmake").write_text("# Extension packaging covered independently.\n")
                headers = root / "packages/thermion_dart/native/include"
                headers.mkdir(parents=True)
                (headers / "Log.hpp").write_text("#pragma once\n")
                (headers / "SurfaceExportInfo.h").write_text("#pragma once\n")
                config = source.parent / ".dart_tool/package_config.json"
                config.parent.mkdir()
                uri = "../../../packages/thermion_dart" if relative else headers.parents[1].as_uri()
                config.write_text(json.dumps({"packages": [{"name": "thermion_dart", "rootUri": uri}]}))
                (source / "empty.cpp").write_text("int main() { return 0; }\n")
                (source / "plugin.cpp").write_text('#include "Log.hpp"\n#include "SurfaceExportInfo.h"\n')
                (source / "cmake/FindPkgConfig.cmake").write_text("macro(pkg_check_modules)\nendmacro()\n")
                (source / "flutter/CMakeLists.txt").write_text(
                    f'set(FLUTTER_APP_FLAVOR "{flavor}" PARENT_SCOPE)\n'
                    'set(PROJECT_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build/" PARENT_SCOPE)\n'
                    'set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/icudtl.dat" PARENT_SCOPE)\n'
                    'set(FLUTTER_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libflutter.so" PARENT_SCOPE)\n'
                    'set(AOT_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/app.so" PARENT_SCOPE)\n'
                    'add_custom_target(flutter_assemble)\n'
                )
                (source / "runner/CMakeLists.txt").write_text(
                    'add_executable(pomodoist "${CMAKE_CURRENT_SOURCE_DIR}/../empty.cpp")\n'
                )
                (source / "flutter/generated_plugins.cmake").write_text(
                    'add_library(thermion_flutter_plugin STATIC "${CMAKE_CURRENT_SOURCE_DIR}/plugin.cpp")\n'
                    'add_library(multiview_desktop_plugin STATIC "${CMAKE_CURRENT_SOURCE_DIR}/empty.cpp")\n'
                )
                with (source / "CMakeLists.txt").open("a") as output:
                    output.write('\nget_target_property(dirs thermion_flutter_plugin LINK_DIRECTORIES)\n'
                                 'file(WRITE "${CMAKE_BINARY_DIR}/link-directories.txt" "${dirs}")\n')
                build = root / "build/flutter/linux/x64" / flavor / "release"
                for command in (["cmake", "-S", str(source), "-B", str(build),
                                 f"-DCMAKE_MODULE_PATH={source / 'cmake'}", "-DCMAKE_BUILD_TYPE=Release"],
                                ["cmake", "--build", str(build), "--target", "thermion_flutter_plugin"]):
                    result = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                assets = source.parent / "build/native_assets/linux"
                dirs = (build / "link-directories.txt").read_text().split(";")
                self.assertIn(assets.resolve(), [Path(item).resolve() for item in dirs])


if __name__ == "__main__":
    unittest.main()
