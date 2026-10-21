"""Export the approved Blender scenes as one skinned, textured glTF model.

Run with Blender --background <pomo_3_0_2_all_animations_linked.blend>
--python-exit-code 1 --python apps/flutter/tool/pomo/export_model.py -- OUTPUT.
Writes an intermediate GLB outside the bundle; never saves the source .blend.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(sys.argv[sys.argv.index('--') + 1]).resolve() if '--' in sys.argv else ROOT / 'build/pomo-model-export'
SOURCE = Path(bpy.data.filepath)
assert SOURCE.name == 'pomo_3_0_2_all_animations_linked.blend', SOURCE
SOURCE_HASH = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
CACHE = ROOT / 'build/pomo-model-bake' / SOURCE_HASH / 'runtime-uv-v5-4096-512-hand16k'
CLIPS = {
    'calm': ('06 | Calm', 1, 240, 58, True),
    'focus': ('10 | Thinking reference', 1, 144, 49, True),
    'rest': ('08 | Rest', 1, 96, 25, True),
    'tired': ('09 | Tired', 1, 96, 25, True),
    'greeting': ('01 | Greeting', 1, 72, 28, False),
    'happy': ('02 | Happy', 1, 72, 20, False),
    'sad': ('04 | Sad', 8, 29, 29, False),
    'surprised': ('03 | Surprised', 1, 72, 12, False),
}
OUT.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(parents=True, exist_ok=True)


def select(scene, obj):
    bpy.context.window.scene = scene
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.select_set(True)
    scene.view_layers[0].objects.active = obj


def bake_material(scene, obj, label):
    """Bake procedural colors/roughness/normals, not lighting or motion."""
    select(scene, obj)
    # Authoring UVs overlap at the eyes; bake to a dedicated non-overlapping atlas.
    uv = obj.data.uv_layers.new(name='Pomo Runtime UV')
    obj.data.uv_layers.active = uv
    uv.active_render = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv = obj.data.uv_layers['Pomo Runtime UV']
    size = 4096 if 'body' in label else 512
    materials = []
    for slot in obj.material_slots:
        slot.material = slot.material.copy()
        materials.append(slot.material)
    images = {}
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.render.bake.margin = 4
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.use_clear = True
    for channel, bake_type in [('color', 'DIFFUSE'), ('roughness', 'ROUGHNESS'), ('normal', 'NORMAL')]:
        path = CACHE / f'{label}-{channel}.png'
        if path.exists():
            image = bpy.data.images.load(str(path), check_existing=True)
        else:
            image = bpy.data.images.new(f'{label}-{channel}', size, size, alpha=False)
            if channel != 'color':
                image.colorspace_settings.name = 'Non-Color'
            for mat in materials:
                node = mat.node_tree.nodes.new('ShaderNodeTexImage')
                node.image = image
                mat.node_tree.nodes.active = node
            outputs = []
            if channel == 'color':
                # Bake the shader's base color independently of its diffuse/specular mix.
                for material in materials:
                    tree = material.node_tree
                    bsdf = next(node for node in tree.nodes if node.type == 'BSDF_PRINCIPLED')
                    output = next(node for node in tree.nodes if node.type == 'OUTPUT_MATERIAL' and node.is_active_output)
                    previous = output.inputs['Surface'].links[0].from_socket
                    emission = tree.nodes.new('ShaderNodeEmission')
                    color = bsdf.inputs['Base Color']
                    if color.is_linked:
                        tree.links.new(color.links[0].from_socket, emission.inputs['Color'])
                    else:
                        emission.inputs['Color'].default_value = color.default_value
                    tree.links.new(emission.outputs[0], output.inputs['Surface'])
                    outputs.append((tree, output, previous, emission))
            print('BAKE', label, channel, flush=True)
            bpy.ops.object.bake(type='EMIT' if channel == 'color' else bake_type,
                               pass_filter={'COLOR'}, normal_space='TANGENT')
            for tree, output, previous, emission in outputs:
                tree.links.new(previous, output.inputs['Surface'])
                tree.nodes.remove(emission)
            image.filepath_raw = str(path)
            image.file_format = 'PNG'
            image.save()
        if channel != 'color':
            image.colorspace_settings.name = 'Non-Color'
        images[channel] = image
    mat = bpy.data.materials.new(label)
    mat.use_nodes = True
    # Alpha is animated in the runtime only when switching the approved hand/eye variant.
    mat.surface_render_method = 'BLENDED'
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Alpha'].default_value = 0.999
    bsdf.inputs['Roughness'].default_value = 0.6
    uv_node = nodes.new('ShaderNodeUVMap')
    uv_node.uv_map = uv.name
    for channel in images:
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = images[channel]
        links.new(uv_node.outputs['UV'], tex.inputs['Vector'])
        if channel == 'normal':
            normal = nodes.new('ShaderNodeNormalMap')
            normal.uv_map = uv.name
            links.new(tex.outputs['Color'], normal.inputs['Color'])
            links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
        else:
            links.new(tex.outputs['Color'], bsdf.inputs['Base Color' if channel == 'color' else 'Roughness'])
    # Runtime engines expose UV0/UV1; discard unused authoring UV sets after baking.
    uv_name = uv.name
    for name in [layer.name for layer in obj.data.uv_layers if layer.name != uv_name]:
        obj.data.uv_layers.remove(obj.data.uv_layers[name])
    assert len(obj.data.uv_layers) == 1
    obj.data.uv_layers.active = obj.data.uv_layers[uv_name]
    obj.data.uv_layers[uv_name].active_render = True
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0



def volume_correction(obj, rig):
    """Represent Blender's dual-quaternion/masked deformation in glTF morphs."""
    count = len(obj.data.vertices)
    transforms = np.zeros((count, 4, 4), dtype=np.float64)
    bone_matrices = {b.name: np.array(b.matrix @ b.bone.matrix_local.inverted())
                     for b in rig.pose.bones if b.bone.use_deform}
    for vertex in obj.data.vertices:
        total = 0.0
        for group in vertex.groups:
            matrix = bone_matrices.get(obj.vertex_groups[group.group].name)
            if matrix is not None:
                transforms[vertex.index] += matrix * group.weight
                total += group.weight
        transforms[vertex.index] = transforms[vertex.index] / total if total > 1e-8 else np.eye(4)
    base = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)
    before_skin = base.copy()
    keys = obj.data.shape_keys
    if keys:
        for key in keys.key_blocks[1:]:
            if key.value:
                before_skin += (np.array([v.co[:] for v in key.data]) - np.array([v.co[:] for v in key.relative_key.data])) * key.value
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    desired = np.array([v.co[:] for v in mesh.vertices], dtype=np.float64)
    evaluated.to_mesh_clear()
    corrected = np.linalg.solve(transforms[:, :3, :3], (desired-transforms[:, :3, 3])[..., None])[..., 0]
    return corrected - before_skin

