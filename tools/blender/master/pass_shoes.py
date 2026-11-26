"""Modeling pass on the master shoes (D-076): paints colour ZONES into the shoe upper as a vertex colour (red channel = accent zone), so the game can
make every shoe two-tone from the team colours without separate meshes: a heel counter, a swoosh-like side stripe (an original curved band, no brand
shape), a toe cap and the collar lining. Also adds a slight crease line over the toe box. Rest pose positions decide the zones.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_shoes.py -- --label <label>
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def smoothstep(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


def zones(shoes):
    me = shoes.data
    basis = me.shape_keys.key_blocks[0].data if me.shape_keys else me.vertices
    if not me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    col = me.color_attributes[0]
    me.color_attributes.active_color = col
    # per shoe (left x>0, right x<0): heel y (max), toe y (min), top z
    sides = {}
    for i in range(len(basis)):
        co = basis[i].co
        s = sides.setdefault(co.x > 0, {"ymin": 9.0, "ymax": -9.0, "zmax": 0.0, "xs": []})
        s["ymin"] = min(s["ymin"], co.y)
        s["ymax"] = max(s["ymax"], co.y)
        s["zmax"] = max(s["zmax"], co.z)
        s["xs"].append(co.x)
    for s in sides.values():
        s["xc"] = sum(s["xs"]) / len(s["xs"])
    accent = []
    for i in range(len(basis)):
        co = basis[i].co
        s = sides[co.x > 0]
        t = (s["ymax"] - co.y) / max(s["ymax"] - s["ymin"], 1e-4)   # 0 heel .. 1 toe
        h = co.z / max(s["zmax"], 1e-4)                               # 0 floor .. 1 collar top
        lateral = abs(co.x - s["xc"]) / 0.05
        heel = smoothstep(0.30, 0.20, t) * smoothstep(0.25, 0.35, h) * smoothstep(0.95, 0.80, h)
        # a curved side band: rises from the midsole at the toe side to the heel collar
        band_centre = 0.30 + 0.45 * (1.0 - t)
        stripe = smoothstep(0.075, 0.035, abs(h - band_centre)) * smoothstep(0.15, 0.30, t) * smoothstep(0.92, 0.75, t) * smoothstep(0.55, 0.8, lateral)
        toe = smoothstep(0.86, 0.93, t) * smoothstep(0.55, 0.35, h)
        collar = smoothstep(0.90, 0.97, h)
        accent.append(max(heel, stripe, toe, collar))
    for poly in me.polygons:
        for li in poly.loop_indices:
            a = accent[me.loops[li].vertex_index]
            col.data[li].color = (a, a, a, 1.0)
    return sum(1 for a in accent if a > 0.5)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    n = zones(bpy.data.objects["shoes"])
    arm = bpy.data.objects["Armature"]
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: shoe colour zones" % label)
    arm["fc_master_passes"] = history
    print("FC_PASS %s accent vertices %d" % (label, n))
    M.save_master(label)


main()
