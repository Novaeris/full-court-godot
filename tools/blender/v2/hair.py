"""V2 hair, facial hair and head accessories (D-075, milestone M4), made from the scalp and face of the body so they fit every head shape.
Every style is real geometry: a shell over the scalp (or face) whose vertices carry a hair DENSITY (vertex colour red: 0 none, 1 full) that the game shader
turns into hair thinning into skin, which gives fades, tapers and natural hairlines; volume styles add displaced geometry (curls, afro); braids, cornrows
and dreadlocks add real strand tubes. The shells are bound to the body with the same Surface Deform capture as the garments, so face morphs reshape them."""
import math

import bmesh
import bpy
from mathutils import Vector

import garments as G

# identity hair value -> V2 style meshes (the game picks one of the list by the player key)
STYLES = ["buzz", "low_fade", "high_fade", "taper", "short_curls", "afro", "cornrows", "braids", "dreads", "long"]
FACIAL = ["stubble", "mustache", "goatee", "beard_short", "beard_full"]


def head_frame(skin):
    """Centre of the skull, top of the head, and the scale (head height) from the head-weighted vertices."""
    gi = skin.vertex_groups["head"].index
    pts = [v.co for v in skin.data.vertices if any(g.group == gi and g.weight > 0.6 for g in v.groups)]
    top = max(p.z for p in pts)
    chin = min(p.z for p in pts)
    hh = top - chin
    centre = Vector((0.0, sum(p.y for p in pts) / len(pts) + 0.01, top - hh * 0.42))
    nose = min(pts, key=lambda p: p.y)
    return {"centre": centre, "top": top, "chin": chin, "hh": hh, "nose": nose}


def angles(co, F):
    d = co - F["centre"]
    th = math.atan2(d.x, -d.y)                      # 0 at the front
    phi = math.asin(max(-1.0, min(1.0, d.z / max(d.length, 1e-6))))   # elevation
    return th, phi, d.length


def hairline(th, lift=0.0):
    """The lowest elevation (radians) of the hair at azimuth th: high at the forehead, low at the nape, around the ears in between."""
    c = math.cos(th)
    front = 0.42 + lift
    side = 0.10 + lift * 0.5
    back = -0.62 + lift * 0.3
    if c >= 0:
        return side + (front - side) * c ** 1.5
    return side + (back - side) * (-c) ** 1.2


def _ear_gap(th, phi):
    """True near the ears, where short hair leaves skin (a hair shell over the ear would look like a helmet)."""
    s = abs(math.sin(th))
    return s > 0.85 and phi < 0.20 and math.cos(th) > -0.45


def scalp(skin, F, name, lift=0.0, margin=0.08):
    def keep(c, n, arm_w, head_w):
        if head_w < 0.5:
            return False
        th, phi, _ = angles(c, F)
        return phi > hairline(th, lift) - margin and not _ear_gap(th, phi)
    return G.region(skin, keep, name)


def set_density(obj, F, fn, offset_fn, bumps=None):
    """Writes the density (vertex colour) and pushes every vertex out along its normal by offset_fn(th, phi, density)."""
    me = obj.data
    if not me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    col = me.color_attributes[0]
    dens = []
    for v in me.vertices:
        th, phi, _ = angles(v.co, F)
        d = max(0.0, min(1.0, fn(th, phi)))
        dens.append(d)
        off = offset_fn(th, phi, d)
        if bumps is not None:
            off += bumps(v.co) * d
        v.co = v.co + v.normal * off
    for poly in me.polygons:
        for li in poly.loop_indices:
            d = dens[me.loops[li].vertex_index]
            col.data[li].color = (d, d, d, 1.0)
    me.update()


def sphere_uv(obj, F):
    """u around the head, v up it: hair strands run along v in the shader."""
    me = obj.data
    layer = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for poly in me.polygons:
        coords = []
        for li in poly.loop_indices:
            th, phi, _ = angles(me.vertices[me.loops[li].vertex_index].co, F)
            coords.append([0.5 + th / math.tau, 0.5 + phi / math.pi])
        us = [c[0] for c in coords]
        if max(us) - min(us) > 0.5:
            for c in coords:
                if c[0] < 0.5:
                    c[0] += 1.0
        for li, c in zip(poly.loop_indices, coords):
            layer.data[li].uv = c


