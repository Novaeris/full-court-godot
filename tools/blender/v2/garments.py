"""V2 garments and equipment (D-075, milestones M5 and M6), made FROM the body so they fit every build:
  1. a region of the body surface is selected by bone landmarks and skin weights (torso for the jersey, pelvis and thighs for the shorts, ...),
  2. it is copied, pushed out along its normals by a looseness that varies with height (a jersey hangs looser at the hem, shorts flare), given folds,
     cloth thickness and a subdivision pass, and bordered with trim at its open edges,
  3. it is skinned by transferring the body weights, and bound to the body with a Surface Deform so every body morph (fcb_) is captured as a shape key.
Nothing here is third-party: the shapes are derived from our CC0 base mesh by project code."""
import math

import bmesh
import bpy
from mathutils import Vector

ARM_GROUPS = ("l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_hand", "r_hand")
HEAD_GROUPS = ("neck", "head")


def smoothstep(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


def landmarks(arm):
    """Rest positions (Blender units) of the joints the garments use."""
    b = arm.data.bones
    get = lambda n: (arm.matrix_world @ b[n].head_local)
    out = {n: get(n) for n in ("pelvis", "torso", "neck", "head", "l_shoulder", "r_shoulder", "l_elbow", "l_hand", "l_hip", "l_knee", "l_foot", "r_foot", "r_knee")}
    out["l_toe"] = get("x_l_toe") if "x_l_toe" in b else out["l_foot"]
    return out


def _weights(bm, obj):
    deform = bm.verts.layers.deform.active
    names = {g.index: g.name for g in obj.vertex_groups}
    return deform, names


def _group_weight(vert, deform, names, groups):
    total = 0.0
    for gi, w in vert[deform].items():
        n = names.get(gi, "")
        if n in groups or (groups is ARM_GROUPS and (n.startswith("x_l_") or n.startswith("x_r_")) and "toe" not in n):
            total += w   # every finger joint counts as arm
    return total


def relax_border(bm, iterations=10, amount=0.5):
    """Smooths the open edges of a cut region into clean curves (the cut follows mesh faces, so it is jagged before this)."""
    for _ in range(iterations):
        border = [v for v in bm.verts if any(len(e.link_faces) == 1 for e in v.link_edges)]
        moves = {}
        for v in border:
            nbrs = [e.other_vert(v) for e in v.link_edges if len(e.link_faces) == 1]
            if len(nbrs) == 2:
                avg = (nbrs[0].co + nbrs[1].co) * 0.5
                moves[v] = v.co.lerp(avg, amount)
        for v, co in moves.items():
            v.co = co


def region(skin, keep_face, name, cut_below=None, cut_above=None):
    """A new object holding the faces of `skin` (its Basis shape) for which keep_face(centroid, normal, arm_w, head_w, groups) is true."""
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    deform, names = _weights(bm, skin)
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()
        arm_w = sum(_group_weight(v, deform, names, ARM_GROUPS) for v in f.verts) / len(f.verts)
        head_w = sum(_group_weight(v, deform, names, HEAD_GROUPS) for v in f.verts) / len(f.verts)
        if not keep_face(c, f.normal, arm_w, head_w):
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # exact level hems: cut along a horizontal plane instead of along mesh faces
    for z, keep_above in ((cut_below, True), (cut_above, False)):
        if z is None:
            continue
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=keep_above, clear_outer=not keep_above)
    if cut_below is None and cut_above is None:
        relax_border(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if me.shape_keys:
        pass
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    for g in skin.vertex_groups:
        obj.vertex_groups.new(name=g.name)
    fill_small_holes(obj)
    return obj


def inflate(obj, offset_fn, folds=None):
    """Pushes every vertex out along its normal by offset_fn(co); folds(co) adds a fold displacement (also along the normal)."""
    me = obj.data
    me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
    for v in me.vertices:
        d = offset_fn(v.co)
        if folds is not None:
            d += folds(v.co)
        v.co = v.co + v.normal * d
    me.update()


def finish(obj, thickness=0.004, subdiv=0):
    """Cloth thickness and a smoothing subdivision, applied."""
    bpy.context.view_layer.objects.active = obj
    if thickness > 0:
        m = obj.modifiers.new("solid", "SOLIDIFY")
        m.thickness = thickness
        m.offset = -1.0
        m.use_even_offset = True
        m.use_quality_normals = True
        m.use_rim_only = True   # the cloth edge shows a thickness; no second shell (the cloth shader is double sided)
        bpy.ops.object.modifier_apply(modifier=m.name)
    if subdiv > 0:
        m = obj.modifiers.new("sub", "SUBSURF")
        m.levels = subdiv
        m.render_levels = subdiv
        bpy.ops.object.modifier_apply(modifier=m.name)
    for p in obj.data.polygons:
        p.use_smooth = True


def transfer_weights(obj, skin):
    """Skins `obj` with the body weights (nearest face, interpolated), at most four bones a vertex, normalised."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    m = obj.modifiers.new("weights", "DATA_TRANSFER")
    m.object = skin
    m.use_vert_data = True
    m.data_types_verts = {"VGROUP_WEIGHTS"}
    m.vert_mapping = "POLYINTERP_NEAREST"
    bpy.ops.object.datalayout_transfer(modifier=m.name)
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def drop_groups(obj, keep_shoulders=False):
    """Removes arm, hand and finger influence from a garment (a hand hanging beside the shorts must not drag the cloth with it)."""
    for g in list(obj.vertex_groups):
        n = g.name
        arm = n in ("l_elbow", "r_elbow", "l_hand", "r_hand") or ((n.startswith("x_l_") or n.startswith("x_r_")) and "toe" not in n)
        if not keep_shoulders:
            arm = arm or n in ("l_shoulder", "r_shoulder")
        if arm:
            obj.vertex_groups.remove(g)


def fill_unweighted(obj):
    """Every vertex must have a bone weight (else the exporter adds a stray bone): an unweighted vertex copies its nearest weighted neighbour."""
    from mathutils.kdtree import KDTree
    me = obj.data
    weighted = [v for v in me.vertices if any(g.weight > 0.0001 for g in v.groups)]
    empty = [v for v in me.vertices if not any(g.weight > 0.0001 for g in v.groups)]
    if not empty or not weighted:
        return len(empty)
    tree = KDTree(len(weighted))
    for i, v in enumerate(weighted):
        tree.insert(v.co, i)
    tree.balance()
    for v in empty:
        _, i, _ = tree.find(v.co)
        for g in weighted[i].groups:
            obj.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")
    return len(empty)


def box_uv(obj, scale=4.0):
    """A simple projection for pieces that need texture coordinates only for shading (trim, shoes, soles, laces)."""
    me = obj.data
    if me.uv_layers:
        return
    layer = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(n.z) > max(abs(n.x), abs(n.y)):
                layer.data[li].uv = (co.x * scale, co.y * scale)
            elif abs(n.x) > abs(n.y):
                layer.data[li].uv = (co.y * scale, co.z * scale)
            else:
                layer.data[li].uv = (co.x * scale, co.z * scale)


def bind_morphs(obj, skin, key_names):
    """Captures each body morph of `skin` as a shape key of `obj` through a Surface Deform binding."""
    for kb in skin.data.shape_keys.key_blocks[1:]:
        kb.value = 0.0
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    m = obj.modifiers.new("follow", "SURFACE_DEFORM")
    m.target = skin
    bpy.ops.object.surfacedeform_bind(modifier=m.name)
    if obj.data.shape_keys is None:
        obj.shape_key_add(name="Basis", from_mix=False)
    for name in key_names:
        skin.data.shape_keys.key_blocks[name].value = 1.0
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        coords = [v.co.copy() for v in me.vertices]
        ev.to_mesh_clear()
        k = obj.shape_key_add(name=name, from_mix=False)
        for i, c in enumerate(coords):
            k.data[i].co = c
        skin.data.shape_keys.key_blocks[name].value = 0.0
    obj.modifiers.remove(m)


def cylinder_uv(obj, z0, span):
    """u around the body (0.5 at the front centre, the seam at the back), v up from z0 over `span` metres: the layout of the jersey graphics."""
    me = obj.data
    layer = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for poly in me.polygons:
        coords = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            coords.append([0.5 + math.atan2(co.x, -co.y) / math.tau, (co.z - z0) / span])
        us = [c[0] for c in coords]
        if max(us) - min(us) > 0.5:
            for c in coords:
                if c[0] < 0.5:
                    c[0] += 1.0
        for li, c in zip(poly.loop_indices, coords):
            layer.data[li].uv = c


def border_loops(obj):
    """Ordered vertex loops along the open edges of a mesh (for trim)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    adj = {}
    for e in bm.edges:
        if len(e.link_faces) == 1:
            a, b = e.verts[0].index, e.verts[1].index
            adj.setdefault(a, []).append(b)
            adj.setdefault(b, []).append(a)
    coords = {i: bm.verts[i].co.copy() for i in adj}
    normals = {i: bm.verts[i].normal.copy() for i in adj}
    bm.free()
    seen, loops = set(), []
    for start in adj:
        if start in seen:
            continue
        loop, cur, prev = [start], start, None
        seen.add(start)
        while True:
            nxt = [n for n in adj[cur] if n != prev and n not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        loops.append([(coords[i], normals[i]) for i in loop])
    return loops


def trim(name, loops, radius, min_points=8, outward=0.002):
    """A flat tube along each loop (a binding or a rib knit), as a new object."""
    bm = bmesh.new()
    segs = 6
    for loop in loops:
        if len(loop) < min_points:
            continue
        pts = [c + n * outward for c, n in loop]
        edge = sum((loop[i][0] - loop[i - 1][0]).length for i in range(1, len(loop))) / max(len(loop) - 1, 1)
        if (loop[0][0] - loop[-1][0]).length < 3.0 * edge:
            pts.append(loop[0][0] + loop[0][1] * outward)   # close only a true loop (an open chain closed would cut across the garment)
        first = len(bm.verts)
        for i, p in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            t = (b - a).normalized()
            nrm = loop[min(i, len(loop) - 1)][1]
            bn = t.cross(nrm).normalized()
            for k in range(segs):
                th = math.tau * k / segs
                bm.verts.new(p + nrm * (radius * 0.6 * math.cos(th)) + bn * (radius * math.sin(th)))
        bm.verts.ensure_lookup_table()
        for i in range(len(pts) - 1):
            for k in range(segs):
                a = first + i * segs + k
                b = first + i * segs + (k + 1) % segs
                c = first + (i + 1) * segs + (k + 1) % segs
                d = first + (i + 1) * segs + k
                try:
                    bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[c], bm.verts[d]))
                except ValueError:
                    pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def drape(obj, group_fn, z_start, slack_fn, taper=0.12, bins=64, dz=0.01, smooth_t=3, smooth_z=3, folds=None):
    """Cloth that HANGS instead of clinging. Around an axis per group (group_fn(co) -> (key, cx, cy)), the radius of the cloth in each direction is the
    widest the body gets above that height (from z_start down, narrowing by `taper` metres per metre), smoothed across directions and heights so small
    bumps (nipples, navel, the hollow of the back) disappear, plus slack_fn(z). folds(theta, z) adds gentle vertical folds."""
    me = obj.data
    pts = []
    for v in me.vertices:
        key, cx, cy = group_fn(v.co)
        dx, dy = v.co.x - cx, v.co.y - cy
        th = math.atan2(dx, -dy)
        pts.append((v.index, key, cx, cy, th, math.hypot(dx, dy), v.co.z))
    tables = {}
    for idx, key, cx, cy, th, r, z in pts:
        tb = tables.setdefault(key, {})
        ti = int((th + math.pi) / math.tau * bins) % bins
        zi = int(math.floor(z / dz))
        tb[(ti, zi)] = max(tb.get((ti, zi), 0.0), r)
    profiles = {}
    for key, tb in tables.items():
        zs = sorted({zi for _, zi in tb}, reverse=True)
        prof = {}
        for ti in range(bins):
            run = 0.0
            for zi in zs:
                body = tb.get((ti, zi), 0.0)
                if zi * dz >= z_start:
                    run = body if body > 0 else run   # above the start the cloth follows the body
                else:
                    run = max(body, run - taper * dz)
                prof[(ti, zi)] = run
        # smooth across directions and heights
        sm = {}
        for (ti, zi), _ in prof.items():
            acc, n = 0.0, 0
            for a in range(-smooth_t, smooth_t + 1):
                for b in range(-smooth_z, smooth_z + 1):
                    val = prof.get(((ti + a) % bins, zi + b))
                    if val:
                        acc += val
                        n += 1
            sm[(ti, zi)] = acc / max(n, 1)
        profiles[key] = sm
    for idx, key, cx, cy, th, r, z in pts:
        ti = int((th + math.pi) / math.tau * bins) % bins
        zi = int(math.floor(z / dz))
        R = min(max(profiles[key].get((ti, zi), r), r * 0.98), r + 0.045) + slack_fn(z)   # never further than 4.5 cm from the body
        if folds is not None:
            R += folds(th, z)
        me.vertices[idx].co.x = cx + math.sin(th) * R
        me.vertices[idx].co.y = cy - math.cos(th) * R
    me.update()


