"""Contracts for the isolated F-Droid dependency manifest."""
import re
from pathlib import Path
import unittest

from prepare_fdroid import fdroid_lock, fdroid_pubspec, patch_purchase_source

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'apps/flutter'


class FDroidDependenciesTest(unittest.TestCase):
    def test_fdroid_manifest_uses_local_purchase_adapter_and_source_sqlite(self):
        manifest = fdroid_pubspec((APP / 'pubspec.yaml').read_text())
        self.assertIn('    path: third_party/fdroid/in_app_purchase', manifest)
        self.assertNotIn('in_app_purchase: ^', manifest)
        self.assertIn('      path: third_party/fdroid/sqlite/sqlite3.c', manifest)
        self.assertIn('    path: third_party/fdroid/thermion_flutter', manifest)
        self.assertIn('      skip_native_build: true', manifest)

    def test_fdroid_lock_removes_only_the_native_play_plugin_and_repoints_purchase(self):
        original = (APP / 'pubspec.lock').read_text()
        updated, _ = fdroid_lock(original)
        self.assertNotIn('in_app_purchase_android:', updated)
        self.assertRegex(updated, r'in_app_purchase:\n(?:.*\n){4}    source: path')
        # Compare all other dependency entries, including their hashes.
        def other_packages(lock):
            return re.sub(
                r'^  (?:in_app_purchase(?:_android)?|thermion_flutter):\n(?:^    .*\n)+', '', lock,
                flags=re.MULTILINE,
            )
        self.assertEqual(other_packages(updated), other_packages(original))

    def test_patch_keeps_storekit_and_rejects_native_android_purchases(self):
        manifest = (
            '    platforms:\n      android:\n'
            '        default_package: in_app_purchase_android\n'
            '      ios:\n        default_package: in_app_purchase_storekit\n'
            'dependencies:\n  in_app_purchase_android: ^0.5.0\n'
        )
        source = (
            "import 'package:in_app_purchase_android/in_app_purchase_android.dart';\n"
            '      InAppPurchaseAndroidPlatform.registerPlatform();\n'
            '      InAppPurchaseStoreKitPlatform.registerPlatform();\n'
        )
        standalone_manifest, standalone_source = patch_purchase_source(manifest, source)
        self.assertNotIn('in_app_purchase_android', standalone_manifest)
        self.assertIn('default_package: in_app_purchase_storekit', standalone_manifest)
        self.assertNotIn('InAppPurchaseAndroidPlatform', standalone_source)
        self.assertIn('throw UnsupportedError(', standalone_source)
        self.assertIn('InAppPurchaseStoreKitPlatform.registerPlatform();', standalone_source)
