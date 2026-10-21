"""Blender --background SOURCE --python-exit-code 1 --python render.py -- OUTPUT CLIP [--metal]."""
import sys
from pathlib import Path
import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_config import FPS, SIZE, SAMPLES, clip_metadata, prepare_output, sha256

args = sys.argv[sys.argv.index('--') + 1:]
out, name = Path(args[0]).resolve(), args[1]
metadata = clip_metadata(name)
source = Path(bpy.data.filepath).resolve()
if source.name != metadata['source']:
    raise ValueError(f"{name} requires {metadata['source']}, received {source.name}")
metadata.update(sourcePath=str(source), sourceSha256=sha256(source))
prepare_output(out, metadata)
s = bpy.data.scenes[metadata['scene']]
bpy.context.window.scene = s
for obj in s.objects:
    if obj.type == 'MESH' and not obj.get('pomo_source_object', '').startswith('Pomo'):
        obj.hide_render = True
s.render.engine = 'CYCLES'
s.cycles.samples = SAMPLES
s.cycles.use_denoising = True
s.render.use_persistent_data = True
if '--metal' in args:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'METAL'
    if not any(d.use for d in prefs.devices):
        raise RuntimeError('No Metal rendering device available')
    s.cycles.device = 'GPU'
s.render.film_transparent = True
s.render.fps, s.render.fps_base = FPS, 1
s.render.resolution_x = s.render.resolution_y = SIZE
s.render.resolution_percentage = 100
s.render.image_settings.file_format = 'PNG'
s.render.image_settings.color_mode = 'RGBA'
for i, frame in enumerate([metadata['stillFrame']]):
    output = out / f'{i:03}.png'
    if output.exists():
        continue
    s.frame_set(frame)
    s.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