def curls(scale, amount):
    def f(co):
        return amount * (0.5 + 0.5 * math.sin(co.x * scale) * math.sin(co.y * scale * 1.13 + 1.7) * math.sin(co.z * scale * 0.91 + 0.6))
    return f


def tubes(name, paths, radius_fn, segs=6):
    """Strand tubes (braids, dreadlocks) along paths of points."""
    bm = bmesh.new()
    for path in paths:
        first = len(bm.verts)
        n = len(path)
        for i, p in enumerate(path):
            t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            a = t.cross(ref).normalized()
            b = t.cross(a).normalized()
            r = radius_fn(i / max(n - 1, 1), i)
            for k in range(segs):
                ang = math.tau * k / segs
                bm.verts.new(p + a * r * math.cos(ang) + b * r * math.sin(ang))
        bm.verts.ensure_lookup_table()
        for i in range(n - 1):
            for k in range(segs):
                q = [first + i * segs + k, first + i * segs + (k + 1) % segs, first + (i + 1) * segs + (k + 1) % segs, first + (i + 1) * segs + k]
                try:
                    bm.faces.new([bm.verts[j] for j in q])
                except ValueError:
                    pass
        try:
            bm.faces.new([bm.verts[first + (n - 1) * segs + k] for k in range(segs)])
        except ValueError:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    for p in me.polygons:
        p.use_smooth = True
    return obj


def _dir(th, phi):
    return Vector((math.sin(th) * math.cos(phi), -math.cos(th) * math.cos(phi), math.sin(phi)))


def _surface_point(F, th, phi, offset, tree):
    """The point of the scalp in direction (th, phi), pushed out by offset (ray cast from the skull centre)."""
    d = Vector((math.sin(th) * math.cos(phi), -math.cos(th) * math.cos(phi), math.sin(phi)))
    hit = tree.ray_cast(F["centre"] + d * 0.3, -d)
    if hit[0] is None:
        return F["centre"] + d * 0.11
    return hit[0] + d * offset


def _paint_full(obj):
    me = obj.data
    if not me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    col = me.color_attributes[0]
    for i in range(len(col.data)):
        col.data[i].color = (1.0, 1.0, 1.0, 1.0)


def _join(a, b):
    bpy.ops.object.select_all(action="DESELECT")
    a.select_set(True)
    b.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.object.join()
    return a


def volume(obj, F, extra, hl_lift=0.0, curl=None):
    """A rounded hair volume measured from the skull centre (no crumpling): each vertex moves out to the skull radius + extra(phi) along its direction from
    the centre, blending from the scalp at the hairline to the full volume above it, then smoothed; curl adds clumps."""
    me = obj.data
    for v in me.vertices:
        d = v.co - F["centre"]
        r = d.length
        th, phi, _ = angles(v.co, F)
        w = G.smoothstep(hairline(th, hl_lift) - 0.02, hairline(th, hl_lift) + 0.35, phi)
        target = r + extra(th, phi) * w + 0.003
        if curl is not None:
            target += curl(v.co) * w
        v.co = F["centre"] + d.normalized() * target
    me.update()
    G.smooth_mesh(obj, 5, 0.45)


def lock_paths(F, tree, roots, length, hang_out=0.004):
    """Locks that start on the scalp, FLOW along it away from the face (back and down) while above the ears, then hang. roots: [(th, phi)]."""
    paths = []
    ear_z = F["centre"].z - F["hh"] * 0.10
    for th, phi in roots:
        p = _surface_point(F, th, phi, 0.004, tree)
        pts = [p.copy()]
        travelled = 0.0
        step = length / 14.0
        while travelled < length and len(pts) < 40:
            if p.z > ear_z:
                n = (p - F["centre"]).normalized()
                flow = Vector((0.0, 1.0, -1.4))
                flow = (flow - n * flow.dot(n)).normalized()
                q = p + flow * step
                hit = tree.ray_cast(F["centre"] + (q - F["centre"]).normalized() * 0.3, -(q - F["centre"]).normalized())
                if hit[0] is not None:
                    q = hit[0] + (q - F["centre"]).normalized() * 0.006
            else:
                out = Vector((p.x - F["centre"].x, p.y - F["centre"].y, 0.0))
                out = out.normalized() if out.length > 1e-4 else Vector((0, 1, 0))
                q = p + Vector((0.0, 0.0, -step)) + out * hang_out
            travelled += (q - p).length
            p = q
            pts.append(p.copy())
        paths.append(pts)
    return paths


