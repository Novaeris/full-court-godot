"""Renders an assembled player (body + chosen head parts + hair) from several views for inspection; not part of the game build.
    blender -b --python tools/blender/basketball/preview.py -- --out dir [--body athletic] [--face 2] [--jaw 1] [--nose 1] [--mouth 1] [--brow 1] [--eyes 1] [--hair afro] [--facial beard]
"""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import build_player_m1 as M  # noqa: E402
import clothing as C  # noqa: E402
import body as B  # noqa: E402
import context as X  # noqa: E402
import hair as R  # noqa: E402
import head as H  # noqa: E402


def args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    d = {"out": ".", "body": "athletic", "face": 2, "jaw": 1, "nose": 1, "mouth": 1, "brow": 1, "eyes": 1, "hair": "short", "facial": "none", "views": "full"}
    for i in range(0, len(argv) - 1, 2):
        k = argv[i].lstrip("-")
        d[k] = type(d[k])(argv[i + 1]) if k in d else argv[i + 1]
    return d


def main():
    a = args()
    ctx = X.Context(X.load_standard(), 1.98, a["body"])
    arm, mats = M.start(ctx, True)
    skin = B.build_skin(ctx, True)
    skin.merge(H.build_base_head(ctx))
    skin.to_object("skin", mats["skin"], arm)
    jersey, jtrim = C.build_jersey(ctx)
    shorts, strim = C.build_shorts(ctx)
    socks, ktrim = C.build_socks(ctx)
    shoes, sole, shtrim = C.build_shoes(ctx)
    for t in (strim, ktrim, shtrim):
        jtrim.merge(t)
    jersey.to_object("jersey", mats["jersey"], arm)
    shorts.to_object("shorts", mats["shorts"], arm)
    socks.to_object("socks", mats["socks"], arm)
    shoes.to_object("shoes", mats["shoes"], arm)
    sole.to_object("sole", mats["sole"], arm)
    jtrim.to_object("trim", mats["trim"], arm)
    H.build_skin_head(ctx, a["face"], a["jaw"]).to_object("skin_head", mats["skin"], arm)
    n, nn = H.build_nose(ctx, a["nose"])
    n.to_object("nose", mats["skin"], arm)
    nn.to_object("nostrils", mats["features"], arm)
    H.build_lips(ctx, a["mouth"]).to_object("lips", mats["lips"], arm)
    H.build_brows(ctx, a["brow"]).to_object("brow", mats["hair"], arm)
    H.build_eyes(ctx, a["eyes"]).to_object("eyes", mats["features"], arm)
    if a["hair"] != "bald":
        R.build_hair(ctx, a["hair"]).to_object("hair", mats["hair"], arm)
    if a["facial"] != "none":
        R.build_facial_hair(ctx, a["facial"], a["jaw"]).to_object("facial", mats["hair"], arm)
    # colours
    mats["jersey"].node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.1, 0.3, 0.9, 1)
    mats["shorts"].node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.1, 0.3, 0.9, 1)
    mats["trim"].node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.95, 0.95, 0.95, 1)
    scene = bpy.context.scene
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for loc, energy in (((2.5, -3, 3.0), 900), ((-3, -2, 2.0), 300), ((0, 3, 2.5), 300)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = energy
        ld.size = 3
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        c = lo.constraints.new("TRACK_TO")
        c.target = arm
        c.track_axis = "TRACK_NEGATIVE_Z"
        c.up_axis = "UP_Y"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.5, 0.55, 1)
    scene.world = world
    os.makedirs(a["out"], exist_ok=True)
    shots = {
        "full_front": ((0, -5, 1.0), (1.5708, 0, 0), 2.4, (700, 1000)),
        "full_side": ((5, 0, 1.0), (1.5708, 0, 1.5708), 2.4, (700, 1000)),
        "full_34": ((3.5, -3.5, 1.0), (1.5708, 0, 0.785), 2.4, (700, 1000)),
        "head_front": ((0, -5, 1.78), (1.5708, 0, 0), 0.55, (800, 800)),
        "head_34": ((3.5, -3.5, 1.78), (1.5708, 0, 0.785), 0.55, (800, 800)),
        "shorts_front": ((0, -5, 0.85), (1.5708, 0, 0), 0.8, (800, 800)),
        "hands_front": ((0, -5, 1.15), (1.5708, 0, 0), 1.0, (800, 800)),
    }
    for name, (loc, rot, scale, res) in shots.items():
        cam.location = Vector(loc)
        cam.rotation_euler = rot
        cam_data.ortho_scale = scale
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.filepath = os.path.join(a["out"], name + ".png")
        bpy.ops.render.render(write_still=True)


main()
