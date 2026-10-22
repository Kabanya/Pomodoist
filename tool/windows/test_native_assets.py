"""Configure the real Windows project without requiring a Windows compiler."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NativeAssetsTests(unittest.TestCase):
    def test_thermion_links_and_installs_flutter_native_assets_for_every_flavor(self):
        for flavor in ("", "development", "staging", "production"):
            with self.subTest(flavor=flavor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / "app/windows"
                (source / "flutter").mkdir(parents=True)
                (source / "runner").mkdir()
                shutil.copyfile(ROOT / "apps/flutter/windows/CMakeLists.txt", source / "CMakeLists.txt")
                assets = root / "app/build/native_assets/windows"
                assets.mkdir(parents=True)
                for name in ("thermion_dart.dll", "thermion_dart.lib"):
                    (assets / name).touch()
                (source / "empty.cpp").write_text("int main() { return 0; }\n")
                (source / "flutter/CMakeLists.txt").write_text(
                    f'set(FLUTTER_APP_FLAVOR "{flavor}" PARENT_SCOPE)\n'
                    'set(PROJECT_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build/" PARENT_SCOPE)\n'
                    'set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/icudtl.dat" PARENT_SCOPE)\n'
                    'set(FLUTTER_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/flutter_windows.dll" PARENT_SCOPE)\n'
                    'set(AOT_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/app.so" PARENT_SCOPE)\n'
                )
                (source / "runner/CMakeLists.txt").write_text(
                    'add_executable(pomodoist "${CMAKE_CURRENT_SOURCE_DIR}/../empty.cpp")\n'
                )
                # Reproduce thermion_flutter 0.5.0's relative-path assumption.
                (source / "flutter/generated_plugins.cmake").write_text(
                    'add_library(thermion_flutter_plugin STATIC "${CMAKE_CURRENT_SOURCE_DIR}/empty.cpp")\n'
                    'set(old_assets "${CMAKE_CURRENT_BINARY_DIR}/runner/../../../native_assets/windows")\n'
                    'target_link_directories(thermion_flutter_plugin PRIVATE "${old_assets}")\n'
                    'set(PLUGIN_BUNDLED_LIBRARIES "${old_assets}/thermion_dart.dll;${old_assets}/thermion_dart.lib")\n'
                )
                with (source / "CMakeLists.txt").open("a") as output:
                    output.write(
                        '\nget_target_property(dirs thermion_flutter_plugin LINK_DIRECTORIES)\n'
                        'file(WRITE "${CMAKE_BINARY_DIR}/link-directories.txt" "${dirs}")\n'
                    )
                build = root / "app/build/windows/x64" / flavor
                configured = subprocess.run(
                    ["cmake", "-S", str(source), "-B", str(build), "-DCMAKE_BUILD_TYPE=Release"],
                    capture_output=True, text=True,
                )
                self.assertEqual(configured.returncode, 0, configured.stdout + configured.stderr)
                link_dirs = (build / "link-directories.txt").read_text().split(";")
                self.assertIn(assets.resolve(), [Path(item).resolve() for item in link_dirs])
                # The plugin's stale install paths must not survive either.
                install = (build / "cmake_install.cmake").read_text()
                self.assertNotIn("runner/../../../native_assets", install)


if __name__ == "__main__":
    unittest.main()