def scalp_roots(count, front_clear=0.55, rows=3):
    """Root directions spread over the scalp, none on the forehead."""
    roots = []
    per = max(count // rows, 1)
    for r in range(rows):
        phi = 1.15 - 0.33 * r
        for k in range(per):
            th = -math.pi + math.tau * (k + 0.5 * (r % 2)) / per
            if math.cos(th) > 0.45:
                if r != 0:
                    continue   # no lock rooted at the front of the head: it would fall over the face
                phi = 1.38     # front roots sit on the crown and flow back
            roots.append((th, phi))
    return roots


def build_style(skin, style):
    from mathutils.bvhtree import BVHTree
    F = head_frame(skin)
    hh = F["hh"]
    name = "hair_" + style
    if style == "buzz":
        obj = scalp(skin, F, name)
        set_density(obj, F, lambda th, phi: 0.7 * G.smoothstep(hairline(th) - 0.05, hairline(th) + 0.06, phi), lambda th, phi, d: 0.0018)
    elif style in ("low_fade", "high_fade"):
        lo, hi = (0.03, 0.42) if style == "low_fade" else (0.20, 0.75)
        obj = scalp(skin, F, name)
        set_density(obj, F, lambda th, phi: G.smoothstep(hairline(th) + lo, hairline(th) + hi, phi) * 0.95 + 0.25 * G.smoothstep(hairline(th) - 0.04, hairline(th) + 0.05, phi) * (1 - G.smoothstep(hairline(th) + lo, hairline(th) + hi, phi)),
                    lambda th, phi, d: 0.0015 + 0.010 * d * G.smoothstep(0.35, 0.9, phi))
    elif style == "taper":
        obj = scalp(skin, F, name)
        set_density(obj, F, lambda th, phi: G.smoothstep(hairline(th) - 0.03, hairline(th) + 0.16, phi),
                    lambda th, phi, d: 0.002 + 0.016 * d * G.smoothstep(0.25, 0.85, phi))
    elif style == "short_curls":
        obj = scalp(skin, F, name)
        set_density(obj, F, lambda th, phi: G.smoothstep(hairline(th) - 0.03, hairline(th) + 0.10, phi), lambda th, phi, d: 0.0)
        volume(obj, F, lambda th, phi: 0.022, curl=curls(240.0, 0.006))
    elif style == "afro":
        obj = scalp(skin, F, name, lift=-0.05)
        set_density(obj, F, lambda th, phi: G.smoothstep(hairline(th, -0.05) - 0.03, hairline(th, -0.05) + 0.12, phi), lambda th, phi, d: 0.0)
        volume(obj, F, lambda th, phi: 0.045 + 0.018 * max(0.0, math.sin(phi)), hl_lift=-0.05, curl=curls(130.0, 0.010))
    elif style in ("cornrows", "braids", "dreads"):
        obj = scalp(skin, F, name)
        set_density(obj, F, lambda th, phi: 0.85 * G.smoothstep(hairline(th) - 0.03, hairline(th) + 0.06, phi), lambda th, phi, d: 0.0025)
        bm = bmesh.new()
        bm.from_mesh(skin.data)
        tree = BVHTree.FromBMesh(bm)
        bm.free()
        paths = []
        rows = 9 if style == "cornrows" else (14 if style == "braids" else 11)
        for r in range(rows):
            th = -1.15 + 2.3 * r / (rows - 1)
            if style == "cornrows":
                # a row runs from the front hairline over the crown to the nape, following the skull
                start = _dir(th * 0.9, hairline(th * 0.9) + 0.09)
                crown = (_dir(th * 0.5, 1.2) + Vector((0, 0, 0.3))).normalized()
                end = _dir(math.pi - th * 0.55, hairline(math.pi) + 0.08)
                pts = []
                for k in range(20):
                    t = k / 19
                    d = (start.lerp(crown, t * 2.0) if t < 0.5 else crown.lerp(end, (t - 0.5) * 2.0)).normalized()
                    hit = tree.ray_cast(F["centre"] + d * 0.3, -d)
                    pts.append((hit[0] if hit[0] is not None else F["centre"] + d * 0.11) + d * 0.004)
                paths.append(pts)
        if style != "cornrows":
            count = 30 if style == "braids" else 22
            paths = lock_paths(F, tree, scalp_roots(count), hh * (0.95 if style == "braids" else 0.8))
        rad = {"cornrows": lambda t, i: 0.0042 * (1.0 + 0.25 * (i % 2)), "braids": lambda t, i: 0.0045 * (1.0 + 0.22 * (i % 2)) * (1 - 0.3 * t),
               "dreads": lambda t, i: 0.0075 * (1.0 - 0.25 * t)}[style]
        strands = tubes(name + "_strands", paths, rad)
        _paint_full(strands)
        obj = _join(obj, strands)
    elif style == "long":
        obj = scalp(skin, F, name, lift=0.02)
        set_density(obj, F, lambda th, phi: G.smoothstep(hairline(th, 0.02) - 0.03, hairline(th, 0.02) + 0.08, phi),
                    lambda th, phi, d: 0.006 + 0.012 * d)
        bm = bmesh.new()
        bm.from_mesh(skin.data)
        tree = BVHTree.FromBMesh(bm)
        bm.free()
        paths = lock_paths(F, tree, scalp_roots(36, rows=3), hh * 1.15, hang_out=0.003)
        strands = tubes(name + "_strands", paths, lambda t, i: 0.013 * (1 - 0.35 * t), 6)
        _paint_full(strands)
        obj = _join(obj, strands)
    else:
        raise ValueError(style)
    sphere_uv(obj, F)
    return obj


def build_facial(skin, style):
    F = head_frame(skin)
    hh = F["hh"]
    nose = F["nose"]
    mouth_z = nose.z - hh * 0.13
    name = "facial_" + style

    def keep(c, n, arm_w, head_w):
        if head_w < 0.5 or c.z > nose.z + 0.01:
            return False
        th, phi, _ = angles(c, F)
        if math.cos(th) < -0.15:
            return False
        lips = ((c.x / 0.030) ** 2 + ((c.z - mouth_z) / 0.012) ** 2) < 1.0 and c.y < nose.y + 0.05
        return not lips

    obj = G.region(skin, keep, name)

    def dens(th, phi, co):
        mouth_d = math.hypot(co.x / 0.05, (co.z - mouth_z) / 0.03)
        jaw = G.smoothstep(nose.z - 0.02, nose.z - 0.06, co.z)
        cheek_side = abs(math.sin(th))
        if style == "stubble":
            return 0.45 * jaw * (1 - 0.6 * G.smoothstep(0.9, 1.0, cheek_side))
        must = (G.smoothstep(0.036, 0.022, abs(co.x)) * G.smoothstep(mouth_z + 0.002, mouth_z + 0.010, co.z)
                * G.smoothstep(nose.z - 0.006, nose.z - 0.016, co.z) * G.smoothstep(0.5, 0.7, math.cos(th)))
        if style == "mustache":
            return 0.9 * must
        if style == "goatee":
            chin = G.smoothstep(0.034, 0.020, abs(co.x)) * G.smoothstep(mouth_z - 0.008, mouth_z - 0.020, co.z) * G.smoothstep(0.4, 0.6, math.cos(th))
            ring = G.smoothstep(1.4, 1.1, mouth_d) * G.smoothstep(0.5, 0.7, math.cos(th))
            return 0.9 * max(chin, must, ring)
        if style == "beard_short":
            return 0.92 * jaw
        return jaw   # beard_full

    me = obj.data
    me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    col = me.color_attributes[0]
    d_v = []
    for v in me.vertices:
        th, phi, _ = angles(v.co, F)
        d = max(0.0, min(1.0, dens(th, phi, v.co)))
        d_v.append(d)
        thick = {"stubble": 0.0008, "mustache": 0.0025, "goatee": 0.0035, "beard_short": 0.004, "beard_full": 0.014}[style]
        v.co = v.co + v.normal * (0.0008 + thick * d)
    for poly in me.polygons:
        for li in poly.loop_indices:
            d = d_v[me.loops[li].vertex_index]
            col.data[li].color = (d, d, d, 1.0)
    if style == "beard_full":
        G.smooth_mesh(obj, 2, 0.4)
    sphere_uv(obj, F)
    return obj


def build_headband(skin):
    F = head_frame(skin)

    def keep(c, n, arm_w, head_w):
        if head_w < 0.5:
            return False
        th, phi, _ = angles(c, F)
        return 0.30 < phi < 0.52 and not _ear_gap(th, phi)

    obj = G.region(skin, keep, "acc_headband")
    G.inflate(obj, lambda co: 0.006)
    return obj
