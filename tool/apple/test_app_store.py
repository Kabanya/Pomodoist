import hashlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import app_store


class ScreenshotCheckTest(unittest.TestCase):
    def test_requires_every_locale_and_rejects_reused_english_png(self):
        # Header for the local preflight. The asc validator handles PNG decoding.
        png = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' + bytes(8) + b'\x08\x02'
        displays = (('IOS', 'iphone', 'APP_IPHONE_61', 1),)
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(app_store, 'DISPLAYS', displays), \
                patch.object(app_store, 'LOCALES', {'en': 'en-US', 'ru': 'ru'}), \
                patch.object(app_store, 'asc') as validate:
            root = Path(tmp)
            en = root / 'iphone/en-US/01-focus.png'
            en.parent.mkdir(parents=True)
            en.write_bytes(png)

            with self.assertRaisesRegex(ValueError, 'iphone/ru: expected 1'):
                app_store.check_screenshots(root)

            ru = root / 'iphone/ru/01-focus.png'
            ru.parent.mkdir()
            ru.write_bytes(png)
            with self.assertRaisesRegex(ValueError, 'duplicates'):
                app_store.check_screenshots(root)
            validate.assert_not_called()

            ru.write_bytes(png + b'different')
            app_store.check_screenshots(root)
            self.assertEqual(validate.call_count, 2)

    def test_upload_preserves_english_and_rejects_conflicting_localized_set(self):
        def uploaded(data):
            return {'attributes': {
                'sourceFileChecksum': hashlib.md5(data).hexdigest(),
                'assetDeliveryState': {'state': 'COMPLETE'},
            }}

        display = 'APP_IPHONE_61'
        displays = (('IOS', 'iphone', display, 2),)
        locales = {'en': 'en-US', 'ru': 'ru'}
        remote = {'IOS': {
            'en-US': {display: [uploaded(b'one'), uploaded(b'two')]},
            'ru': {display: [uploaded(b'first')]},
        }}
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(app_store, 'DISPLAYS', displays), \
                patch.object(app_store, 'LOCALES', locales):
            args = SimpleNamespace(screenshots=Path(tmp))
            folder = args.screenshots / 'iphone/ru'
            folder.mkdir(parents=True)
            (folder / '01-focus.png').write_bytes(b'first')
            (folder / '02-planner.png').write_bytes(b'second')

            commands = list(app_store.screenshot_commands(args, (), remote))
            self.assertEqual(len(commands), 1)
            self.assertIn('ru', commands[0])
            self.assertIn('--skip-existing', commands[0])

            remote['IOS']['ru'][display] = [uploaded(b'second')]
            with self.assertRaisesRegex(ValueError, 'existing screenshots differ'):
                list(app_store.screenshot_commands(args, (), remote))


if __name__ == '__main__':
    unittest.main()
