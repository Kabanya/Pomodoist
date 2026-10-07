"""Run the packaging script with doubles for Apple's signing/build services."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = 'Developer ID Application: FinchForge, LLC (4VK836929S)'


class MacosBuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / 'release'
        shutil.copytree(ROOT / 'tool/macos', self.root / 'tool/macos')
        (self.root / 'tool/link-build.sh').write_text('#!/bin/bash\nexit 0\n')
        (self.root / 'tool/link-build.sh').chmod(0o755)
        entry = self.root / 'apps/flutter/lib/main.dart'
        entry.parent.mkdir(parents=True)
        entry.touch()
        (self.root / '.env.testflight').touch()
        self.app = self.root / 'apps/flutter/build/macos/Build/Products/Release-production/Pomodoist.app'
        for name in ('MacOS/Pomodoist', 'Frameworks/App.framework/App',
                     'Frameworks/sqlite3.framework/sqlite3',
                     'Frameworks/libexample.dylib', 'PlugIns/PomodoistFocusWidgetExtension.appex/Contents/MacOS/Widget'):
            path = self.app / 'Contents' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.finchforge.pomodoist',
            'CFBundleExecutable': 'Pomodoist',
        }))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = os.environ | {
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'POMODOIST_FLUTTER': str(self.bin / 'flutter'),
            'POMODOIST_MACOS_SIGNING_IDENTITY': IDENTITY,
            'POMODOIST_MACOS_NOTARY_PROFILE': 'test-notary',
            'TEST_APP': str(self.app),
            'TEST_NOTARY_STATUS': 'Accepted',
        }
        self.command('flutter', 'touch "$TEST_APP/built"')
        self.command('xcodebuild', "echo '    PRODUCT_BUNDLE_IDENTIFIER = com.finchforge.pomodoist'")
        self.command('security', 'printf \'1) ABC "%s"\\n\' "$POMODOIST_MACOS_SIGNING_IDENTITY"')
        self.command('lipo', "echo 'x86_64 arm64'")
        self.command('file', '''
case "${@: -1}" in
  */Pomodoist|*/App|*/sqlite3|*.dylib) echo 'Mach-O universal binary' ;;
  *) echo 'data' ;;
esac
''')
        self.command('codesign', '''
target="${@: -1}"
if [[ "$1" == -d ]]; then
  echo '<key>com.apple.security.cs.allow-jit</key><true/>'
elif [[ "$1" == --verify ]]; then
  exit 0
else
  [[ "$*" == *--timestamp* ]] || exit 1
  [[ "$target" == *.dmg || "$*" == *'--options runtime'* ]] || exit 1
  if [[ -d "$target" ]]; then touch "$target/signed"; else touch "$target.signed"; fi
fi
''')
        self.command('hdiutil', '''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -srcfolder ]]; then source="$2"; shift; fi
  output="$1"; shift
done
app="$source/Pomodoist.app"
test -f "$app/signed"
test -f "$app/Contents/Frameworks/App.framework/signed"
test -f "$app/Contents/Frameworks/sqlite3.framework/signed"
test -f "$app/Contents/Frameworks/libexample.dylib.signed"
test ! -d "$app/Contents/PlugIns/PomodoistFocusWidgetExtension.appex"
test -L "$source/Applications"
echo 'signed application image' > "$output"
''')
        self.command('xcrun', '''
if [[ "$1 $2" == 'notarytool submit' ]]; then
  printf '<plist version="1.0"><dict><key>id</key><string>test-submission</string></dict></plist>\\n'
elif [[ "$1 $2" == 'notarytool wait' ]]; then
  [[ "${TEST_NOTARY_WAIT_FAILURE:-0}" == 0 ]] || exit 138
  printf '<plist version="1.0"><dict><key>id</key><string>test-submission</string><key>status</key><string>%s</string></dict></plist>\\n' "$TEST_NOTARY_STATUS"
elif [[ "$1 $2" == 'stapler staple' ]]; then
  echo 'stapled ticket' >> "$3"
fi
''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -eu\n' + body + '\n')
        path.chmod(0o755)

    def build(self):
        return subprocess.run(['bash', 'tool/macos/build.sh', '--output', 'release'], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_missing_signing_credentials_stop_before_build(self):
        for field in ('POMODOIST_MACOS_SIGNING_IDENTITY', 'POMODOIST_MACOS_NOTARY_PROFILE'):
            with self.subTest(field=field):
                original = self.env.pop(field)
                result = self.build()
                self.env[field] = original
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.app / 'built').exists())

    @unittest.skipUnless(Path('/usr/libexec/PlistBuddy').is_file(), 'macOS packaging check')
    def test_signed_contents_are_packaged_and_checksum_includes_ticket(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.output
        self.assertIn('stapled ticket', (output / 'Pomodoist-macOS.dmg').read_text())
        result = subprocess.run(['shasum', '-a', '256', '-c', 'Pomodoist-macOS.dmg.sha256'],
                                cwd=output, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(Path('/usr/libexec/PlistBuddy').is_file(), 'macOS packaging check')
    def test_rejected_notarization_does_not_produce_release_checksum(self):
        self.env['TEST_NOTARY_STATUS'] = 'Invalid'
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Notarization status: Invalid', result.stderr)
        self.assertFalse((self.output / 'Pomodoist-macOS.dmg.sha256').exists())

    @unittest.skipUnless(Path('/usr/libexec/PlistBuddy').is_file(), 'macOS packaging check')
    def test_missing_intel_slice_stops_packaging(self):
        self.command('lipo', "echo 'arm64'")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing universal architectures', result.stderr)
        self.assertFalse((self.output / 'Pomodoist-macOS.dmg').exists())

    @unittest.skipUnless(Path('/usr/libexec/PlistBuddy').is_file(), 'macOS packaging check')
    def test_failed_wait_preserves_submission_for_recovery(self):
        self.env['TEST_NOTARY_WAIT_FAILURE'] = '1'
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        receipt_path = self.output / 'notarization-submission.plist'
        self.assertTrue(receipt_path.is_file())
        receipt = plistlib.loads(receipt_path.read_bytes())
        self.assertEqual(receipt['id'], 'test-submission')
        self.assertFalse((self.output / 'Pomodoist-macOS.dmg.sha256').exists())


if __name__ == '__main__':
    unittest.main()
