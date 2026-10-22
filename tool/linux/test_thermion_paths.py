"""Resolve native headers independently of Flutter's symlinked output directory."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / 'apps/flutter/linux/resolve_thermion.py'

class ThermionPathsTest(unittest.TestCase):
    def resolve(self, uri, symlink=False):
        with tempfile.TemporaryDirectory(prefix='pomo native paths ') as directory:
            root = Path(directory)
            config = root / 'app/.dart_tool/package_config.json'
            if symlink:
                target = root / 'build/deep/dart_tool'
                target.mkdir(parents=True)
                config.parent.parent.mkdir(parents=True)
                config.parent.symlink_to(target, target_is_directory=True)
            else:
                config.parent.mkdir(parents=True)
            package = root / 'cache with spaces/thermion'
            (package / 'native/include').mkdir(parents=True)
            (package / 'native/include/Log.hpp').write_text('// test header\n')
            root_uri = package.as_uri() if uri == 'absolute' else '../../cache%20with%20spaces/thermion'
            config.write_text(json.dumps({'packages': [{'name': 'thermion_dart', 'rootUri': root_uri}]}))
            result = subprocess.run(['python3', str(RESOLVER), str(config)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()), package)

    def test_absolute_file_uri_in_external_pub_cache(self):
        self.resolve('absolute')

    def test_relative_encoded_uri(self):
        self.resolve('relative')

    def test_relative_uri_uses_application_path_through_symlink(self):
        self.resolve('relative', symlink=True)

    def test_missing_package_reports_configuration_error(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'package_config.json'
            config.write_text('{"packages": []}')
            result = subprocess.run(['python3', str(RESOLVER), str(config)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('thermion_dart', result.stderr)

if __name__ == '__main__':
    unittest.main()
