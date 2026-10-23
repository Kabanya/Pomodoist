"""Portable GNOME extension payload checks, independent of a running Shell."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile
import unittest
import zipfile

MODULE_PATH = Path(__file__).with_name('package_gnome_extension.py')


class ExtensionBundleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'extension source'
        self.source.mkdir()
        self.metadata = {'uuid': 'pomo@pomodoist.com', 'name': 'Pomo',
                         'version': 1, 'shell-version': ['46', '50', '51']}
        self.write_metadata()
        (self.source / 'extension.js').write_text('export default class Pomo {}\n')
        (self.source / 'core.js').write_text('export const version = 1;\n')
        (self.source / 'tests').mkdir()
        (self.source / 'tests' / 'core.test.js').write_text('test-only\n')
        spec = importlib.util.spec_from_file_location('pomo_gnome_package', MODULE_PATH)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def write_metadata(self):
        (self.source / 'metadata.json').write_text(json.dumps(self.metadata))

    def test_reproducible_archive_contains_runtime_sources_not_tests(self):
        first = self.root / 'first.zip'
        second = self.root / 'second.zip'
        self.module.build_extension_bundle(self.source, first)
        (self.source / 'extension.js').touch()
        self.module.build_extension_bundle(self.source, second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as archive:
            self.assertEqual(archive.namelist(), ['core.js', 'extension.js', 'metadata.json'])
            self.assertEqual(archive.read('core.js'), b'export const version = 1;\n')
            self.assertEqual(json.loads(archive.read('metadata.json')), self.metadata)

    def test_rejects_incorrect_identity_or_unknown_shell_versions(self):
        for field, value in [('uuid', '../other'), ('shell-version', ['46', '52']),
                             ('version', 0), ('version', True)]:
            with self.subTest(field=field, value=value):
                saved = self.metadata.copy()
                self.metadata[field] = value
                self.write_metadata()
                output = self.root / 'invalid.zip'
                with self.assertRaises(ValueError):
                    self.module.build_extension_bundle(self.source, output)
                self.assertFalse(output.exists())
                self.metadata = saved

    def test_rejects_symlink_and_missing_runtime_entrypoint(self):
        (self.source / 'alias.js').symlink_to(self.source / 'core.js')
        with self.assertRaises(ValueError):
            self.module.build_extension_bundle(self.source, self.root / 'link.zip')
        (self.source / 'alias.js').unlink()
        (self.source / 'extension.js').unlink()
        with self.assertRaises(ValueError):
            self.module.build_extension_bundle(self.source, self.root / 'missing.zip')

    def test_cmake_installs_extension_zip_and_sources_without_native_build(self):
        repo = Path(__file__).resolve().parents[2]
        fixture = self.root / 'fixture repo'
        linux = fixture / 'apps/flutter/linux'
        linux.mkdir(parents=True)
        tools = fixture / 'tool/linux'
        tools.mkdir(parents=True)
        shutil.copyfile(MODULE_PATH, tools / MODULE_PATH.name)
        shutil.copyfile(repo / 'apps/flutter/linux/gnome_extension.cmake',
                        linux / 'gnome_extension.cmake')
        shutil.copytree(self.source, linux / 'gnome-extension/pomo@pomodoist.com')
        (linux / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.19)\nproject(ExtensionFixture NONE)\n'
            'set(BINARY_NAME fixture)\nadd_custom_target(fixture)\n'
            'set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")\n'
            'include(gnome_extension.cmake)\n')
        build = self.root / 'CMake build'
        destination = self.root / 'installed bundle'
        for command in [['cmake', '-S', str(linux), '-B', str(build),
                         f'-DCMAKE_INSTALL_PREFIX={destination}'],
                        ['cmake', '--build', str(build)],
                        ['cmake', '--install', str(build), '--component', 'Runtime']]:
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = destination / 'data/gnome-extension'
        with zipfile.ZipFile(payload / 'pomo@pomodoist.com.shell-extension.zip') as archive:
            for name in archive.namelist():
                self.assertEqual((payload / 'pomo@pomodoist.com' / name).read_bytes(),
                                 archive.read(name))
        self.assertFalse((payload / 'pomo@pomodoist.com/tests').exists())

    def test_cli_installs_matching_source_and_zip_payloads_with_spaces(self):
        output = self.root / 'bundle data' / 'pomo@pomodoist.com.shell-extension.zip'
        sources_out = self.root / 'bundle data' / 'pomo@pomodoist.com'
        result = subprocess.run([sys.executable, str(MODULE_PATH), '--source', str(self.source),
                                 '--output', str(output), '--sources-out', str(sources_out)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            for name in archive.namelist():
                self.assertEqual((sources_out / name).read_bytes(), archive.read(name))
        self.assertFalse((sources_out / 'tests').exists())


if __name__ == '__main__':
    unittest.main()
