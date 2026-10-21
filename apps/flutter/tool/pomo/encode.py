"""Encode lossless fallback stills from verified Blender PNG exports.

Usage: python3 encode.py FRAME_ROOT ASSET_DIRECTORY [Focus Rest Tired ...]
"""
import json
import sys
from pathlib import Path
from PIL import Image
from export_config import CLIPS, FPS, SIZE, SOURCE, read_export


def encode(source, dest, names):
    # Verify all requested exports before replacing any assets.
    exports = [(name, *read_export(source / name, name)) for name in names]
    dest.mkdir(parents=True, exist_ok=True)
    manifest_path = dest / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {
        'source': SOURCE, 'size': SIZE, 'fps': FPS, 'clips': {}}
    if (manifest['size'], manifest['fps']) != (SIZE, FPS):
        raise ValueError('Existing manifest uses incompatible dimensions or fps')
    for name, metadata, paths in exports:
        key = name.lower()
        still = f'{key}-still.webp'
        path = paths[0]
        with Image.open(path) as image:
            with image.convert('RGBA') as frame:
                if frame.size != (SIZE, SIZE) or frame.getextrema()[3][0] != 0 or frame.getextrema()[3][1] == 0:
                    raise ValueError(f'{path}: expected visible transparent {SIZE}x{SIZE} image')
                frame.save(dest / still, lossless=True)
        manifest['clips'][key] = {
            'still': still,
            **{field: metadata[field] for field in (
                'source', 'sourceSha256', 'scene', 'firstFrame', 'lastFrame',
                'stillFrame', 'sampledFrames', 'durationMs')},
        }
        print(name, still, 'OK', flush=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    encode(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:] or list(CLIPS))
