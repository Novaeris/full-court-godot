"""Modeling pass on the master uniform (D-076):
1. JERSEY BINDING: the upper jersey (armholes, chest, shoulder straps) takes the skin's own weights, including the shoulders and clavicles, so raising an
   arm lifts the cloth with the chest instead of letting the skin poke through; below the armpit the arm influence fades out (the sides do not flap).
2. PANEL ZONES: the side panels are painted into the cloth as a vertex colour mask (green), from the geometry: along each side of the jersey and down the
   OUTER side of each shorts leg. The cloth shader draws the panel and its piping from the mask (no texture-coordinate artefacts between the legs).
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_uniform_fit.py -- --label <label>
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402

ARM = {"l_shoulder", "r_shoulder", "x_clavicle_l", "x_clavicle_r", "l_elbow", "r_elbow"}


def smoothstep(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


def rebind_jersey(jersey, skin, z_pit):
    """Blends shoulder and clavicle influence into the TOP of the jersey only (straps, armholes, upper chest), taken from the nearest TORSO skin (never
    from the arm: skin whose weight is mostly arm is excluded). Below the armpit the existing spine and pelvis weights stay untouched."""
    from mathutils.kdtree import KDTree
    sk_names = {g.index: g.name for g in skin.vertex_groups}
    sk_basis = skin.data.shape_keys.key_blocks[0].data if skin.data.shape_keys else skin.data.vertices
    torso_pts = []
    for v in skin.data.vertices:
        w = {sk_names[g.group]: g.weight for g in v.groups if g.weight > 0.001}
        arm_w = sum(x for n, x in w.items() if n in ("l_elbow", "r_elbow", "l_hand", "r_hand") or n.startswith("x_l_") or n.startswith("x_r_"))
        sh_w = sum(x for n, x in w.items() if n in ("l_shoulder", "r_shoulder"))
        if arm_w > 0.05 or sh_w > 0.55 or sk_basis[v.index].co.z < z_pit - 0.15:
            continue
        torso_pts.append((sk_basis[v.index].co.copy(), w))
    tree = KDTree(len(torso_pts))
    for k, (co, _) in enumerate(torso_pts):
        tree.insert(co, k)
    tree.balance()
    basis = jersey.data.shape_keys.key_blocks[0].data
    names = {g.index: g.name for g in jersey.vertex_groups}
    changed = 0
    for v in jersey.data.vertices:
        co = basis[v.index].co
        f = smoothstep(z_pit - 0.06, z_pit + 0.06, co.z)
        if f <= 0.0:
            continue
        _, k, _ = tree.find(co)
        target = torso_pts[k][1]
        current = {names[g.group]: g.weight for g in v.groups}
        mixed = {}
        for n in set(current) | set(target):
            mixed[n] = current.get(n, 0.0) * (1.0 - f) + target.get(n, 0.0) * f
        top = sorted(mixed.items(), key=lambda kv: -kv[1])[:4]
        total = sum(x for _, x in top) or 1.0
        for g in list(v.groups):
            jersey.vertex_groups[g.group].remove([v.index])
        for n, x in top:
            if x <= 0.0:
                continue
            if n not in jersey.vertex_groups:
                jersey.vertex_groups.new(name=n)
            jersey.vertex_groups[n].add([v.index], x / total, "REPLACE")
        changed += 1
    print("FC_PASS jersey top rebound: %d vertices" % changed)


def paint_panels(obj, dist_fn):
    """Stores each vertex's distance (metres) from the panel centre line in a second UV layer ("panel", u = distance). The shader cuts the panel and the
    piping at exact distances, so their edges are straight lines whatever the mesh density (a per-vertex mask would be jagged)."""
    me = obj.data
    basis = me.shape_keys.key_blocks[0].data if me.shape_keys else me.vertices
    layer = me.uv_layers.get("panel") or me.uv_layers.new(name="panel")
    dist = [dist_fn(basis[i].co) for i in range(len(basis))]
    for poly in me.polygons:
        for li in poly.loop_indices:
            layer.data[li].uv = (dist[me.loops[li].vertex_index], 0.0)
    me.uv_layers.active = me.uv_layers[0]
    return sum(1 for d in dist if d < 0.05)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    arm = bpy.data.objects["Armature"]
    b = arm.data.bones
    at = lambda n: arm.matrix_world @ b[n].head_local
    z_pit = at("l_shoulder").z - 0.10
    jersey, shorts, skin = bpy.data.objects["jersey"], bpy.data.objects["shorts"], bpy.data.objects["skin"]
    if "--panels-only" not in argv:
        rebind_jersey(jersey, skin, z_pit)
    cy = (at("torso").y + at("neck").y) * 0.5
    half_band = 0.045   # metres either side of the side line

    def jersey_mask(co):
        # distance along the surface (arc length) from the side line of the torso, where the direction is straight sideways
        return abs(abs(math.atan2(co.x, -(co.y - cy))) - math.pi / 2) * math.hypot(co.x, co.y - cy)

    hip = at("l_hip")
    z_crotch = hip.z - 0.07

    def shorts_mask(co):
        if co.z > z_crotch + 0.06:
            return jersey_mask(co)   # the waist: the same side line as the jersey
        cx = hip.x if co.x > 0 else -hip.x
        out = 1.0 if co.x > 0 else -1.0
        dx, dy = (co.x - cx) * out, co.y - hip.y
        return abs(math.atan2(dy, dx)) * math.hypot(dx, dy)    # 0 on the outer side of the leg

    nj = paint_panels(jersey, jersey_mask)
    ns = paint_panels(shorts, shorts_mask)
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: jersey rebound with faded arm weights; panel masks painted" % label)
    arm["fc_master_passes"] = history
    print("FC_PASS %s panel vertices jersey %d shorts %d" % (label, nj, ns))
    M.save_master(label)


main()