# Evaluate source poses before constructing the export scene.
samples = {}
corrections = {}
for name, (scene_name, first, last, still, loop) in CLIPS.items():
    scene = bpy.data.scenes[scene_name]
    bpy.context.window.scene = scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    body = next(o for o in scene.objects if o.get('pomo_source_object') == 'Pomo Character')
    frames = []
    corrections[name] = {}
    arms = [o for o in scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.use_deform_preserve_volume for m in o.modifiers)]
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        bones = {}
        for bone in rig.pose.bones:
            matrix = rig.convert_space(pose_bone=bone, matrix=bone.matrix, from_space='POSE', to_space='LOCAL')
            loc, rot, scale = matrix.decompose()
            bones[bone.name] = (tuple(loc), tuple(rot), tuple(scale))
        keys = {k.name: k.value for k in body.data.shape_keys.key_blocks if k.name != 'Basis'}
        frames.append((bones, keys))
        if (frame-first) % 4 == 0 or frame in [still, last]:
            for arm in arms:
                corrections[name].setdefault(arm.get('pomo_source_object'), {})[frame-first] = volume_correction(arm, rig)
    # A final boundary sample gives exact durations and closes looping poses.
    samples[name] = frames + [frames[0] if loop else frames[-1]]
    print('SAMPLED', name, len(frames), flush=True)

