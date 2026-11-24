"""Renders a contact sheet of the head parts for inspection (not part of the game build).
    blender -b --python tools/blender/basketball/head_preview.py -- --out docs/validation/player_m1/heads.png
"""
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import build_player as legacy  # noqa: E402
import head as H  # noqa: E402
from fc_character.materials import material  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(ROOT, "heads.png")
    with open(os.path.join(ROOT, "data", "player_pipeline", "rig_standard.json"), encoding="utf-8") as f:
        standard = json.load(f)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = legacy.Builder(standard, 1.98)
    arm = b.armature()
    skin = material("skin", (0.62, 0.42, 0.28), 0.55)
    hair = material("hair", (0.06, 0.04, 0.03), 0.8)
    lips = material("lips", (0.45, 0.22, 0.18), 0.5)
    feat = material("features", (1, 1, 1), 0.3, vertex_color=True)
    # three heads in a row: (face, jaw, nose, mouth, brow, eyes)
    combos = [(0, 0, 0, 0, 0, 1), (2, 1, 1, 1, 1, 1), (4, 2, 2, 2, 2, 2), (1, 1, 0, 0, 1, 0), (5, 0, 2, 1, 1, 1)]
    objs = []
    for n, (fc, jw, ns, mo, br, ey) in enumerate(combos):
        parts = [(H.build_skin_head(b, fc, jw), skin, "skin_head"), (H.build_lips(b, mo), lips, "lips"), (H.build_brows(b, br), hair, "brow"),
                 (H.build_eyes(b, ey), feat, "eyes")]
        nose, nostrils = H.build_nose(b, ns)
        parts += [(nose, skin, "nose"), (nostrils, feat, "nostrils")]
        for part, mat, nm in parts:
            o = part.to_object("%s_%d" % (nm, n), mat, arm)
            o.parent = None
            o.modifiers.clear()
            o.location.x = (n - 2) * 0.42
            objs.append(o)
    bpy.data.objects.remove(arm)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1800, 700
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.3
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    zc = 1.98 * 0.995 - 0.127 * 1.98 * 0.5
    cam.location = Vector((0, -3, zc))
    cam.rotation_euler = (1.5708, 0, 0)
    scene.camera = cam
    for loc, energy in (((1.5, -2.5, zc + 1.2), 400), ((-2, -2, zc + 0.5), 150)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = energy
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (1.2, 0, 0.5 if loc[0] > 0 else -0.5)
        scene.collection.objects.link(lo)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.55, 0.6, 1)
    scene.world = world
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    # profile view as well
    cam.location = Vector((3, 0, zc))
    cam.rotation_euler = (1.5708, 0, 1.5708)
    scene.render.filepath = out.replace(".png", "_side.png")
    bpy.ops.render.render(write_still=True)


main()
