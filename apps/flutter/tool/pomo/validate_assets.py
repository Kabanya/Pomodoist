"""Asset contract validation; no application UI or visual acceptance check."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops
from export_config import SIZE, clip_metadata, read_export, sha256

root = Path(__file__).resolve().parents[2] / 'assets/pomo'
manifest = json.loads((root / 'manifest.json').read_text())
required = {'calm', 'focus', 'rest', 'tired', 'greeting', 'happy', 'sad', 'surprised'}
assert required <= manifest['clips'].keys(), 'Missing emotion assets'
assert (manifest['size'], manifest['fps']) == (SIZE, 24)
source_hashes = {}
for name, clip in manifest['clips'].items():
    with Image.open(root / clip['still']) as image:
        assert image.size == (SIZE, SIZE) and image.mode == 'RGBA', name
        assert image.getextrema()[3][0] == 0 and image.getextrema()[3][1] > 0, name
    if name in required:
        expected = clip_metadata(name.title())
        assert clip['still'] == f'{name}-still.webp'
        for field in ('source', 'scene', 'firstFrame', 'lastFrame', 'stillFrame', 'sampledFrames', 'durationMs'):
            assert clip[field] == expected[field], (name, field)
        source = root.parent / 'branding/mascot' / clip['source']
        assert len(clip['sourceSha256']) == 64 and all(c in '0123456789abcdef' for c in clip['sourceSha256']), name
        # Blender sources are local authoring artifacts, not required in CI.
        if source.exists():
            if clip['source'] not in source_hashes:
                source_hashes[clip['source']] = sha256(source)
            assert clip['sourceSha256'] == source_hashes[clip['source']], name
        if len(sys.argv) > 1:
            metadata, paths = read_export(Path(sys.argv[1]) / name.title(), name.title())
            assert metadata['sourceSha256'] == clip['sourceSha256'], name
            with Image.open(paths[0]) as rendered, Image.open(root / clip['still']) as still:
                # Transparent RGB is irrelevant; compare visible RGB and alpha.
                a, b = rendered.convert('RGBA'), still.convert('RGBA')
                assert ImageChops.difference(a.getchannel('A'), b.getchannel('A')).getbbox() is None, name
                bg = Image.new('RGBA', a.size)
                a = Image.alpha_composite(bg, a).convert('RGB')
                b = Image.alpha_composite(bg, b).convert('RGB')
                assert ImageChops.difference(a, b).getbbox() is None, name
    print(name, clip['still'], 'OK')
