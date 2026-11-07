import json
from pathlib import Path
import tempfile
import unittest

import store_screenshots


class DeterministicArtifactsTest(unittest.TestCase):
    def test_approved_device_decks_preserve_meaning_and_order(self):
        expected = {
            'iphone': ['hero', 'focus', 'calendar', 'timeline', 'priority', 'kanban', 'voice', 'habits', 'search', 'reports'],
            'mac': ['hero', 'focus', 'calendar', 'priority', 'voice', 'kanban', 'timeline', 'habits', 'search', 'reports'],
            'ipad': ['hero', 'focus', 'customization', 'timeline', 'kanban', 'priority', 'voice', 'search', 'projects', 'reports'],
        }
        for device, meanings in expected.items():
            layouts = store_screenshots.CONFIG['decks'][device]
            actual = [layout.split('=')[-1] if '?' in layout else Path(layout).stem
                      for _, layout in layouts]
            self.assertEqual(actual, meanings, device)
            template = store_screenshots.TOOL / 'templates' / store_screenshots.CONFIG['devices'][device]['template'] / 'hero.html'
            self.assertIn('Turn thoughts', template.read_text())
            if device != 'ipad':
                self.assertIn('pomo-greeting', template.read_text())
                self.assertIn('voice-calendar-pomodoro', template.read_text())

    def test_original_marketing_copy_covers_every_shipping_language(self):
        copy = json.loads((store_screenshots.TOOL / 'store-cover-copy.json').read_text())
        self.assertEqual(set(copy['locales']), set(store_screenshots.CONFIG['locales']))
        self.assertEqual(copy['source'], copy['locales']['en-US'])
        for locale, values in copy['locales'].items():
            self.assertEqual(len(values), len(copy['source']), locale)
            self.assertTrue(all(value.strip() for value in values), locale)

    def test_repeat_check_rejects_changed_pixels_and_provenance(self):
        first = {'results': [{'file': 'iphone/en-US/01-today.png', 'sha256': 'one'}]}
        store_screenshots.compare(first, json.loads(json.dumps(first)))
        second = {'results': [{'file': 'iphone/en-US/01-today.png', 'sha256': 'two'}]}
        with self.assertRaisesRegex(AssertionError, '01-today.png'):
            store_screenshots.compare(first, second)

    def test_repeat_check_names_source_edits_during_capture(self):
        first = {'results': [], 'sourceHashes': {'lib/screen.dart': 'before'}}
        second = {'results': [], 'sourceHashes': {'lib/screen.dart': 'after'}}
        with self.assertRaisesRegex(AssertionError, 'lib/screen.dart'):
            store_screenshots.compare(first, second)

    def test_archive_does_not_depend_on_source_file_mtime(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            image = output / 'iphone/en-US/01-today.png'
            image.parent.mkdir(parents=True)
            image.write_bytes(b'pixel fixture')
            manifest = {'results': [{'file': 'iphone/en-US/01-today.png', 'locale': 'en-US'}]}
            (output / 'manifest.json').write_text(json.dumps(manifest))
            store_screenshots.package(output, manifest)
            first = (output / 'covers.zip').read_bytes()
            import os
            os.utime(image, (1000000000, 1000000000))
            store_screenshots.package(output, manifest)
            self.assertEqual(first, (output / 'covers.zip').read_bytes())
