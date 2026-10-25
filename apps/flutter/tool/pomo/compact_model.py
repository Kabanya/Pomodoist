"""Quantize geometry, deduplicate buffers and gzip a self-contained Pomo GLB.

Usage: python3 compact_model.py EXPORT_DIRECTORY OUTPUT_DIRECTORY
The decoded model remains standard dense glTF: skins and morphs stay editable.
"""
import gzip
import hashlib
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

STEPS = {'POSITION': 0.00001, 'NORMAL': 1 / 4096, 'TANGENT': 1 / 4096,
         'TEXCOORD_0': 1 / 65536}


def compact(raw):
    magic, version, length = struct.unpack_from('<III', raw)
    assert (magic, version, length) == (0x46546c67, 2, len(raw))
    json_length, tag = struct.unpack_from('<II', raw, 12)
    assert tag == 0x4e4f534a
    doc = json.loads(raw[20:20 + json_length])
    assert not doc.get('extensionsRequired'), 'Handle required extensions explicitly'
    binary = raw[28 + json_length:]
    views, accessors = doc['bufferViews'], doc['accessors']
    assert all('sparse' not in a for a in accessors), 'Metal requires dense morphs'
    chunks = [bytearray(binary[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]) for v in views]
    steps = {}
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            for attrs in [primitive['attributes'], *primitive.get('targets', [])]:
                for semantic, index in attrs.items():
                    if semantic in STEPS:
                        old = steps.setdefault(index, STEPS[semantic])
                        assert old == STEPS[semantic]
    worst = 0.
    for index, step in steps.items():
        a = accessors[index]
        assert a['componentType'] == 5126 and a.get('byteOffset', 0) == 0
        v = views[a['bufferView']]
        assert not v.get('byteStride'), 'Expected separate Blender accessors'
        values = np.frombuffer(chunks[a['bufferView']], dtype='<f4')
        original = values.copy()
        assert np.isfinite(values).all()
        values[:] = np.round(values / step) * step
        values[values == 0] = 0  # Canonicalize negative zero for deduplication.
        error = float(np.max(np.abs(original - values)))
        assert error <= step * .501 + 1e-7
        worst = max(worst, error)
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        values = values.reshape(a['count'], components)
        for bound, fn in [('min', np.min), ('max', np.max)]:
            if bound in a:
                a[bound] = fn(values, axis=0).tolist()
    for image in doc.get('images', []):
        assert image['mimeType'] == 'image/png'
        index = image['bufferView']
        with Image.open(io.BytesIO(chunks[index])) as source:
            # Keep the base color and tangent-space normal maps as real textures.
            limit = 1024
            source.thumbnail((limit, limit), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            source.save(out, format='PNG', optimize=True)
            chunks[index] = out.getvalue()
    used = {a['bufferView'] for a in accessors} | {im['bufferView'] for im in doc.get('images', [])}
    packed, new_views, mapping, identical = bytearray(), [], {}, {}
    for index in sorted(used):
        view = views[index]
        chunk = bytes(chunks[index])
        key = (view.get('target'), view.get('byteStride'), chunk)
        if key not in identical:
            packed.extend(b'\0' * (-len(packed) % 4))
            new_view = {k: v for k, v in view.items() if k not in ('byteOffset', 'byteLength')}
            new_view.update(byteOffset=len(packed), byteLength=len(chunk))
            identical[key] = len(new_views)
            new_views.append(new_view)
            packed.extend(chunk)
        mapping[index] = identical[key]
    for a in accessors:
        a['bufferView'] = mapping[a['bufferView']]
    for im in doc.get('images', []):
        im['bufferView'] = mapping[im['bufferView']]
    packed.extend(b'\0' * (-len(packed) % 4))
    doc['bufferViews'] = new_views
    doc['buffers'] = [{'byteLength': len(packed)}]
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    result = (struct.pack('<III', magic, version, 28 + len(encoded) + len(packed)) +
              struct.pack('<II', len(encoded), 0x4e4f534a) + encoded +
              struct.pack('<II', len(packed), 0x004e4942) + packed)
    return result, {'floatGrid': STEPS, 'maxAttributeError': worst,
                    'textureLimits': {'color': 1024, 'normalAndRoughness': 1024}, 'viewsBefore': len(views), 'viewsAfter': len(new_views)}


def package(source, dest):
    raw = (source / 'pomo.glb').read_bytes()
    manifest = json.loads((source / 'manifest.json').read_text())
    assert hashlib.sha256(raw).hexdigest() == manifest['modelSha256'], 'Export model/manifest mismatch'
    result, report = compact(raw)
    zipped = gzip.compress(result, compresslevel=9, mtime=0)
    assert gzip.decompress(zipped) == result
    manifest.update(version=2, asset='pomo.glb.gz', encoding='gzip',
                    modelSha256=hashlib.sha256(result).hexdigest(),
                    compressedSha256=hashlib.sha256(zipped).hexdigest(),
                    decodedBytes=len(result), compressedBytes=len(zipped),
                    optimization=report)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'pomo.glb.gz').write_bytes(zipped)
    (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'original': len(raw), 'decoded': len(result), 'compressed': len(zipped), **report}), flush=True)


if __name__ == '__main__':
    package(Path(sys.argv[1]), Path(sys.argv[2]))
