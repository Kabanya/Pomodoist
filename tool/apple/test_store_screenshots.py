import json
from pathlib import Path
import tempfile
import unittest

import store_screenshots


class DeterministicArtifactsTest(unittest.TestCase):
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
