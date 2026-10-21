"""Shared, explicit source and timing contract for Pomo exports."""
import hashlib
import json
from pathlib import Path

SIZE = 384
FPS = 24
SAMPLES = 16
SOURCE = 'pomo_3_0_2_all_animations_linked.blend'
# First/last/still are Blender frame numbers, not zero-based PNG indices.
CLIPS = {
    'Greeting': ('01 | Greeting', 1, 72, 28, SOURCE),
    'Happy': ('02 | Happy', 1, 72, 20, SOURCE),
    'Surprised': ('03 | Surprised', 1, 72, 12, SOURCE),
    'Sad': ('04 | Sad', 8, 29, 29, SOURCE),
    'Calm': ('06 | Calm', 1, 240, 58, SOURCE),
    'Focus': ('10 | Thinking reference', 1, 144, 49, SOURCE),
    'Rest': ('08 | Rest', 1, 96, 25, SOURCE),
    'Tired': ('09 | Tired', 1, 96, 25, SOURCE),
}


def clip_metadata(name):
    scene, first, last, still, source = CLIPS[name]
    count = last - first + 1
    duration = 0 if count == 1 else 900 if name == 'Sad' else round(count * 1000 / FPS)
    return dict(source=source, scene=scene, firstFrame=first, lastFrame=last,
                stillFrame=still, sampledFrames=1, durationMs=duration,
                size=SIZE, fps=FPS, renderSamples=SAMPLES, exportVersion=2)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare_output(out, metadata):
    """Resume only an export from exactly the same source and settings."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    marker = out / 'export.json'
    if marker.exists():
        if json.loads(marker.read_text()) != metadata:
            raise ValueError(f'{out}: export source/settings changed; use a fresh directory')
    elif any(out.glob('*.png')):
        raise ValueError(f'{out}: PNGs have no source provenance; use a fresh directory')
    else:
        marker.write_text(json.dumps(metadata, indent=2) + '\n')


def read_export(out, name):
    metadata = json.loads((Path(out) / 'export.json').read_text())
    for key, value in clip_metadata(name).items():
        if metadata.get(key) != value:
            raise ValueError(f'{name}: incorrect export {key}')
    source = Path(metadata['sourcePath'])
    if source.name != metadata['source'] or sha256(source) != metadata['sourceSha256']:
        raise ValueError(f'{name}: Blender source has changed since rendering')
    expected = [Path(out) / f'{i:03}.png' for i in range(metadata['sampledFrames'])]
    if sorted(Path(out).glob('*.png')) != expected:
        raise ValueError(f'{name}: missing or unexpected rendered frames')
    return metadata, expected
