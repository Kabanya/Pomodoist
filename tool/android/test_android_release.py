"""Executable Android packaging contracts; no Flutter or third-party modules needed."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = '{http://schemas.android.com/apk/res/android}'
FLAVOR_MANIFESTS = {
    'development': 'apps/flutter/android/app/src/development/AndroidManifest.xml',
    'staging': 'apps/flutter/android/app/src/staging/AndroidManifest.xml',
    'production': 'apps/flutter/android/app/src/production/AndroidManifest.xml',
}
FLAVOR_GETTERS = ('displayName', 'applicationId', 'urlScheme')
CALLBACK_HOSTS = {'login-callback', 'captcha-callback', 'google-calendar-connected', 'focus', 'purchase-success'}


def dart_flavor_table():
    """Read the flavor identity table out of the Dart enum that declares it."""
    text = (ROOT / 'apps/flutter/lib/domain/models/app_flavor.dart').read_text()
    table = {}
    for getter in FLAVOR_GETTERS:
        block = text.split(f'get {getter}')[1].split('};')[0]
        table[getter] = dict(re.findall(r"AppFlavor\.(\w+) => '([^']+)'", block))
    return table


class AndroidManifestTests(unittest.TestCase):
    def setUp(self):
        self.manifest = ET.parse(ROOT / 'apps/flutter/android/app/src/main/AndroidManifest.xml').getroot()

    def test_permissions_cover_existing_native_features(self):
        permissions = {item.get(ANDROID + 'name') for item in self.manifest.findall('uses-permission')}
        required = {'INTERNET', 'RECORD_AUDIO', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM'}
        self.assertTrue({'android.permission.' + item for item in required} <= permissions)
        self.assertNotIn('android.permission.USE_EXACT_ALARM', permissions)
        self.assertNotIn('android.permission.MANAGE_EXTERNAL_STORAGE', permissions)

    def test_all_native_callback_hosts_are_registered(self):
        metadata = {item.get(ANDROID + 'name'): item.get(ANDROID + 'value') for item in self.manifest.findall('application/activity/meta-data')}
        self.assertEqual(metadata.get('flutter_deeplinking_enabled'), 'false')

    def test_shared_manifest_registers_no_deep_link_scheme(self):
        # Every scheme lives in a flavor manifest. A scheme in the shared
        # manifest would register all three flavors for the same links.
        data = self.manifest.findall('application/activity/intent-filter/data')
        self.assertEqual([item.get(ANDROID + 'scheme') for item in data], [None] * len(data))

    def test_each_flavor_registers_the_callback_hosts_under_its_own_scheme(self):
        for flavor, relative in FLAVOR_MANIFESTS.items():
            with self.subTest(flavor=flavor):
                manifest = ET.parse(ROOT / relative).getroot()
                data = manifest.findall('application/activity/intent-filter/data')
                self.assertEqual({item.get(ANDROID + 'host') for item in data}, CALLBACK_HOSTS)
                # The scheme is the flavor's manifestPlaceholder, which
                # test_flavors_match_the_dart_flavor_table pins to AppFlavor.
                self.assertEqual({item.get(ANDROID + 'scheme') for item in data}, {'${urlScheme}'})

    def test_reminders_survive_reboot_and_app_update(self):
        receivers = {item.get(ANDROID + 'name'): item for item in self.manifest.findall('application/receiver')}
        prefix = 'com.dexterous.flutterlocalnotifications.'
        self.assertIn(prefix + 'ScheduledNotificationReceiver', receivers)
        self.assertIn(prefix + 'ScheduledNotificationBootReceiver', receivers)
        for item in receivers.values():
            self.assertEqual(item.get(ANDROID + 'exported'), 'false')

    def test_production_does_not_backup_auth_or_allow_cleartext(self):
        app = self.manifest.find('application')
        self.assertEqual(app.get(ANDROID + 'allowBackup'), 'false')
        self.assertEqual(app.get(ANDROID + 'usesCleartextTraffic'), 'false')

    def test_all_backup_domains_are_excluded_from_transfer(self):
        rules = ET.parse(ROOT / 'apps/flutter/android/app/src/main/res/xml/data_extraction_rules.xml').getroot()
        required = {'root', 'file', 'database', 'sharedpref', 'external', 'device_root', 'device_file', 'device_database', 'device_sharedpref'}
        for mode in ('cloud-backup', 'device-transfer'):
            excluded = {item.get('domain') for item in rules.findall(mode + '/exclude') if item.get('path') == '.'}
            self.assertEqual(excluded, required)

    def test_only_debug_builds_opt_in_to_cleartext(self):
        app = ET.parse(ROOT / 'apps/flutter/android/app/src/debug/AndroidManifest.xml').getroot().find('application')
        self.assertEqual(app.get(ANDROID + 'usesCleartextTraffic'), 'true')
        self.assertEqual(self.manifest.find('application').get(ANDROID + 'usesCleartextTraffic'), 'false')

    def test_microphone_is_optional_for_tablets(self):
        features = {item.get(ANDROID + 'name'): item for item in self.manifest.findall('uses-feature')}
        self.assertIn('android.hardware.microphone', features)
        self.assertEqual(features['android.hardware.microphone'].get(ANDROID + 'required'), 'false')


class AndroidGradleTests(unittest.TestCase):
    def test_production_identity_and_desugaring(self):
        text = (ROOT / 'apps/flutter/android/app/build.gradle.kts').read_text()
        self.assertNotIn('com.example.', text)
        self.assertIn('applicationId = "com.finchforge.pomodoist"', text)
        self.assertIn('namespace = "com.finchforge.pomodoist"', text)
        self.assertIn('isCoreLibraryDesugaringEnabled = true', text)
        self.assertIn('com.android.tools:desugar_jdk_libs:2.1.4', text)

    def test_release_never_falls_back_to_debug_signing(self):
        text = (ROOT / 'apps/flutter/android/app/build.gradle.kts').read_text()
        self.assertNotIn('signingConfigs.getByName("debug")', text)
        self.assertIn('signingConfigs.getByName("release")', text)
        self.assertIn('Android Debug', text)
        self.assertIn('androiddebugkey', text)
        self.assertIn('validateReleaseSigning', text)

    def test_flavors_match_the_dart_flavor_table(self):
        text = (ROOT / 'apps/flutter/android/app/build.gradle.kts').read_text()
        table = dart_flavor_table()
        self.assertIn('flavorDimensions += "app"', text)
        for flavor in FLAVOR_MANIFESTS:
            with self.subTest(flavor=flavor):
                self.assertIn(f'create("{flavor}")', text)
                self.assertIn(f'applicationId = "{table["applicationId"][flavor]}"', text)
                self.assertIn(f'manifestPlaceholders["appLabel"] = "{table["displayName"][flavor]}"', text)
                self.assertIn(f'manifestPlaceholders["urlScheme"] = "{table["urlScheme"][flavor]}"', text)

    def test_only_the_shipped_flavor_keeps_the_release_version_name(self):
        # Staging and development must be distinguishable in settings and logs.
        text = (ROOT / 'apps/flutter/android/app/build.gradle.kts').read_text()
        self.assertIn('versionNameSuffix = "-dev"', text)
        self.assertIn('versionNameSuffix = "-stg"', text)
        production = text.split('create("production")')[1].split('signingConfigs')[0]
        self.assertNotIn('versionNameSuffix', production)


class ReleaseConfigTests(unittest.TestCase):
    def validate(self, config):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.json'
            path.write_text(json.dumps(config))
            return subprocess.run([sys.executable, str(ROOT / 'tool/android/validate_config.py'), str(path)], capture_output=True, text=True)

    def valid_config(self):
        return {'POMODOIST_ENVIRONMENT': 'production', 'WEB_APP_URL': 'https://app.pomodoist.com', 'POMODOIST_REGISTRATION_URL': 'https://app.pomodoist.com/auth/challenge', 'TURNSTILE_SITE_KEY': '0x4-test-site-key', 'SENTRY_DSN': '', 'POMODOIST_BILLING_CHANNEL': 'storekit'}

    def test_accepts_public_production_config(self):
        result = self.validate(self.valid_config())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_development_and_non_https_endpoints(self):
        for field, value in [('POMODOIST_ENVIRONMENT', 'local'), ('WEB_APP_URL', 'http://app.pomodoist.com'), ('WEB_APP_URL', 'https://user:password@app.pomodoist.com'), ('POMODOIST_REGISTRATION_URL', 'https://attacker.example/auth/challenge')]:
            with self.subTest(field=field, value=value):
                config = self.valid_config()
                config[field] = value
                self.assertNotEqual(self.validate(config).returncode, 0)

    def test_rejects_secret_or_unknown_dart_defines(self):
        for field in ['SUPABASE_SERVICE_ROLE_KEY', 'OPENAI_API_KEY', 'ANDROID_KEY_PASSWORD', 'GOOGLE_DESKTOP_CLIENT_SECRET', 'UNKNOWN']:
            with self.subTest(field=field):
                config = self.valid_config()
                config[field] = 'must-not-appear-in-diagnostics'
                result = self.validate(config)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('must-not-appear-in-diagnostics', result.stdout + result.stderr)

    def test_rejects_unlocks_test_storekit_and_checkout(self):
        for field, value in [('POMODOIST_DEV_UNLOCK', '1'), ('POMODOIST_LOCAL_STOREKIT', 'true'), ('POMODOIST_BILLING_CHANNEL', 'stripe')]:
            config = self.valid_config()
            config[field] = value
            self.assertNotEqual(self.validate(config).returncode, 0)

    def test_requires_captcha_and_complete_backend_override(self):
        for change in [{'TURNSTILE_SITE_KEY': ''}, {'SUPABASE_URL': 'https://example.supabase.co'}, {'SUPABASE_ANON_KEY': 'sb_publishable_test'}]:
            config = self.valid_config() | change
            self.assertNotEqual(self.validate(config).returncode, 0)

    def test_rejects_privileged_supabase_keys(self):
        import base64
        for role in ['service_role', 'authenticated']:
            payload = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
            config = self.valid_config() | {'SUPABASE_URL': 'https://example.supabase.co', 'SUPABASE_ANON_KEY': 'e30.' + payload + '.signature'}
            self.assertNotEqual(self.validate(config).returncode, 0)

    def test_accepts_public_backend_override(self):
        config = self.valid_config() | {'SUPABASE_URL': 'https://example.supabase.co', 'SUPABASE_ANON_KEY': 'sb_publishable_test'}
        result = self.validate(config)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_duplicate_json_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.json'
            path.write_text('{"POMODOIST_ENVIRONMENT":"production","POMODOIST_ENVIRONMENT":"local"}')
            result = subprocess.run([sys.executable, str(ROOT / 'tool/android/validate_config.py'), str(path)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