def smooth_mesh(obj, iterations=4, factor=0.5):
    """Laplacian smoothing that keeps the open edges in place (removes leftover body detail from cloth)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    inner = [v for v in bm.verts if all(len(e.link_faces) == 2 for e in v.link_edges)]
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=factor, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(obj.data)
    bm.free()


# --- the garments -------------------------------------------------------------------------------------------------------------------------------

def jersey(skin, L):
    z_hem = L["pelvis"].z - 0.10
    z_pit = L["l_shoulder"].z - 0.11
    sx = L["l_shoulder"].x

    neck_half = 0.085      # half the neck opening at the top of the straps
    strap_out = 0.150      # the outer edge of the 6 cm strap
    arm_cx = sx + 0.02     # the armhole is an ellipse centred just outside the shoulder joint
    arm_rx = arm_cx - strap_out
    arm_cz = L["l_shoulder"].z - 0.03

    def keep(c, n, arm_w, head_w):
        if c.z < z_hem or arm_w > 0.25 or head_w > 0.2:
            return False
        dx = abs(c.x) - arm_cx
        dz = c.z - arm_cz
        if (dx / arm_rx) ** 2 + (dz / 0.22) ** 2 < 1.0:
            return False   # curved armhole, deep enough to free the shoulder
        top = L["neck"].z + 0.03
        if c.y < 0 and (c.x / neck_half) ** 2 + ((c.z - top) / 0.16) ** 2 < 1.0:
            return False   # rounded scoop neckline in front
        if c.y >= 0 and (c.x / (neck_half - 0.005)) ** 2 + ((c.z - top) / 0.075) ** 2 < 1.0:
            return False   # shallower round neckline at the back
        return True

    obj = region(skin, keep, "jersey")
    centre_y = (L["torso"].y + L["neck"].y) * 0.5
    z_chest = L["l_shoulder"].z - 0.26
    drape(obj, lambda co: ("torso", 0.0, centre_y), z_chest, lambda z: 0.016 + 0.012 * smoothstep(z_chest, z_hem, z), taper=0.40,
          folds=lambda th, z: 0.005 * smoothstep(L["torso"].z + 0.05, z_hem, z) * math.sin(th * 9.0))
    smooth_mesh(obj, 3)
    return obj


def shorts(skin, L):
    z_top = L["pelvis"].z + 0.05
    z_hem = L["l_knee"].z + 0.07

    def keep(c, n, arm_w, head_w):
        return z_hem - 0.03 < c.z < z_top + 0.03 and arm_w < 0.2

    obj = region(skin, keep, "shorts", cut_below=z_hem, cut_above=z_top)
    z_crotch = L["l_hip"].z - 0.07
    hip_x, hip_y = L["l_hip"].x, L["l_hip"].y

    def group(co):
        if co.z > z_crotch:
            return ("pelvis", 0.0, L["pelvis"].y)
        return ("l", hip_x, hip_y) if co.x > 0 else ("r", -hip_x, hip_y)

    drape(obj, group, L["pelvis"].z - 0.02, lambda z: 0.014 + 0.012 * smoothstep(z_crotch, z_hem, z), taper=-0.02,
          folds=lambda th, z: 0.003 * smoothstep(z_crotch, z_hem, z) * math.sin(th * 6.0))
    smooth_mesh(obj, 3)
    return obj


def socks(skin, L):
    z_top = L["l_knee"].z - 0.23
    z_low = 0.07   # the sock ends inside the shoe

    def keep(c, n, arm_w, head_w):
        return z_low - 0.03 < c.z < z_top + 0.03 and arm_w < 0.2

    obj = region(skin, keep, "socks", cut_below=z_low, cut_above=z_top)
    inflate(obj, lambda co: 0.0035)
    return obj


def _slice_loft(bm, stations, segs=20, n=0.6):
    """Super-ellipse sections along Y: station = (y, x_centre, half_width, z_bottom, z_top). Closed at both ends."""
    first = len(bm.verts)
    for y, xc, hw, zb, zt in stations:
        zc, hz = (zb + zt) * 0.5, max((zt - zb) * 0.5, 0.001)
        for k in range(segs):
            th = math.tau * k / segs
            s, c = math.sin(th), math.cos(th)
            bm.verts.new((xc + hw * math.copysign(abs(s) ** n, s), y, zc + hz * math.copysign(abs(c) ** n, c)))
    bm.verts.ensure_lookup_table()
    for i in range(len(stations) - 1):
        for k in range(segs):
            q = [first + i * segs + k, first + i * segs + (k + 1) % segs, first + (i + 1) * segs + (k + 1) % segs, first + (i + 1) * segs + k]
            try:
                bm.faces.new([bm.verts[j] for j in q])
            except ValueError:
                pass
    for idx in (0, len(stations) - 1):
        try:
            bm.faces.new([bm.verts[first + idx * segs + k] for k in range(segs)])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def shoes(skin, L):
    """Basketball shoes (M6, V2.1): built along each foot from measured slices. A rubber cupsole (wider than the foot, rounded toe and heel, slight
    toe spring), a padded upper that rises to a high collar behind the ankle, a tongue, laces across the instep and a heel tab.
    Returns (upper, sole, laces). The bare foot inside is removed from the skin by hide_feet()."""
    uppers, soles, laces = bmesh.new(), bmesh.new(), bmesh.new()
    ankle_z = L["l_foot"].z
    for side in (1.0, -1.0):
        pts = [v.co for v in skin.data.vertices if v.co.z < ankle_z + 0.02 and v.co.x * side > 0.02]
        if len(pts) < 20:
            continue
        toe_y, heel_y = min(p.y for p in pts), max(p.y for p in pts)
        length = heel_y - toe_y
        cx = sum(p.x for p in pts) / len(pts)
        # foot half-width per slice (measured), smoothed
        n_sl = 14
        widths = []
        for i in range(n_sl + 1):
            y = heel_y - length * i / n_sl
            band = [p for p in pts if abs(p.y - y) < length / n_sl and p.z < 0.06]
            w = (max(p.x for p in band) - min(p.x for p in band)) * 0.5 if band else 0.03
            xc = (max(p.x for p in band) + min(p.x for p in band)) * 0.5 if band else cx
            widths.append((w, xc))
        sole_st, upper_st = [], []
        for i in range(n_sl + 1):
            t = i / n_sl                         # 0 heel .. 1 toe
            y = heel_y + 0.012 - (length + 0.030) * t
            w, xc = widths[i]
            round_end = max(0.0, 1.0 - abs((t - 0.5) / 0.5) ** 5) ** 0.35   # a rounded heel and a round toe box, not a point
            spring = 0.012 * smoothstep(0.8, 1.0, t)
            w = max(w, 0.036)
            hw_sole = (w + 0.016) * (0.45 + 0.55 * round_end)
            sole_st.append((y, xc, hw_sole, spring, 0.034 + spring))
            # upper height profile: high collar at the heel, the instep, the low toe box
            top = 0.150 - 0.030 * smoothstep(0.05, 0.40, t) - 0.055 * smoothstep(0.50, 0.95, t)   # collar, tongue and instep, toe box
            hw_up = (w + 0.011) * (0.42 + 0.58 * round_end)
            upper_st.append((y, xc, hw_up, 0.026 + spring, top + spring))
        tmp_s, tmp_u = bmesh.new(), bmesh.new()
        _slice_loft(tmp_s, sole_st, 22, 0.45)
        _slice_loft(tmp_u, upper_st, 22, 0.75)
        for _ in range(2):
            bmesh.ops.smooth_vert(tmp_u, verts=tmp_u.verts[:], factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        _append(soles, tmp_s)
        _append(uppers, tmp_u)
        tmp_s.free()
        tmp_u.free()
        # tongue: a padded strip up the front of the ankle
        mid = upper_st[n_sl // 3]
        _bar(laces, Vector((mid[1], mid[0] - 0.018, mid[4] - 0.012)), Vector((mid[1], mid[0] - 0.006, mid[4] + 0.018)),
             Vector((mid[1], mid[0] + 0.008, mid[4] + 0.034)), 0.011)
        # laces: six crossing bars on the instep, on the upper surface
        for k in range(6):
            i = int(n_sl * (0.34 + 0.07 * k))
            y, xc, hw, zb, zt = upper_st[i]
            z = zt + 0.002
            _bar(laces, Vector((xc - hw * 0.45, y + 0.004, z - 0.006)), Vector((xc, y, z + 0.002)), Vector((xc + hw * 0.45, y - 0.004, z - 0.006)), 0.0024)
        # heel tab
        y, xc, hw, zb, zt = upper_st[0]
        _bar(laces, Vector((xc, y + 0.006, zt - 0.03)), Vector((xc, y + 0.012, zt - 0.005)), Vector((xc, y + 0.010, zt + 0.012)), 0.006)
    out = []
    for name, b in (("shoes", uppers), ("sole", soles), ("laces", laces)):
        me = bpy.data.meshes.new(name)
        b.to_mesh(me)
        b.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        for p in o.data.polygons:
            p.use_smooth = True
        out.append(o)
    return out


def hide_feet(skin, L):
    """Removes the skin faces inside the shoes (every player wears shoes): no toes through the upper, fewer triangles."""
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    limit = 0.085   # below the lowest top line of the upper (the toe box)
    doomed = [f for f in bm.faces if f.calc_center_median().z < limit and all(v.co.z < limit + 0.01 for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    bm.to_mesh(skin.data)
    bm.free()
    return len(doomed)


def fill_small_holes(obj, max_perimeter=0.25):
    """Closes the small holes a region cut leaves (a face whose arm or head weight crossed the threshold), never the openings of the garment."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    boundary = [e for e in bm.edges if len(e.link_faces) == 1]
    seen = set()
    small = []
    for e in boundary:
        if e.index in seen:
            continue
        loop, stack = [], [e]
        while stack:
            cur = stack.pop()
            if cur.index in seen:
                continue
            seen.add(cur.index)
            loop.append(cur)
            for v in cur.verts:
                for nb in v.link_edges:
                    if len(nb.link_faces) == 1 and nb.index not in seen:
                        stack.append(nb)
        if sum(x.calc_length() for x in loop) < max_perimeter:
            small += loop
    if small:
        bmesh.ops.holes_fill(bm, edges=small, sides=0)
    bm.to_mesh(obj.data)
    bm.free()


