"""Exercise the temporary CI Keychain without accessing the real Keychain."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CiSigningTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state.json'
        self.initial = {'default': '/original/login.keychain-db',
                        'search': ['/original/login.keychain-db', '/original/Other Keychain'],
                        'calls': []}
        self.state.write_text(json.dumps(self.initial))
        self.env = os.environ | {
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'RUNNER_TEMP': str(self.root),
            'TEST_STATE': str(self.state),
            'POMODOIST_MACOS_CERTIFICATE_P12_BASE64': base64.b64encode(b'certificate').decode(),
            'POMODOIST_MACOS_CERTIFICATE_PASSWORD': 'fixture-p12-password',
            'POMODOIST_MACOS_SIGNING_IDENTITY': 'Developer ID Application: Fixture (TEAM)',
            'POMODOIST_MACOS_NOTARY_PROFILE': 'fixture-notary',
            'ASC_KEY_ID': 'FIXTUREKEY',
            'ASC_ISSUER_ID': 'fixture-issuer',
            'ASC_PRIVATE_KEY_BASE64': base64.b64encode(b'fixture-private-key').decode(),
        }
        fake = self.bin / 'fake'
        fake.write_text(f'#!{sys.executable}\n' + '''
import json, os, pathlib, sys
state_path = pathlib.Path(os.environ['TEST_STATE'])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
command = pathlib.Path(sys.argv[0]).name
state['calls'].append([command, *args])
status = 0
if command == 'security':
    if args[0] == 'default-keychain':
        if '-s' in args: state['default'] = args[-1]
        else: print('    "' + state['default'] + '"')
    elif args[0] == 'list-keychains':
        if '-s' in args: state['search'] = args[args.index('-s') + 1:]
        else:
            for name in state['search']: print('    "' + name + '"')
    elif args[0] == 'create-keychain':
        pathlib.Path(args[-1]).touch()
    elif args[0] == 'delete-keychain':
        pathlib.Path(args[-1]).unlink()
    elif args[0] == 'import':
        assert pathlib.Path(args[1]).read_bytes() == b'certificate'
        assert pathlib.Path(args[1]).stat().st_mode & 0o777 == 0o600
        if os.environ.get('TEST_IMPORT_FAILURE'): status = 1
    elif args[0] == 'find-identity':
        if not os.environ.get('TEST_MISSING_IDENTITY'):
            print('1) ABC "' + os.environ['POMODOIST_MACOS_SIGNING_IDENTITY'] + '"')
elif command == 'xcrun':
    assert args[:2] == ['notarytool', 'store-credentials']
    assert pathlib.Path(args[args.index('--key') + 1]).read_bytes() == b'fixture-private-key'
    assert pathlib.Path(args[args.index('--key') + 1]).stat().st_mode & 0o777 == 0o600
    if os.environ.get('TEST_NOTARY_FAILURE'): status = 1
elif command == 'build':
    assert state['default'] != '/original/login.keychain-db'
    mask = os.umask(0)
    os.umask(mask)
    state['build_umask'] = mask
    status = int(os.environ.get('TEST_BUILD_STATUS', '0'))
state_path.write_text(json.dumps(state))
sys.exit(status)
''')
        fake.chmod(0o755)
        for name in ('security', 'xcrun', 'build'):
            (self.bin / name).symlink_to(fake)

    def run_signing(self):
        return subprocess.run(['bash', '-c', 'umask 022; exec bash "$@"', 'ci-signing-test',
                               str(ROOT / 'tool/macos/ci_signing.sh'), 'build'],
                              env=self.env, capture_output=True, text=True)

    def assert_cleaned(self):
        state = json.loads(self.state.read_text())
        self.assertEqual(state['default'], self.initial['default'])
        self.assertEqual(state['search'], self.initial['search'])
        self.assertEqual(list(self.root.glob('pomodoist-signing.*')), [])
        return state['calls']

    def test_imports_one_identity_sets_up_notary_and_cleans_after_build(self):
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.assert_cleaned()
        commands = [(call[0], call[1] if len(call) > 1 else '') for call in calls]
        self.assertLess(commands.index(('security', 'import')), commands.index(('xcrun', 'notarytool')))
        self.assertLess(commands.index(('xcrun', 'notarytool')), commands.index(('build', '')))
        self.assertIn(('security', 'set-key-partition-list'), commands)
        for field in ('POMODOIST_MACOS_CERTIFICATE_PASSWORD', 'ASC_PRIVATE_KEY_BASE64'):
            self.assertNotIn(self.env[field], result.stdout + result.stderr)

    def test_missing_credentials_stop_before_keychain_or_build(self):
        fields = [name for name in self.env if name.startswith(('ASC_', 'POMODOIST_MACOS_'))]
        for field in fields:
            with self.subTest(field=field):
                original = self.env.pop(field)
                result = self.run_signing()
                self.env[field] = original
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn(field, result.stderr)
                self.assertEqual(self.assert_cleaned(), [])

    def test_failed_import_identity_or_notary_cleans_and_never_builds(self):
        for failure in ('TEST_IMPORT_FAILURE', 'TEST_MISSING_IDENTITY', 'TEST_NOTARY_FAILURE'):
            with self.subTest(failure=failure):
                self.env[failure] = '1'
                result = self.run_signing()
                self.env.pop(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(call[0] == 'build' for call in self.assert_cleaned()))

    def test_build_failure_is_preserved_after_cleanup(self):
        self.env['TEST_BUILD_STATUS'] = '42'
        result = self.run_signing()
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assert_cleaned()

    def test_build_preserves_original_umask_while_credentials_are_private(self):
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.state.read_text())['build_umask'], 0o022)
        self.assert_cleaned()


if __name__ == '__main__':
    unittest.main()
