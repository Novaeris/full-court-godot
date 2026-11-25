"""Inspection renders of a V2 .blend (not part of the build): front, side, back, face close-ups and a sheet of faces with different morph mixes.
    blender -b <file.blend> --python tools/blender/v2/preview_v2.py -- --out <dir> [--faces 8] [--seed 1]
Never write the output inside the project folder (Godot would import it)."""
import math
import os
import random
import sys

import bpy
from mathutils import Vector


def arg(name, default):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return type(default)(argv[argv.index(name) + 1]) if name in argv else default


def setup_scene(target_obj):
    scene = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for loc, e in (((2.5, -3, 3.0), 900), ((-3, -2, 2.0), 350), ((0, 3, 2.5), 400)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = 3
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        c = lo.constraints.new("TRACK_TO")
        c.target = target_obj
        c.track_axis = "TRACK_NEGATIVE_Z"
        c.up_axis = "UP_Y"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.5, 0.55, 1)
    scene.world = w
    return scene, cam, cam_data


def colour(name, rgb, rough=0.5):
    m = bpy.data.materials.get(name)
    if m is None:
        return
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough


def shot(scene, cam, cam_data, path, loc, rot, scale, res):
    cam.location = Vector(loc)
    cam.rotation_euler = rot
    cam_data.ortho_scale = scale
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    out = arg("--out", ".")
    faces = arg("--faces", 8)
    random.seed(arg("--seed", 1))
    os.makedirs(out, exist_ok=True)
    skin = bpy.data.objects["skin"]
    arm = bpy.data.objects["Armature"]
    colour("skin", (0.42, 0.26, 0.17), 0.45)
    colour("eyes", (0.9, 0.9, 0.9), 0.2)
    colour("brows", (0.05, 0.04, 0.03), 0.8)
    colour("lashes", (0.05, 0.04, 0.03), 0.8)
    colour("jersey", (0.1, 0.25, 0.8), 0.8)
    colour("shorts", (0.1, 0.25, 0.8), 0.8)
    colour("socks", (0.92, 0.92, 0.92), 0.9)
    colour("trim", (0.95, 0.95, 0.95), 0.8)
    colour("shoes", (0.08, 0.08, 0.1), 0.5)
    colour("sole", (0.95, 0.95, 0.95), 0.7)
    colour("equipment", (0.95, 0.95, 0.95), 0.6)
    for o in bpy.data.objects:
        if o.name.startswith("brow_") and o.name != "brow_001":
            o.hide_render = True
    scene, cam, cam_data = setup_scene(arm)
    H = float(arm.get("fc_height_m", 2.0))
    shot(scene, cam, cam_data, os.path.join(out, "front.png"), (0, -6, H / 2), (math.pi / 2, 0, 0), H * 1.08, (700, 1000))
    shot(scene, cam, cam_data, os.path.join(out, "side.png"), (6, 0, H / 2), (math.pi / 2, 0, math.pi / 2), H * 1.08, (700, 1000))
    shot(scene, cam, cam_data, os.path.join(out, "back.png"), (0, 6, H / 2), (math.pi / 2, 0, math.pi), H * 1.08, (700, 1000))
    shot(scene, cam, cam_data, os.path.join(out, "face.png"), (1.2, -3, H * 0.935), (math.pi / 2, 0, 0.38), H * 0.15, (700, 700))
    shot(scene, cam, cam_data, os.path.join(out, "hands.png"), (0.7, -3, H * 0.5), (math.pi / 2, 0, 0.25), H * 0.3, (700, 700))
    keys = [k for k in skin.data.shape_keys.key_blocks[1:]]
    face_keys = [k.name for k in keys if k.name.startswith("fcf_")]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for n in range(faces):
        weights = {k: (random.random() ** 2 if random.random() < 0.45 else 0.0) for k in face_keys}
        for o in meshes:
            if o.data.shape_keys is None:
                continue
            for kb in o.data.shape_keys.key_blocks[1:]:
                kb.value = weights.get(kb.name, 0.0)
        shot(scene, cam, cam_data, os.path.join(out, "face_var_%d.png" % n), (0.9, -3, H * 0.935), (math.pi / 2, 0, 0.3), H * 0.15, (400, 400))
    body_keys = [k.name for k in keys if k.name.startswith("fcb_")]
    for name in body_keys:
        for o in meshes:
            if o.data.shape_keys is None:
                continue
            for kb in o.data.shape_keys.key_blocks[1:]:
                kb.value = 1.0 if kb.name == name else 0.0
        shot(scene, cam, cam_data, os.path.join(out, "body_%s.png" % name), (3.5, -4.2, H / 2), (math.pi / 2, 0, 0.7), H * 1.08, (420, 600))


main()