def _append(dst, src):
    mapping = {}
    for v in src.verts:
        mapping[v] = dst.verts.new(v.co)
    for f in src.faces:
        try:
            dst.faces.new([mapping[v] for v in f.verts])
        except ValueError:
            pass


def _bar(bm, a, mid, b, radius, segs=6):
    """A small tube a -> mid -> b."""
    pts = [a, mid, b]
    first = len(bm.verts)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, 2)] - pts[max(i - 1, 0)]).normalized()
        n = t.cross(Vector((0, 0, 1)))
        if n.length < 1e-4:
            n = t.cross(Vector((1, 0, 0)))
        n.normalize()
        bn = t.cross(n).normalized()
        for k in range(segs):
            th = math.tau * k / segs
            bm.verts.new(p + n * radius * math.cos(th) + bn * radius * math.sin(th))
    bm.verts.ensure_lookup_table()
    for i in range(2):
        for k in range(segs):
            q = [first + i * segs + k, first + i * segs + (k + 1) % segs, first + (i + 1) * segs + (k + 1) % segs, first + (i + 1) * segs + k]
            try:
                bm.faces.new([bm.verts[j] for j in q])
            except ValueError:
                pass


def equipment(skin, L):
    """M6 equipment as thin shells from the body: arm sleeves, knee sleeves and wristbands for each side. Returns {name: object}."""
    out = {}
    for side, sx in (("l", 1.0), ("r", -1.0)):
        hand_z = L["l_hand"].z
        sh_z = L["l_shoulder"].z

        def arm_keep(c, n, arm_w, head_w, sx=sx, lo=hand_z + 0.05, hi=sh_z - 0.09):
            return arm_w > 0.6 and lo < c.z < hi and c.x * sx > 0.0

        def wrist_keep(c, n, arm_w, head_w, sx=sx, lo=hand_z + 0.012, hi=hand_z + 0.07):
            return arm_w > 0.6 and lo < c.z < hi and c.x * sx > 0.0

        def knee_keep(c, n, arm_w, head_w, sx=sx, lo=L["l_knee"].z - 0.09, hi=L["l_knee"].z + 0.10):
            return arm_w < 0.2 and lo < c.z < hi and c.x * sx > 0.0

        cuts = {"equip_armsleeve_": (hand_z + 0.05, sh_z - 0.09), "equip_wristband_": (hand_z + 0.012, hand_z + 0.07),
                "equip_kneesleeve_": (L["l_knee"].z - 0.09, L["l_knee"].z + 0.10)}
        for name, keep, off in (("equip_armsleeve_" + side, arm_keep, 0.0022), ("equip_wristband_" + side, wrist_keep, 0.005),
                                ("equip_kneesleeve_" + side, knee_keep, 0.003)):
            lo, hi = cuts[name[:-1]]
            loose = lambda c, n, a, h, k=keep, lo=lo, hi=hi: k(c.copy() if lo + 0.02 < c.z < hi - 0.02 else Vector((c.x, c.y, (lo + hi) * 0.5)), n, a, h)
            obj = region(skin, loose, name, cut_below=lo, cut_above=hi)
            inflate(obj, lambda co, off=off: off)
            out[name] = obj
    return out


def sleeve(skin, L, name, z_low, z_high, side_x, offset=0.003):
    def keep(c, n, arm_w, head_w):
        return z_low < c.z < z_high and (side_x is None or c.x * side_x > 0.02)

    obj = region(skin, keep, name)
    inflate(obj, lambda co: offset)
    return obj