scene = bpy.data.scenes.new('Pomo runtime')
scene.render.fps = 24
bpy.context.window.scene = scene
base_scene = bpy.data.scenes['06 | Calm']
source_rig = next(o for o in base_scene.objects if o.type == 'ARMATURE')
rig = source_rig.copy()
rig.data = source_rig.data.copy()
rig.name = 'Pomo rig'
rig.animation_data_clear()
scene.collection.objects.link(rig)
select(scene, rig)
bpy.ops.object.mode_set(mode='EDIT')
anchor = rig.data.edit_bones.new('static_anchor')
anchor.head, anchor.tail = (0, 0, 0), (0, .1, 0)
bpy.ops.object.mode_set(mode='OBJECT')
for bone in rig.pose.bones:
    for constraint in list(bone.constraints):
        bone.constraints.remove(constraint)

meshes = []
simplification = []
for variant, scene_name, still in [('regular', '06 | Calm', 58), ('thinking', '10 | Thinking reference', 49)]:
    source_scene = bpy.data.scenes[scene_name]
    bpy.context.window.scene = source_scene
    source_scene.frame_set(still)
    source_armature = next(o for o in source_scene.objects if o.type == 'ARMATURE')
    for bone in source_armature.data.bones:
        assert all(abs(a-b) < 1e-5 for ra,rb in zip(bone.matrix_local,rig.data.bones[bone.name].matrix_local) for a,b in zip(ra,rb)), bone.name
    sources = [o for o in source_scene.objects if o.type == 'MESH' and not o.hide_render and o.get('pomo_source_object', '').startswith('Pomo') and o.get('pomo_source_object') != 'Pomo Highlight Control Ring']
    for source in sources:
        obj = source.copy()
        obj.data = source.data.copy()
        source_scene.collection.objects.link(obj)
        identity = source.get('pomo_source_object')
        label = variant + '-' + ('body' if identity == 'Pomo Character' else identity.replace('Pomo ', '').replace(' ', '-').lower())
        obj.name = label
        obj.data.name = label
        obj.animation_data_clear()
        if obj.data.shape_keys:
            obj.data.shape_keys.animation_data_clear()
        # Keep body topology; simplify only the unusually dense hand below.
        for modifier in list(obj.modifiers):
            if modifier.type == 'SUBSURF':
                obj.modifiers.remove(modifier)
        if identity.startswith('Pomo Arm.') and len(obj.data.vertices) > 10000:
            assert obj.data.shape_keys is None, 'Shape-key hands need correspondence transfer'
            select(source_scene, obj)
            obj.data.calc_loop_triangles()
            before = len(obj.data.loop_triangles)
            simplify = obj.modifiers.new('Runtime hand simplification', 'DECIMATE')
            simplify.ratio = min(1., 16000 / before)
            simplify.use_collapse_triangulate = True
            bpy.ops.object.modifier_move_to_index(modifier=simplify.name, index=0)
            bpy.ops.object.modifier_apply(modifier=simplify.name)
            obj.data.calc_loop_triangles()
            assert len(obj.data.loop_triangles) <= 16000
            simplification.append({'mesh': label, 'sourceTriangles': before, 'runtimeTriangles': len(obj.data.loop_triangles), 'runtimeVertices': len(obj.data.vertices)})
            print('SIMPLIFIED', label, before, len(obj.data.loop_triangles), flush=True)
        bake_material(source_scene, obj, label)
        source_scene.collection.objects.unlink(obj)
        scene.collection.objects.link(obj)
        if obj.parent and obj.parent.type == 'ARMATURE':
            obj.parent = rig
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE':
                modifier.object = rig
        # Blender ignores non-deforming groups; glTF must explicitly anchor those vertices.
        for group in list(obj.vertex_groups):
            if group.name in rig.data.bones and not rig.data.bones[group.name].use_deform:
                obj.vertex_groups.remove(group)
        static = obj.vertex_groups.new(name='static_anchor')
        for vertex in obj.data.vertices:
            if not any(g.weight > 1e-8 and obj.vertex_groups[g.group].name in rig.data.bones for g in vertex.groups):
                static.add([vertex.index], 1.0, 'REPLACE')
        meshes.append(obj)

