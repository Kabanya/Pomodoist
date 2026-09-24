"""Run the smoke script against a narrow adb double, without an emulator."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tool/android/smoke_test.sh'


class SmokeTest(unittest.TestCase):
    def test_flavor_launches_real_activity_and_reports_adb_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            tools = Path(directory)
            adb = tools / 'adb'
            adb.write_text('''#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == shell && ${2:-} == am && ${3:-} == start ]]; then
  if [[ ${5:-} == -n && ${6:-} != "$EXPECTED_PACKAGE/com.finchforge.pomodoist.MainActivity" ]]; then
    echo 'Error type 3: Activity class does not exist.'
    exit 1
  fi
  if [[ ${ADB_FAIL_START:-0} == 1 ]]; then
    echo 'simulated activity failure'
    exit 1
  fi
  echo 'Status: ok'
fi
''')
            adb.chmod(0o755)
            sleep = tools / 'sleep'
            sleep.write_text('#!/usr/bin/env bash\nexit 0\n')
            sleep.chmod(0o755)
            env = os.environ | {'PATH': directory + os.pathsep + os.environ['PATH']}
            for flavor, package in (
                ('development', 'com.finchforge.pomodoist.dev'),
                ('staging', 'com.finchforge.pomodoist.stg'),
                ('production', 'com.finchforge.pomodoist'),
            ):
                with self.subTest(flavor=flavor):
                    env['EXPECTED_PACKAGE'] = package
                    result = subprocess.run(['bash', str(SCRIPT), flavor], env=env,
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            env['EXPECTED_PACKAGE'] = 'com.finchforge.pomodoist.dev'
            env['ADB_FAIL_START'] = '1'
            result = subprocess.run(['bash', str(SCRIPT), 'development'], env=env,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('simulated activity failure', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
