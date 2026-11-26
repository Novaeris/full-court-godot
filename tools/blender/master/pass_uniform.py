"""Modeling pass on the master uniform (D-076): a basketball jersey HANGS from the chest (it does not cling to the waist), with soft vertical folds that
deepen toward the hem; basketball shorts have wide, straight legs. Works on the jersey and shorts objects of the master and moves the trim (binding)
with them. Every offset goes through master_lib.move_vertices, so the body morphs keep working.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_uniform.py -- --label <label> [--dry-run]
"""
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def smoothstep(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


def bones(arm):
    b = arm.data.bones
    return {n: arm.matrix_world @ b[n].head_local for n in ("pelvis", "torso", "neck", "l_shoulder", "l_hip", "r_hip", "l_knee")}


def hang(obj, centre_fn, z_top, z_bottom, bins=72, flare=0.04, fold_n=9, fold_amp=0.006, max_out=0.06, inner_hold=0.0):
    """Offsets that make cloth hang: below z_top each direction keeps at least the widest radius found above it (so it falls straight from the chest
    or the hips), flaring a little toward the hem, plus vertical folds. Returns {index: Vector}."""
    me = obj.data
    basis = me.shape_keys.key_blocks[0].data if me.shape_keys else me.vertices
    info = []
    for i in range(len(basis)):
        co = basis[i].co
        key, cx, cy = centre_fn(co)
        dx, dy = co.x - cx, co.y - cy
        th = math.atan2(dx, -dy)
        info.append((i, key, cx, cy, th, math.hypot(dx, dy), co.z))
    # widest radius per direction at or above each height (scan from the top)
    best = {}
    order = sorted(info, key=lambda r: -r[6])
    running = {}
    for i, key, cx, cy, th, r, z in order:
        b = (key, int((th + math.pi) / math.tau * bins) % bins)
        if z >= z_top:
            running[b] = max(running.get(b, 0.0), r)
        best[i] = running.get(b, r)
    # smooth the running radius across neighbouring directions
    offsets = {}
    for i, key, cx, cy, th, r, z in info:
        if z >= z_top:
            continue
        t = smoothstep(z_top, z_bottom, z)
        target = max(r, best[i]) * (1.0 + flare * t)
        target += fold_amp * t * (0.5 + 0.5 * math.cos(th * fold_n))
        target = min(target, r + max_out)
        d = target - r
        if d <= 0.0005:
            continue
        offsets[i] = Vector((math.sin(th) * d, -math.cos(th) * d, 0.0))
    return offsets


def smooth_offsets(obj, offsets, iterations=3):
    """Averages each offset with its mesh neighbours, so the reshaped cloth stays smooth."""
    me = obj.data
    nbrs = {i: [] for i in range(len(me.vertices))}
    for e in me.edges:
        a, b = e.vertices
        nbrs[a].append(b)
        nbrs[b].append(a)
    cur = dict(offsets)
    for _ in range(iterations):
        nxt = {}
        for i in cur:
            acc = Vector(cur[i])
            n = 1
            for j in nbrs[i]:
                if j in cur:
                    acc += cur[j]
                    n += 1
            nxt[i] = acc / n
        cur = nxt
    return cur


def bridge(obj, z_low, z_high, centre, iterations=25, factor=0.5):
    """Fabric bridges hollows: repeated smoothing of the cloth between z_low and z_high, keeping only movements AWAY from the body axis, so concave
    spots (between and under the pectorals, the sternum) fill in while the convex shape stays. Returns {index: Vector}."""
    me = obj.data
    basis = me.shape_keys.key_blocks[0].data if me.shape_keys else me.vertices
    pos = [basis[i].co.copy() for i in range(len(basis))]
    nbrs = {i: [] for i in range(len(pos))}
    for e in me.edges:
        a, b = e.vertices
        nbrs[a].append(b)
        nbrs[b].append(a)
    border = {i for i in nbrs if len(nbrs[i]) < 4}
    active = [i for i in range(len(pos)) if z_low < pos[i].z < z_high and i not in border]
    for _ in range(iterations):
        new = {}
        for i in active:
            if not nbrs[i]:
                continue
            avg = sum((pos[j] for j in nbrs[i]), Vector()) / len(nbrs[i])
            step = (avg - pos[i]) * factor
            radial = Vector((pos[i].x - centre.x, pos[i].y - centre.y, 0.0))
            if radial.length > 1e-6 and step.dot(radial.normalized()) > 0:
                new[i] = pos[i] + radial.normalized() * step.dot(radial.normalized())
        for i, p in new.items():
            pos[i] = p
    out = {}
    for i in active:
        d = pos[i] - basis[i].co
        if d.length > 0.0003:
            out[i] = d
    return out


def carry(trim, cloth_objects_offsets, reach=0.02):
    """The binding follows the cloth edge it sits on: each trim vertex takes the offset of the nearest moved cloth vertex within `reach` metres."""
    pts = []
    for obj, offsets in cloth_objects_offsets:
        basis = obj.data.shape_keys.key_blocks[0].data if obj.data.shape_keys else obj.data.vertices
        for i, d in offsets.items():
            pts.append((basis[i].co.copy(), d))
    if not pts:
        return {}
    tree = KDTree(len(pts))
    for k, (co, _) in enumerate(pts):
        tree.insert(co, k)
    tree.balance()
    tb = trim.data.shape_keys.key_blocks[0].data if trim.data.shape_keys else trim.data.vertices
    out = {}
    for i in range(len(tb)):
        co, k, dist = tree.find(tb[i].co)
        if dist is not None and dist < reach:
            out[i] = pts[k][1]
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    argv = argv
    arm = bpy.data.objects["Armature"]
    L = bones(arm)
    jersey, shorts, trim = bpy.data.objects["jersey"], bpy.data.objects["shorts"], bpy.data.objects["trim"]
    cy = (L["torso"].y + L["neck"].y) * 0.5
    strength = float(argv[argv.index("--strength") + 1]) if "--strength" in argv else 1.0
    z_chest = L["l_shoulder"].z - (0.20 if strength <= 1.0 else 0.13)
    j_off = hang(jersey, lambda co: ("t", 0.0, cy), z_chest, L["pelvis"].z - 0.10, flare=0.05 * strength, fold_n=9, fold_amp=0.007 * strength, max_out=0.07)
    j_off = smooth_offsets(jersey, j_off, 4)
    if "--bridge" in argv:
        j_off = bridge(jersey, L["pelvis"].z - 0.05, L["neck"].z - 0.05, Vector((0.0, cy, 0.0)))
    z_crotch = L["l_hip"].z - 0.07
    hx, hy = L["l_hip"].x, L["l_hip"].y

    def leg(co):
        if co.z > z_crotch:
            return ("p", 0.0, L["pelvis"].y)
        return ("l", hx, hy) if co.x > 0 else ("r", -hx, hy)

    s_off = hang(shorts, leg, L["l_hip"].z - 0.02, L["l_knee"].z + 0.07, flare=0.10, fold_n=6, fold_amp=0.005, max_out=0.05)
    s_off = smooth_offsets(shorts, s_off, 4)
    t_off = carry(trim, [(jersey, j_off), (shorts, s_off)])
    print("FC_PASS %s jersey %d, shorts %d, trim %d vertices moved; max jersey %.3f m" % (label, len(j_off), len(s_off), len(t_off),
          max((d.length for d in j_off.values()), default=0.0)))
    if "--dry-run" in argv:
        return
    M.move_vertices(jersey, j_off)
    M.move_vertices(shorts, s_off)
    M.move_vertices(trim, t_off)
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: jersey hang, shorts hang" % label)
    arm["fc_master_passes"] = history
    M.save_master(label)


main()