bpy.context.window.scene = scene
# Both material variants receive the same face shape interpolation.
regular_body = next(o for o in meshes if o.name == 'regular-body')
thinking_body = next(o for o in meshes if o.name == 'thinking-body')
assert len(regular_body.data.vertices) == len(thinking_body.data.vertices)
for key in thinking_body.data.shape_keys.key_blocks:
    if key.name not in regular_body.data.shape_keys.key_blocks:
        new = regular_body.shape_key_add(name=key.name)
        coords = np.empty(len(key.data)*3, dtype=np.float32)
        key.data.foreach_get('co', coords)
        new.data.foreach_set('co', coords)


# Sparse corrective shapes preserve arm volume while the skeleton remains editable.
for obj in meshes:
    identity = obj.get('pomo_source_object')
    if not any(m.type == 'ARMATURE' and m.use_deform_preserve_volume for m in obj.modifiers):
        continue
    base = np.array([v.co[:] for v in obj.data.vertices])
    for name, arms in corrections.items():
        for index, delta in arms.get(identity, {}).items():
            assert len(delta) == len(base)
            key = obj.shape_key_add(name=f'volume-{name}-{index}')
            key.data.foreach_set('co', (base + delta).astype(np.float32).ravel())


def stash(datablock, name):
    action = datablock.animation_data.action
    action.name = name
    slot = datablock.animation_data.action_slot
    datablock.animation_data.action = None
    track = datablock.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.action_slot = slot
    strip.extrapolation = 'NOTHING'


for name, frames in samples.items():
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions.new(name)
    keyed = [o.data.shape_keys for o in meshes if o.data.shape_keys]
    for keys in keyed:
        for key in keys.key_blocks[1:]:
            key.slider_min, key.slider_max = -2, 2
    for keys in keyed:
        keys.animation_data_create()
        keys.animation_data.action = bpy.data.actions.new(name + '-face')
    for index, (bones, weights) in enumerate(frames, start=1):
        for bone_name, (loc, rot, scale) in bones.items():
            bone = rig.pose.bones[bone_name]
            bone.rotation_mode = 'QUATERNION'
            bone.location, bone.rotation_quaternion, bone.scale = loc, rot, scale
            for prop in ['location', 'rotation_quaternion', 'scale']:
                bone.keyframe_insert(prop, frame=index, group=bone_name)
        for keys in keyed:
            for key in keys.key_blocks[1:]:
                value = weights.get(key.name, 0)
                if key.name.startswith('volume-'):
                    _, key_clip, key_frame = key.name.split('-')
                    if key_clip == name:
                        identity = next(o.get('pomo_source_object') for o in meshes if o.data.shape_keys == keys)
                        positions = sorted(corrections[name].get(identity, {}))
                        sample = index-1
                        if sample == len(frames)-1:
                            sample = 0 if CLIPS[name][4] else sample-1
                        left = max(p for p in positions if p <= sample)
                        right = min(p for p in positions if p >= sample)
                        target = int(key_frame)
                        value = (1 if target == left else 0) if left == right else ((right-sample)/(right-left) if target == left else (sample-left)/(right-left) if target == right else 0)
                key.value = value
                key.keyframe_insert('value', frame=index)
    stash(rig, name)
    for keys in keyed:
        stash(keys, name)
    print('ANIMATION', name, flush=True)
