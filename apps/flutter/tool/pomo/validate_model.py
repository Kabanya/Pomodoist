"""Compare exported emotion poses with the approved source in background Blender.

The source is evaluated, never saved. Run from the repository root with the
approved .blend open. The 0.001-unit tolerance is below one pixel at 384px and
includes the dense mitten's omitted subdivision modifier.
"""
import json
import gzip
import hashlib
import sys
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else Path('apps/flutter/assets/pomo/model')
manifest = json.loads((root / 'manifest.json').read_text())
assert Path(bpy.data.filepath).name == manifest['source']
assert hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest() == manifest['sourceSha256']
model = root / manifest.get('asset', 'pomo.glb')
if model.suffix == '.gz':
    raw = gzip.decompress(model.read_bytes())
    assert hashlib.sha256(raw).hexdigest() == manifest['modelSha256']
    model = Path('build/pomo-compact/validation.glb')
    model.parent.mkdir(parents=True, exist_ok=True)
    model.write_bytes(raw)
scene = bpy.data.scenes.new('Roundtrip')
scene.render.fps = 24
bpy.context.window.scene = scene
bpy.ops.import_scene.gltf(filepath=str(model.resolve()))
results = {}

for clip, meta in manifest['clips'].items():
    source_scene = bpy.data.scenes[meta['scene']]
    variant = 'thinking' if clip == 'focus' else 'regular'
    for obj in scene.objects:
        owners = [obj, obj.data.shape_keys if obj.type == 'MESH' else None]
        for owner in owners:
            if not owner or not owner.animation_data:
                continue
            owner.animation_data.action = None
            for track in owner.animation_data.nla_tracks:
                track.mute = track.name != clip
            if hasattr(owner, 'key_blocks'):
                for key in owner.key_blocks:
                    key.slider_min, key.slider_max = -2, 2

    errors = []
    for frame in {meta['firstFrame'], meta['stillFrame'], meta['lastFrame']}:
        bpy.context.window.scene = source_scene
        source_scene.frame_set(frame)
        source_points = {}
        for obj in source_scene.objects:
            key = obj.get('pomo_source_object', '')
            if obj.type != 'MESH' or obj.hide_render or not key.startswith('Pomo'):
                continue
            suffix = 'body' if key == 'Pomo Character' else key.replace('Pomo ', '').replace(' ', '-').lower()
            label = variant + '-' + suffix
            evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            mesh.calc_loop_triangles()
            tree = BVHTree.FromPolygons(points, [tuple(t.vertices) for t in mesh.loop_triangles], all_triangles=True)
            evaluated.to_mesh_clear()
            source_points[label] = (tree, points)

        bpy.context.window.scene = scene
        time = ((frame - meta['firstFrame']) /
                (meta['lastFrame'] - meta['firstFrame'] + 1) *
                meta['durationMs'] / 1000 * 24)
        scene.frame_set(int(time) + 1, subframe=time - int(time))
        checked = set()
        for obj in scene.objects:
            if obj.type != 'MESH' or not obj.data.materials:
                continue
            label = obj.data.materials[0].name
            if label not in source_points:
                continue
            checked.add(label)
            evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            mesh.calc_loop_triangles()
            tree = BVHTree.FromPolygons(points, [tuple(t.vertices) for t in mesh.loop_triangles], all_triangles=True)
            source_tree, original_points = source_points[label]
            distances = [source_tree.find_nearest(point)[3] for point in points]
            reverse = [tree.find_nearest(point)[3] for point in original_points]
            errors.append({'frame': frame, 'mesh': label,
                           'maxSurfaceError': max(distances), 'maxReverseSurfaceError': max(reverse)})
            evaluated.to_mesh_clear()
        assert variant + '-body' in checked, f'{clip}: body was not compared'
    results[clip] = errors

report = Path('build/pomo-model-geometry-validation.json')
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps(results, indent=2))
for clip, errors in results.items():
    print('GEOMETRY', clip, max(max(e['maxSurfaceError'], e['maxReverseSurfaceError']) for e in errors), flush=True)
assert all(errors and max(max(e['maxSurfaceError'], e['maxReverseSurfaceError']) for e in errors) < .001
           for errors in results.values()), 'GLB geometry does not match source'
