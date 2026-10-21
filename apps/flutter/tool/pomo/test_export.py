"""Regression checks for provenance and partial exports, without Blender."""
import json
import tempfile
import unittest
from pathlib import Path
from PIL import Image
from encode import encode
from export_config import clip_metadata, prepare_output, read_export, sha256


class ExportTest(unittest.TestCase):
    def test_resume_rejects_unverified_or_changed_source(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            (out / '000.png').write_bytes(b'old frame')
            with self.assertRaisesRegex(ValueError, 'no source provenance'):
                prepare_output(out, {'sourceSha256': 'old'})
            (out / '000.png').unlink()
            prepare_output(out, {'sourceSha256': 'old'})
            prepare_output(out, {'sourceSha256': 'old'})
            with self.assertRaisesRegex(ValueError, 'source/settings changed'):
                prepare_output(out, {'sourceSha256': 'new'})

    def test_partial_still_encoding_preserves_other_assets_and_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            metadata = clip_metadata('Rest')
            blend = root / metadata['source']
            blend.write_bytes(b'synthetic source for provenance regression')
            metadata.update(sourcePath=str(blend), sourceSha256=sha256(blend))
            out, dest = root / 'Rest', root / 'assets'
            prepare_output(out, metadata)
            for i in range(1):
                with Image.new('RGBA', (384, 384)) as frame:
                    frame.paste((255, 0, 0, 255) if i < 48 else (0, 0, 255, 255), (100, 100, 200, 200))
                    frame.save(out / f'{i:03}.png')
            dest.mkdir()
            old = {'source': 'original.blend', 'size': 384, 'fps': 24, 'clips': {'calm': {'still': 'untouched.webp'}}}
            (dest / 'manifest.json').write_text(json.dumps(old))
            (dest / 'untouched.webp').write_bytes(b'untouched')
            encode(root, dest, ['Rest'])
            updated = json.loads((dest / 'manifest.json').read_text())
            self.assertEqual(updated['source'], old['source'])
            self.assertEqual(updated['clips']['calm'], old['clips']['calm'])
            self.assertEqual((dest / 'untouched.webp').read_bytes(), b'untouched')
            self.assertFalse((dest / 'rest.webp').exists())
            self.assertNotIn('animation', updated['clips']['rest'])
            self.assertEqual(updated['clips']['rest']['sourceSha256'], metadata['sourceSha256'])
            with Image.open(dest / 'rest-still.webp') as still:
                self.assertEqual(still.getpixel((150, 150)), (255, 0, 0, 255))
            last = out / '000.png'
            saved = last.read_bytes()
            last.unlink()
            with self.assertRaisesRegex(ValueError, 'missing or unexpected'):
                read_export(out, 'Rest')
            last.write_bytes(saved)
            blend.write_bytes(b'changed source')
            with self.assertRaisesRegex(ValueError, 'source has changed'):
                read_export(out, 'Rest')


if __name__ == '__main__':
    unittest.main()