scene.frame_start = 1
scene.frame_end = 241
scene.frame_set(1)
select(scene, rig)
for obj in meshes:
    obj.select_set(True)
path = OUT / 'pomo.glb'
# Dense morph accessors avoid missing geometry in Filament's Metal renderer.
bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
    use_active_scene=True, export_animations=True, export_animation_mode='NLA_TRACKS',
    export_merge_animation='NLA_TRACK', export_force_sampling=True, export_frame_range=False,
    export_morph=True, export_tangents=True, export_morph_tangent=True, export_try_sparse_sk=False, export_skins=True, export_cameras=False, export_lights=False,
    export_extras=False, export_vertex_color='NONE', export_all_vertex_colors=False)

# Normalize exported clip names/times, including the established 900 ms Sad reaction.
raw = path.read_bytes()
json_len = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+json_len])
bin_start = 20 + json_len
binary = bytearray(raw[bin_start+8:])
assert len(doc['skins']) >= 1
assert len(doc['animations']) == len(CLIPS), [a['name'] for a in doc['animations']]
manifest = {'version': 1, 'source': SOURCE.name, 'sourceSha256': SOURCE_HASH,
            'format': 'glTF 2.0', 'sourceVersion': '3.0.2', 'simplification': simplification, 'transitionMs': 250,
            'camera': {'position': [0, .2, 3.8], 'target': [0, -.025, 0], 'orthoScale': 1.28},
            'clips': {}}
for animation in doc['animations']:
    name = animation['name']
    assert name in CLIPS, name
    scene_name, first, last, still, loop = CLIPS[name]
    duration = .9 if name == 'sad' else (last-first+1)/24
    inputs = {s['input'] for s in animation['samplers']}
    actual = max(doc['accessors'][i]['max'][0] for i in inputs)
    start = min(doc['accessors'][i]['min'][0] for i in inputs)
    # Duplicate time accessors because glTF may share them across different clips.
    for sampler in animation['samplers']:
        accessor = dict(doc['accessors'][sampler['input']])
        view = doc['bufferViews'][accessor['bufferView']]
        offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        values = struct.unpack_from('<'+'f'*accessor['count'], binary, offset)
        values = [(v - start) * duration / (actual - start) for v in values]
        while len(binary) % 4:
            binary.append(0)
        view_index = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': 4*len(values)})
        binary.extend(struct.pack('<'+'f'*len(values), *values))
        accessor.update(bufferView=view_index, byteOffset=0, min=[min(values)], max=[max(values)])
        sampler['input'] = len(doc['accessors'])
        doc['accessors'].append(accessor)
    manifest['clips'][name] = {'scene': scene_name, 'firstFrame': first, 'lastFrame': last,
        'stillFrame': still, 'durationMs': round(duration*1000),
        'stillSeconds': (still-first)/(last-first+1)*duration, 'loop': loop}
# Explicit alpha blending lets the runtime blend the two approved mesh variants.
for material in doc['materials']:
    material['alphaMode'] = 'BLEND'
    material['pbrMetallicRoughness']['baseColorFactor'] = [1,1,1,1]
# Atlas mipmaps bleed neighboring islands on Metal; keep bilinear sampling.
for sampler in doc.get('samplers', []):
    sampler['minFilter'] = 9729
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc, separators=(',', ':')).encode()
encoded += b' ' * (-len(encoded) % 4)
binary += b'\0' * (-len(binary) % 4)
path.write_bytes(struct.pack('<III', 0x46546c67, 2, 12+8+len(encoded)+8+len(binary)) +
                 struct.pack('<II',len(encoded),0x4e4f534a)+encoded+
                 struct.pack('<II',len(binary),0x004e4942)+binary)
manifest['modelSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print('EXPORTED', path, path.stat().st_size, flush=True)
