"""Inspection sheet of every V2 hair and facial-hair style (not part of the build). Run on the .blend kept by build_v2.py:
    blender -b <fc_v2_body.blend> --python tools/blender/v2/preview_hair.py -- --out <dir>
The hair material mixes the skin colour and the hair colour by the density vertex colour, as the game shader does."""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import preview_v2 as P  # noqa: E402


def hair_material(skin_rgb, hair_rgb):
    m = bpy.data.materials.get("hair")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*skin_rgb, 1)
    mix.inputs[7].default_value = (*hair_rgb, 1)
    nt.links.new(attr.outputs["Color"], mix.inputs[0])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7


def main():
    out = P.arg("--out", ".")
    os.makedirs(out, exist_ok=True)
    skin_rgb = (0.32, 0.2, 0.13)
    P.colour("skin", skin_rgb, 0.45)
    P.colour("eyes", (0.9, 0.9, 0.9), 0.2)
    P.colour("brows", (0.05, 0.04, 0.03), 0.8)
    P.colour("lashes", (0.05, 0.04, 0.03), 0.8)
    P.colour("jersey", (0.1, 0.25, 0.8), 0.8)
    P.colour("accessory", (0.95, 0.95, 0.95), 0.8)
    hair_material(skin_rgb, (0.03, 0.025, 0.02))
    arm = bpy.data.objects["Armature"]
    styles = [o for o in bpy.data.objects if o.name.startswith(("hair_", "facial_", "acc_"))]
    for o in bpy.data.objects:
        if o.type == "MESH" and (o.name.startswith(("hair_", "facial_", "acc_", "equip_")) or (o.name.startswith("brow_") and o.name != "brow_001")):
            o.hide_render = True
    scene, cam, cam_data = P.setup_scene(arm)
    H = float(arm.get("fc_height_m", 2.0))
    for o in styles:
        o.hide_render = False
        for view, rot, loc in (("34", 0.55, (1.6, -2.6, H * 0.935)), ("back", math.pi - 0.3, (1.0, 3.2, H * 0.935))):
            P.shot(scene, cam, cam_data, os.path.join(out, "%s_%s.png" % (o.name, view)), loc, (math.pi / 2, 0, rot), H * 0.17, (360, 360))
        o.hide_render = True


main()
