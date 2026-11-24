"""Hair styles, facial hair and the headband. Hair is built as solid shapes (a cap, a curtain, tubes for braids and locs) rather than strands: it reads at
broadcast distance and costs few triangles. Everything is skinned to the head bone and fitted to the widest head variant."""
import math

from mathutils import Vector

import head as H
from fc_character.mesh import Part, smoothstep, lerp, TAU
from fc_character.mesh_extra import tube

HEAD = [("head", 1.0)]


def _frame(ctx):
    return H.HeadFrame(ctx)


def _cap(ctx, thick=1.10, lift=0.03, front_line=0.56, side_line=0.12, back_line=-0.20, rows=9, segs=30, bumps=0.0, scale=(1.0, 1.0, 1.0)):
    """A scalp cap. The hairline (lowest elevation, radians) goes from front_line at the forehead to side_line at the ears and back_line at the nape."""
    f = _frame(ctx)
    part = Part()
    rx, ry, rz = f.rx * 1.06 * thick * scale[0], f.ry * thick * scale[1], f.rz * thick * scale[2]
    z0 = f.z0 + f.hh * lift
    for k in range(segs):
        pass
    cols = []
    for k in range(segs):
        th = TAU * k / segs
        c = math.cos(th)   # 1 at the front, -1 at the back
        s = abs(math.sin(th))
        phi_min = lerp(side_line, front_line if c > 0 else back_line, abs(c) ** 1.4) if True else 0.0
        cols.append(phi_min)
    first = 0
    for i in range(rows + 1):
        for k in range(segs):
            th = TAU * k / segs
            phi = lerp(cols[k], math.pi / 2, i / rows)
            bump = 1.0 + bumps * math.sin(5 * th + 1.3) * math.sin(6 * phi + 0.7) if bumps else 1.0
            grow = lerp(0.915, 1.0, smoothstep(0.0, 0.34, i / rows))   # the hairline edge lies on the scalp, the volume builds over the first rows
            part.vert((rx * grow * bump * math.sin(th) * math.cos(phi), -ry * grow * bump * math.cos(th) * math.cos(phi), z0 + rz * grow * bump * math.sin(phi)), HEAD)
    part.bm.verts.ensure_lookup_table()
    for i in range(rows):
        for k in range(segs):
            a = i * segs + k
            b = i * segs + (k + 1) % segs
            c2 = (i + 1) * segs + (k + 1) % segs
            d = (i + 1) * segs + k
            part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c2], part.bm.verts[d])
    return part


def build_hair(ctx, style: str) -> Part:
    f = _frame(ctx)
    hh = f.hh
    if style == "short":
        return _cap(ctx, 1.055, 0.015, front_line=0.60, side_line=0.0, back_line=-0.38)
    if style == "fade":
        return _cap(ctx, 1.045, 0.01, front_line=0.62, side_line=0.45, back_line=0.30)
    if style == "afro":
        return _cap(ctx, 1.34, 0.05, front_line=0.46, side_line=0.0, back_line=-0.34, rows=11, segs=34, bumps=0.03)
    if style == "curly":
        return _cap(ctx, 1.20, 0.07, front_line=0.52, side_line=0.08, back_line=-0.28, rows=11, segs=34, bumps=0.07)
    part = _cap(ctx, 1.07, 0.02, front_line=0.56, side_line=0.12, back_line=-0.12)
    if style == "long":
        rings = []
        for i, z in enumerate((f.z0 + hh * 0.10, f.z0 - hh * 0.15, f.z0 - hh * 0.45, f.z0 - hh * 0.80, f.z0 - hh * 1.10, f.z0 - hh * 1.30)):
            spread = 1.05 + 0.10 * (i / 5.0)
            rings.append((Vector((0, f.ry * 0.12 + hh * 0.03 * i, z)), f.rx * 1.16 * spread, f.ry * (1.08 - 0.07 * i / 5.0) * spread, HEAD))
        curtain = Part()
        curtain.loft(rings, 30, False, False)
        curtain.remove_faces(lambda c: c.y < f.ry * 0.12 - hh * 0.02 and abs(c.x) < f.rx * 0.95)   # open at the face
        part.merge(curtain)
        return part
    if style in ("braids", "locs"):
        count = 16 if style == "braids" else 10
        length = (0.50 if style == "braids" else 0.70) * hh * 1.6
        radius = hh * (0.020 if style == "braids" else 0.030)
        for n in range(count):
            th = math.pi * (0.55 + 0.9 * n / (count - 1)) + (math.pi if n % 2 else 0.0) * 0.0
            row = n % 2
            th = TAU * (n + 0.5) / count
            if math.cos(th) > 0.55:
                continue   # keep the face clear
            phi = 0.15 + 0.35 * row
            root = Vector((f.rx * 1.08 * math.sin(th) * math.cos(phi), -f.ry * 1.06 * math.cos(th) * math.cos(phi), f.z0 + f.rz * 1.06 * math.sin(phi)))
            pts, radii = [], []
            steps = 9
            outward = Vector((math.sin(th), -math.cos(th), 0.0)).normalized()
            for i in range(steps + 1):
                t = i / steps
                p = root + outward * (hh * 0.06 * math.sin(t * math.pi * 0.6)) + Vector((0, 0, -length * t))
                pts.append(p)
                bead = 1.0 + (0.20 * math.sin(i * math.pi) if style == "braids" else 0.0)
                r = radius * (1.0 - 0.35 * t) * bead
                radii.append((r, r))
            tube(part, pts, radii, HEAD, 6, True, True)
        return part
    return part


