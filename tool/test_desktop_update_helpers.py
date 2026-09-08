"""Exercise the actual bundled POSIX helper using isolated fake AppImages."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'lib/features/updates/update_install_scripts.dart'


def bundled_script(name):
    source = SCRIPTS.read_text()
    match = re.search(r"const " + name + r" = r'''\n(.*?)\n''';", source, re.S)
    if not match:
        raise AssertionError(f'Missing bundled helper {name}')
    return match.group(1) + '\n'


@unittest.skipUnless(os.name == 'posix', 'POSIX helper')
class AppImageUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pomodoist ' test ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.stage = self.root / '.pomodoist-update-test'
        self.stage.mkdir()
        self.target = self.root / 'Pomodoist with spaces.AppImage'
        self.marker = self.root / 'launched'
        self.old = '#!/bin/sh\nprintf old > "' + str(self.marker) + '"\n'
        self.target.write_text(self.old)
        self.target.chmod(0o755)
        self.payload = self.stage / 'update.AppImage'
        self.payload.write_text(
            '#!/bin/sh\nprintf new > "' + str(self.marker) + '"\n'
            'printf started > "$POMODOIST_UPDATE_READY_FILE"\n'
        )
        self.script = self.stage / 'install.sh'
        self.script.write_text(bundled_script('linuxUpdateScript'))

    def run_helper(self, digest=None, parent='2147483647'):
        digest = digest or hashlib.sha256(self.payload.read_bytes()).hexdigest()
        return subprocess.run(
            ['/bin/sh', str(self.script), parent, str(self.target),
             str(self.payload), digest],
            capture_output=True, text=True, timeout=20,
        )

    def test_success_replaces_original_path_and_restarts(self):
        expected = self.payload.read_bytes()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_bytes(), expected)
        self.assertTrue(os.access(self.target, os.X_OK))
        self.assertEqual(self.marker.read_text(), 'new')
        self.assertEqual((self.stage / 'result').read_text().strip(), 'success')

    def test_bad_hash_preserves_original_without_launching(self):
        result = self.run_helper('0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_text(), self.old)
        self.assertFalse(self.marker.exists())

    def test_cancel_preserves_running_application(self):
        (self.stage / 'cancel').touch()
        result = self.run_helper(parent=str(os.getpid()))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_text(), self.old)
        self.assertFalse(self.marker.exists())

    def test_failed_new_executable_rolls_back(self):
        self.payload.write_text('#!/bin/sh\nexit 17\n')
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_text(), self.old)
        self.assertEqual(self.marker.read_text(), 'old')
        self.assertEqual((self.stage / 'result').read_text().strip(), 'failed')

    def test_rejects_symlink_target(self):
        real = self.root / 'real.AppImage'
        self.target.rename(real)
        self.target.symlink_to(real)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(real.read_text(), self.old)

    def test_second_helper_cannot_replace_locked_appimage(self):
        lock = Path(str(self.target) + '.update-lock')
        lock.mkdir()
        (lock / 'pid').write_text(str(os.getpid()))
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_text(), self.old)


if __name__ == '__main__':
    unittest.main()
