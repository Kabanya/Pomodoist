"""Structural and bounded-error regression checks for compact model packing."""
import gzip
import hashlib
import json
import io
import struct
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from compact_model import compact, package


def fixture():
    values = struct.pack('<6f', .123456, -.234567, 0, .3, .4, .5)
    doc = {
        'asset': {'version': '2.0'},
        'buffers': [{'byteLength': len(values) * 2}],
        'bufferViews': [{'buffer': 0, 'byteOffset': i * len(values), 'byteLength': len(values), 'target': 34962} for i in range(2)],
        'accessors': [{'bufferView': i, 'componentType': 5126, 'count': 2, 'type': 'VEC3', 'min': [0, 0, 0], 'max': [1, 1, 1]} for i in range(2)],
        'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'targets': [{'POSITION': 1}]}]}],
        'skins': [{'joints': [0]}], 'nodes': [{'name': 'rig'}],
        'animations': [{'name': 'focus', 'channels': [], 'samplers': []}],
    }
    data = json.dumps(doc).encode(); data += b' ' * (-len(data) % 4)
    return struct.pack('<IIIII', 0x46546c67, 2, 28 + len(data) + len(values)*2, len(data), 0x4e4f534a) + data + struct.pack('<II', len(values)*2, 0x004e4942) + values * 2


class CompactTest(unittest.TestCase):
    def test_geometry_error_is_bounded_and_rig_and_morphs_survive(self):
        packed, report = compact(fixture())
        size = struct.unpack_from('<I', packed, 12)[0]
        doc = json.loads(packed[20:20+size])
        self.assertEqual(report['viewsAfter'], 1)
        self.assertEqual(doc['skins'], [{'joints': [0]}])
        self.assertEqual(doc['animations'][0]['name'], 'focus')
        self.assertEqual(doc['meshes'][0]['primitives'][0]['targets'], [{'POSITION': 1}])
        self.assertLessEqual(report['maxAttributeError'], .0000051)
        self.assertEqual(struct.unpack_from('<I', packed, 8)[0], len(packed))

    def test_gzip_is_deterministic_and_source_is_unchanged(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root/'source'; source.mkdir()
            raw = fixture(); (source/'pomo.glb').write_bytes(raw)
            (source/'manifest.json').write_text(json.dumps({'source': 'master.blend', 'modelSha256': hashlib.sha256(raw).hexdigest(), 'clips': {'focus': {'durationMs': 6000}}}))
            package(source, root/'one'); package(source, root/'two')
            a = (root/'one/pomo.glb.gz').read_bytes()
            self.assertEqual(a, (root/'two/pomo.glb.gz').read_bytes())
            self.assertEqual(gzip.decompress(a), compact(raw)[0])
            self.assertEqual((source/'pomo.glb').read_bytes(), raw)
            self.assertEqual(json.loads((root/'one/manifest.json').read_text())['clips']['focus']['durationMs'], 6000)

    def test_all_texture_maps_fit_1024_without_upscaling_or_changing_alpha(self):
        raw = fixture()
        json_size = struct.unpack_from('<I', raw, 12)[0]
        doc = json.loads(raw[20:20 + json_size])
        binary = bytearray(raw[28 + json_size:])
        doc['images'] = []
        for name, size in [('body-color', (4096, 2048)),
                           ('body-normal', (2048, 2048)),
                           ('body-roughness', (512, 256))]:
            image = Image.new('RGBA', size, (128, 128, 255, 123))
            out = io.BytesIO()
            image.save(out, format='PNG')
            binary.extend(b'\0' * (-len(binary) % 4))
            doc['images'].append({'name': name, 'mimeType': 'image/png',
                                  'bufferView': len(doc['bufferViews'])})
            doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary),
                                       'byteLength': len(out.getvalue())})
            binary.extend(out.getvalue())
        binary.extend(b'\0' * (-len(binary) % 4))
        doc['buffers'][0]['byteLength'] = len(binary)
        encoded = json.dumps(doc).encode()
        encoded += b' ' * (-len(encoded) % 4)
        raw = (struct.pack('<IIIII', 0x46546c67, 2, 28 + len(encoded) + len(binary),
                           len(encoded), 0x4e4f534a) + encoded +
               struct.pack('<II', len(binary), 0x004e4942) + binary)
        packed, report = compact(raw)
        json_size = struct.unpack_from('<I', packed, 12)[0]
        doc = json.loads(packed[20:20 + json_size])
        for image, expected in zip(doc['images'], [(1024, 512), (1024, 1024), (512, 256)]):
            view = doc['bufferViews'][image['bufferView']]
            offset = 28 + json_size + view['byteOffset']
            with Image.open(io.BytesIO(packed[offset:offset + view['byteLength']])) as decoded:
                self.assertEqual(decoded.size, expected)
                self.assertEqual(decoded.mode, 'RGBA')
                self.assertEqual(decoded.getpixel((0, 0))[3], 123)
        self.assertEqual(report['textureLimits'], {'color': 1024, 'normalAndRoughness': 1024})

    def test_bad_input_is_rejected(self):
        with self.assertRaises(AssertionError):
            compact(b'BAD!' + fixture()[4:])


if __name__ == '__main__':
    unittest.main()