def _shell(ctx, jaw: int, offset: float, mask) -> Part:
    """A thin shell over the face for facial hair. mask(u, v, w) in 0..1 sets the thickness (soft edges); faces with almost no thickness are removed."""
    f = _frame(ctx)
    face = H.FACES[0]
    part = Part()
    nlat, nseg = 26, 32
    rx, ry, rz = f.rx * face["width"], f.ry, f.rz * (0.98 + 0.02 * face["length"])
    amounts = []
    for i in range(nlat + 1):
        phi = -math.pi / 2 + math.pi * i / nlat
        for k in range(nseg):
            th = TAU * k / nseg
            dx, dy, dz = math.sin(th) * math.cos(phi), -math.cos(th) * math.cos(phi), math.sin(phi)
            lateral, push, down = H.displace(f, face, jaw, dx, dz, -dy)
            back = 1.0 + 0.04 * smoothstep(0.0, -1.0, -dy) * max(0.0, 1.0 - abs(dz))
            m = mask(dx, dz, -dy)
            amounts.append(m)
            o = (0.002 + offset * m) * f.hh
            part.vert((rx * dx * lateral + dx * o, ry * dy * back - f.hh * push + dy * o, f.z0 + rz * dz + f.hh * down * (1.0 if dz < 0 else 0.0) + dz * o), HEAD)
    part.bm.verts.ensure_lookup_table()
    for i in range(nlat):
        for k in range(nseg):
            a = i * nseg + k
            b = i * nseg + (k + 1) % nseg
            c = (i + 1) * nseg + (k + 1) % nseg
            d = (i + 1) * nseg + k
            if (amounts[a] + amounts[b] + amounts[c] + amounts[d]) / 4.0 > 0.03:
                part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c], part.bm.verts[d])
    return part


def _mouth_clear(u, v):
    d = math.sqrt((u / 0.30) ** 2 + ((v + 0.42) / 0.10) ** 2)
    return smoothstep(0.9, 1.35, d)


def build_facial_hair(ctx, style: str, jaw: int) -> Part:
    f = _frame(ctx)
    hh = f.hh
    front = lambda w: smoothstep(-0.30, 0.10, w)
    if style == "stubble":
        return _shell(ctx, jaw, 0.012, lambda u, v, w: front(w) * max(smoothstep(-0.12, -0.34, v), smoothstep(0.78, 0.92, abs(u)) * smoothstep(0.12, -0.05, v)) * _mouth_clear(u, v))
    if style == "beard":
        part = _shell(ctx, jaw, 0.034, lambda u, v, w: front(w) * max(smoothstep(-0.18, -0.42, v), smoothstep(0.74, 0.92, abs(u)) * smoothstep(0.14, -0.05, v)) * _mouth_clear(u, v))
    else:   # goatee
        part = _shell(ctx, jaw, 0.032, lambda u, v, w: front(w) * smoothstep(-0.50, -0.64, v) * smoothstep(0.44, 0.26, abs(u)))
    pts, radii = [], []
    for i in range(9):
        t = i / 8 * 2 - 1
        x = t * hh * 0.14
        z = f.z0 - hh * 0.168 + hh * 0.012 * t * t
        front_y = H.surface_front_y(f, H.FACES[0], jaw, x, z)
        pts.append(Vector((x, front_y + hh * 0.004, z)))
        radii.append((hh * 0.014 * (1 - 0.4 * abs(t)), hh * 0.020 * (1 - 0.5 * abs(t))))
    tube(part, pts, radii, HEAD, 6, True, True)
    return part


def build_headband(ctx) -> Part:
    f = _frame(ctx)
    part = Part()
    rings = []
    for dz, grow in ((0.31, 1.0), (0.37, 1.012), (0.43, 1.0)):
        z = f.z0 + f.rz * dz
        shrink = math.sqrt(max(1.0 - dz * dz, 0.01))
        rings.append((Vector((0, f.ry * 0.03, z)), f.rx * 1.09 * shrink * grow, f.ry * 1.07 * shrink * grow, HEAD))
    part.loft(rings, 30, False, False)
    return part
