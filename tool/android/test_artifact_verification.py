"""Exercise the verifier with command-line SDK doubles, including negative cases."""
import base64
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CERT = b'certificate fixture, not an actual X.509 certificate'
OTHER_CERT = b'a different certificate fixture'
SHA = hashlib.sha256(CERT).hexdigest().upper()


def pem(certificate):
    return ('-----BEGIN CERTIFICATE-----\n'
            + base64.b64encode(certificate).decode()
            + '\n-----END CERTIFICATE-----')


class ArtifactVerificationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'tool/android').mkdir(parents=True)
        shutil.copy(ROOT / 'tool/android/verify_artifacts.sh', self.root / 'tool/android')
        for name in ('flutter-apk/app-release.apk', 'bundle/release/app-release.aab'):
            path = self.root / 'build/app/outputs' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture, not a real signed artifact')
        self.tools = self.root / 'sdk/build-tools/36.0.0'
        self.tools.mkdir(parents=True)
        self.command('apksigner', "echo 'Signer #1 certificate DN: CN=Release'; cat <<'CERT'\n" + pem(CERT) + "\nCERT")
        self.command('aapt', "echo \"package: name='com.finchforge.pomodoist' versionCode='94'\"")
        self.command('jarsigner', "echo 'jar verified.'")
        self.command('keytool', "cat <<'CERT'\n" + pem(CERT) + "\nCERT")
        self.env = os.environ | {'ANDROID_HOME': str(self.root / 'sdk'), 'PATH': str(self.tools) + os.pathsep + os.environ['PATH']}
        self.env.pop('ANDROID_SIGNING_CERT_SHA256', None)

    def command(self, name, body):
        path = self.tools / name
        path.write_text('#!/usr/bin/env bash\nset -e\n' + body + '\n')
        path.chmod(0o755)

    def verify(self):
        return subprocess.run(['bash', 'tool/android/verify_artifacts.sh'], cwd=self.root, env=self.env, capture_output=True, text=True)

    def test_matching_release_certificate(self):
        self.env['ANDROID_SIGNING_CERT_SHA256'] = ':'.join(SHA[i:i + 2].lower() for i in range(0, 64, 2))
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fingerprints_do_not_depend_on_sdk_certificate_labels(self):
        # New SDKs can label signers by SDK range rather than "Signer #1".
        self.command('apksigner', "echo 'Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate DN: CN=Release'; cat <<'CERT'\n" + pem(CERT) + "\nCERT")
        self.command('keytool', "echo 'Signer #1:'; echo 'Certificate #1:'; cat <<'CERT'\n" + pem(CERT) + "\nCERT")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_missing_certificate_even_with_a_matching_text_digest(self):
        self.command('keytool', "echo 'SHA256: " + SHA + "'")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_multiple_distinct_signing_certificates(self):
        self.command('apksigner', "cat <<'CERT'\n" + pem(CERT) + '\n' + pem(OTHER_CERT) + "\nCERT")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_repeated_identical_certificate_for_sdk_ranges_is_allowed(self):
        self.command('apksigner', "cat <<'CERT'\n" + pem(CERT) + '\n' + pem(CERT) + "\nCERT")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_debug_certificate(self):
        self.command('apksigner', "echo 'Signer #1 certificate DN: CN=Android Debug'")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_unsigned_bundle_even_if_jarsigner_exits_zero(self):
        self.command('jarsigner', "echo 'jar is unsigned.'")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_unsigned_entries_in_partly_signed_bundle(self):
        self.command('jarsigner', "echo 'jar verified.'; echo 'This jar contains unsigned entries.'")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_wrong_apk_identity(self):
        self.command('aapt', "echo \"package: name='com.example.pomodoist' versionCode='94'\"")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_debuggable_apk(self):
        self.command('aapt', "echo \"package: name='com.finchforge.pomodoist' versionCode='94'\"; echo application-debuggable")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_different_apk_and_aab_certificates(self):
        self.command('keytool', "cat <<'CERT'\n" + pem(OTHER_CERT) + "\nCERT")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_unexpected_production_certificate(self):
        self.env['ANDROID_SIGNING_CERT_SHA256'] = 'B' * 64
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_broken_apk_signature(self):
        self.command('apksigner', 'exit 1')
        self.assertNotEqual(self.verify().returncode, 0)


if __name__ == '__main__':
    unittest.main()
