"""Blender-side approval renders of the master (D-076): front, side, back, face, three-quarter face, upper body, hands, shoes, with one fixed studio
setup. READ ONLY (never saves). Output must be OUTSIDE the project folder (Godot imports .blend and pictures) or in docs/validation.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/render_master.py -- --out <dir> [--hair hair_low_fade] [--facial facial_goatee]
The in-game check is tools/reference_scene.gd (the same views in Godot); both are required by the approval gate."""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def arg(name, default):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv[argv.index(name) + 1] if name in argv else default


def colour(name, rgb, rough=0.5):
    m = bpy.data.materials.get(name)
    if m is None:
        return
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough


def hair_density_material(skin_rgb, hair_rgb):
    """Hair as the game draws it: the density vertex colour mixes skin and hair, and thin hair (low density) becomes transparent."""
    m = bpy.data.materials.get("hair")
    if m is None:
        return
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 900.0
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(attr.outputs["Color"], mul.inputs[0])
    nt.links.new(noise.outputs["Fac"], mul.inputs[1])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(mul.outputs[0], add.inputs[0])
    nt.links.new(attr.outputs["Color"], add.inputs[1])
    bsdf.inputs["Base Color"].default_value = (*hair_rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    nt.links.new(add.outputs[0], bsdf.inputs["Alpha"])
    m.blend_method = "HASHED" if hasattr(m, "blend_method") else m.blend_method
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "DITHERED"


def main():
    out = arg("--out", os.path.join(M.ROOT, "..", "fc_master_renders"))
    os.makedirs(out, exist_ok=True)
    hair, facial = arg("--hair", "hair_low_fade"), arg("--facial", "facial_goatee")
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        cname = M.collection_for(o.name)
        hidden = (cname in ("FC_Hair", "FC_Facial", "FC_Equipment") and o.name not in (hair, facial)) or (o.name.startswith("brow_") and o.name != "brow_001")
        o.hide_render = hidden
    skin = (0.40, 0.24, 0.15)
    colour("skin", skin, 0.5)
    colour("eyes", (0.85, 0.85, 0.85), 0.15)
    for n in ("brows", "lashes"):
        colour(n, (0.03, 0.025, 0.02), 0.75)
    hair_density_material(skin, (0.02, 0.016, 0.012))
    colour("jersey", (0.07, 0.2, 0.55), 0.85)
    colour("shorts", (0.07, 0.2, 0.55), 0.85)
    colour("trim", (0.98, 0.78, 0.17), 0.8)
    colour("socks", (0.92, 0.92, 0.92), 0.9)
    colour("shoes", (0.95, 0.95, 0.95), 0.6)
    colour("sole", (0.1, 0.1, 0.1), 0.8)
    colour("equipment", (0.95, 0.95, 0.95), 0.6)
    colour("accessory", (0.95, 0.95, 0.95), 0.8)
    scene = bpy.context.scene
    scene.view_settings.view_transform = "Standard"
    ids = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in ids else "BLENDER_EEVEE"
    arm = bpy.data.objects["Armature"]
    H = float(arm.get("fc_height_m", 2.0))
    target = bpy.data.objects.new("fc_target", None)
    scene.collection.objects.link(target)
    target.location = (0, 0, H * 0.55)
    for loc, e, size in (((2.5, -3.5, 3.2), 520, 3), ((-3.5, -2.0, 1.8), 180, 4), ((0.5, 4.0, 3.0), 320, 2)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = size
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        c = lo.constraints.new("TRACK_TO")
        c.target = target
        c.track_axis = "TRACK_NEGATIVE_Z"
        c.up_axis = "UP_Y"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.33, 0.36, 0.42, 1)
    scene.world = w
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.lens = 85
    shots = {
        "front": (Vector((0, -9.5, H * 0.52)), Vector((0, 0, H * 0.5)), (800, 1200)),
        "side": (Vector((9.5, 0, H * 0.52)), Vector((0, 0, H * 0.5)), (800, 1200)),
        "back": (Vector((0, 9.5, H * 0.52)), Vector((0, 0, H * 0.5)), (800, 1200)),
        "face": (Vector((0.0, -1.55, H * 0.93)), Vector((0, 0, H * 0.925)), (900, 900)),
        "face34": (Vector((0.95, -1.25, H * 0.935)), Vector((0, 0, H * 0.925)), (900, 900)),
        "upper": (Vector((0.6, -3.6, H * 0.8)), Vector((0, 0, H * 0.76)), (900, 1100)),
        "hands": (Vector((1.2, -1.6, H * 0.5)), Vector((H * 0.12, 0, H * 0.47)), (900, 900)),
        "shoes": (Vector((0.9, -1.6, H * 0.15)), Vector((0, -0.05, H * 0.04)), (1100, 800)),
    }
    for name, (loc, look, res) in shots.items():
        cam.location = loc
        d = look - loc
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.filepath = os.path.join(out, name + ".png")
        bpy.ops.render.render(write_still=True)
    print("FC_RENDER_OK", out)


main()
