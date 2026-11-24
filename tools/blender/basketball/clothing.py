"""Basketball clothing and equipment: jersey (armholes, scoop neckline, hem), shorts (waistband, flared legs), socks, shoes (upper, tongue, midsole, laces)
and the trim surface (secondary colour: borders, side stripes, sock cuffs). Everything is built around the SAME torso profile as the skin so it fits."""
import math

from mathutils import Vector

from fc_character.mesh import Part, smoothstep, lerp, TAU
from fc_character.mesh_extra import tube


def trim_along(trim: Part, source: Part, loops, radius_n: float, radius_b: float, out_offset: float = 0.0, closed: bool = True, min_len: int = 6):
    """A thin border tube along each open-edge loop of `source`, weighted like the vertices it follows."""
    source.bm.verts.ensure_lookup_table()
    for loop in loops:
        if len(loop) < min_len:
            continue
        pts, ws = [], []
        for i in loop:
            v = source.bm.verts[i]
            pts.append(v.co.copy())
            ws.append(source.weights[i])
        if closed:
            pts.append(pts[0])
            ws.append(ws[0])
        centre = sum(pts, Vector()) / len(pts)
        pts = [p + (Vector((p.x - centre.x, p.y - centre.y, 0.0)).normalized() * out_offset if out_offset else Vector()) for p in pts]
        tube(trim, pts, [(radius_n, radius_b)] * len(pts), ws, 6, False, False)


def cylinder_uv(ctx):
    """UV for the jersey: u runs around the body (0.5 at the front centre, the seam at the back centre), v up the body from the hem (0.62 m of height).
    The game puts the number, surname and wordmark in a texture laid out on these coordinates."""
    z_hem = ctx.torso_z(0.10)
    span = 0.62 * ctx.H / 1.98

    def uv(co):
        return (0.5 + math.atan2(co.x, -co.y) / TAU, (co.z - z_hem) / span)
    return uv


def build_jersey(ctx):
    """Returns (jersey Part, trim Part). A grid whose columns each have their own top edge, so the armholes and the scoop neckline are smooth curves."""
    H = ctx.H
    jersey = Part()
    segs, rows = 48, 18
    t_hem = 0.10
    z_hem = ctx.torso_z(t_hem)
    t_span = lambda z: (z - ctx.torso_z(0.0)) / (ctx.torso_z(1.0) - ctx.torso_z(0.0))
    z_shoulder = ctx.torso_z(0.925)
    z_pit = ctx.torso_z(0.70)
    neck_w = 0.092 * (H / 1.98)
    arm_x = 0.128 * (H / 1.98)
    pit_x = ctx.torso_section(0.9)[0] * H
    loose0 = 0.010 + 0.010 * ctx.body["mass"]
    for k in range(segs):
        th = TAU * k / segs
        s_, c_ = math.sin(th), math.cos(th)
        X = abs(s_) * pit_x
        arm_cut = (z_shoulder - z_pit) * smoothstep(arm_x, arm_x + 0.060, X)
        neck_depth = (0.150 if c_ > 0 else 0.055) * (H / 1.98)
        neck_cut = neck_depth * math.sqrt(max(0.0, 1.0 - (X / neck_w) ** 2)) if X < neck_w else 0.0
        top = z_shoulder - max(arm_cut, neck_cut)
        for i in range(rows + 1):
            r = i / rows
            z = z_hem + (top - z_hem) * r
            t = max(t_hem, min(1.0, t_span(z)))
            rx, ry = ctx.torso_section(t)
            loose = loose0 + 0.014 * (1.0 - smoothstep(0.0, 0.35, t))   # the hem hangs clear of the hips
            rx, ry = (rx + loose) * H, (ry + loose * 0.9) * H
            jersey.vert((rx * s_, -ry * c_, z), ctx.torso_weights(z))
    jersey.bm.verts.ensure_lookup_table()
    for i in range(rows):
        for k in range(segs):
            a = k * (rows + 1) + i
            b = ((k + 1) % segs) * (rows + 1) + i
            c2 = ((k + 1) % segs) * (rows + 1) + i + 1
            d = k * (rows + 1) + i + 1
            jersey.face(jersey.bm.verts[a], jersey.bm.verts[b], jersey.bm.verts[c2], jersey.bm.verts[d])
    trim = Part()
    trim_along(trim, jersey, jersey.boundary_loops(), 0.0030 * H, 0.0042 * H)
    return jersey, trim


def build_shorts(ctx):
    """Returns (shorts Part, trim Part)."""
    H, d = ctx.H, ctx.dims
    shorts = Part()
    py = ctx.rest["pelvis"].z
    block = []
    mass = ctx.body["mass"]
    for z, extra in [(py + 0.050 * H, 0.0), (py + 0.040 * H, 0.0), (py + 0.015 * H, 0.010), (py - 0.040 * H, 0.020), (py - 0.085 * H, 0.016)]:
        block.append((Vector((0, 0, z)), (d["hip_rx"] * mass + 0.012 + extra) * H, (d["hip_rz"] * mass + 0.012 + extra) * H, [("pelvis", 1.0)]))
    shorts.loft(block, 28, True, True, squareness=2.2)
    for p in ("l", "r"):
        hip, knee = ctx.rest[p + "_hip"], ctx.rest[p + "_knee"]
        hem = hip.z + (knee.z - hip.z) * 0.62
        legs = []
        for k in range(7):
            t = k / 6
            z = (py - 0.025 * H) * (1 - t) + hem * t
            flare = 1.0 + 0.06 * t * t + 0.04 * math.sin(t * math.pi * 3) * (1 - t) * 0.5   # slight folds, a flared hem
            r = d["thigh_r"] * H * 0.84 * (0.88 + 0.14 * ctx.body["thigh"]) * (1.10 + 0.08 * t) * flare + 0.008 * H
            m = smoothstep(py - 0.08 * H, hip.z, z) * 0.9 + (0.1 if k > 1 else 0.0)
            legs.append((Vector((hip.x, 0, z)), r, r * 1.04, [("pelvis", 1 - m), (p + "_hip", m)]))
        shorts.loft(legs, 16, False, False)
    trim = Part()
    trim_along(trim, shorts, shorts.boundary_loops(), 0.0030 * H, 0.0045 * H)
    # waistband (a slightly proud ring) and a drawcord knot at the front
    band = []
    for z in (py + 0.050 * H, py + 0.040 * H, py + 0.028 * H):
        band.append((Vector((0, 0, z)), (d["hip_rx"] * mass + 0.016) * H, (d["hip_rz"] * mass + 0.016) * H, [("pelvis", 1.0)]))
    shorts.loft(band, 28, False, False, squareness=2.2)
    # side stripe down each leg outside
    for p in ("l", "r"):
        sx = 1 if p == "l" else -1
        hip, knee = ctx.rest[p + "_hip"], ctx.rest[p + "_knee"]
        pts = []
        for k in range(2, 7):
            t = k / 6
            z = py + 0.040 * H + (hip.z + (knee.z - hip.z) * 0.62 - (py + 0.040 * H)) * t
            r = d["thigh_r"] * H * 0.84 * (0.88 + 0.14 * ctx.body["thigh"]) * (1.16 + 0.12 * t) + 0.013 * H
            x = hip.x + sx * r * 0.98 if t > 0.25 else sx * ((d["hip_rx"] * mass + 0.020 + 0.012 * t) * H)
            pts.append(Vector((x, 0.0, z)))
        w = [("pelvis", 1.0)] * 1 + [(p + "_hip", 1.0)] * 4
        tube(trim, pts, [(0.0050 * H, 0.0070 * H)] * 5, [[w_] for w_ in w], 6, True, True, up=Vector((0, 1, 0)))
    return shorts, trim


def build_socks(ctx):
    H, d = ctx.H, ctx.dims
    socks = Part()
    trim = Part()
    for p in ("l", "r"):
        kn, an = ctx.rest[p + "_knee"], ctx.rest[p + "_foot"]
        rc = d["calf_r"] * H * 0.88 * (0.9 + 0.1 * ctx.body["thigh"])
        rings = []
        for t, k, yo in [(0.36, 1.10, 0.009), (0.5, 0.97, 0.006), (0.75, 0.70, 0.0), (0.93, 0.60, 0.0), (1.0, 0.58, 0.0)]:
            c = kn + (an - kn) * t + Vector((0, yo * H, 0))
            w = [(p + "_knee", 1.0)] if t < 0.8 else [(p + "_knee", 0.5), (p + "_foot", 0.5)]
            rings.append((c, rc * k + 0.0035 * H, (rc * k + 0.0035 * H) * 1.08, w))
        socks.loft(rings, 14, False, False)
        # cuff stripes
        for t, k, yo in [(0.38, 1.08, 0.009), (0.425, 1.07, 0.009)]:
            c = kn + (an - kn) * t + Vector((0, yo * H, 0))
            r = rc * k + 0.0055 * H
            pts = [Vector((c.x + r * math.sin(TAU * i / 14), c.y - r * 1.08 * math.cos(TAU * i / 14), c.z)) for i in range(15)]
            tube(trim, pts, [(0.0028 * H, 0.0040 * H)] * 15, [(p + "_knee", 1.0)], 5, False, False)
    return socks, trim


def _station_loft(part: Part, stations, segs: int, bone: str, squareness: float, flat_bottom: bool = True):
    """Sections in the X-Z plane along Y: station = (y, x_centre, half_width, z_bottom, z_top). The toe points to -Y."""
    first = len(part.weights)
    n = 2.0 / squareness
    for y, xc, hw, zb, zt in stations:
        zc, hz = (zb + zt) * 0.5, (zt - zb) * 0.5
        for k in range(segs):
            th = TAU * k / segs
            s, c = math.sin(th), math.cos(th)
            x = xc + hw * math.copysign(abs(s) ** n, s)
            z = zc + hz * math.copysign(abs(c) ** n, c)
            part.vert((x, y, z), [(bone, 1.0)])
    part.bm.verts.ensure_lookup_table()
    for i in range(len(stations) - 1):
        for k in range(segs):
            a = first + i * segs + k
            b = first + i * segs + (k + 1) % segs
            c2 = first + (i + 1) * segs + (k + 1) % segs
            d = first + (i + 1) * segs + k
            part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c2], part.bm.verts[d])
    for index in (0, len(stations) - 1):
        part.face(*[part.bm.verts[first + index * segs + k] for k in range(segs)])


def build_shoes(ctx):
    """Returns (shoes Part (upper, tongue, heel counter), sole Part (midsole, outsole, laces), trim Part (side stripe))."""
    H = ctx.H
    fs = ctx.dims["foot"] * ctx.scale / ctx.scale
    shoes, sole, trim = Part(), Part(), Part()
    sc = ctx.scale * fs
    for p in ("l", "r"):
        bone = p + "_foot"
        an = ctx.rest[bone]
        x = an.x
        mid_top = 0.036 * sc   # the top of the midsole above the floor
        # (forward distance from the ankle (m), half-width, collar/upper height above the midsole)
        profile = [(-0.092, 0.030, 0.072), (-0.080, 0.038, 0.100), (-0.050, 0.043, 0.108), (-0.015, 0.045, 0.100), (0.030, 0.046, 0.074), (0.080, 0.048, 0.058),
                   (0.130, 0.049, 0.048), (0.175, 0.046, 0.041), (0.210, 0.037, 0.033), (0.232, 0.022, 0.024), (0.241, 0.010, 0.014)]
        up, mid = [], []
        for f, hw, top in profile:
            y = an.y - f * sc
            up.append((y, x, hw * sc, mid_top, mid_top + top * sc))
            mid.append((y, x, hw * sc * 1.07, 0.0, mid_top + 0.002 * sc))
        _station_loft(shoes, up, 14, bone, 3.0)
        _station_loft(sole, mid, 14, bone, 4.0)
        # tongue: a small ridge rising above the instep, and laces across it
        for i, (f, hw, top) in enumerate(profile[3:7]):
            y = an.y - f * sc
            shoes.ellipsoid((x, y, mid_top + top * sc * 1.02), (hw * sc * 0.42, 0.02 * sc, 0.012 * sc), bone, 3, 8)
        for f in (0.002, 0.028, 0.054, 0.080, 0.106):
            y = an.y - f * sc
            idx = min(int((f + 0.015) / 0.045) + 3, 6)
            top = profile[idx][2]
            zt = mid_top + top * sc * 1.04
            pts = [Vector((x - 0.030 * sc, y, zt - 0.004 * sc)), Vector((x, y - 0.006 * sc, zt + 0.006 * sc)), Vector((x + 0.030 * sc, y, zt - 0.004 * sc))]
            tube(sole, pts, [(0.0035 * sc, 0.0035 * sc)] * 3, [(bone, 1.0)], 5, True, True)
        # heel counter: a proud cap at the back
        shoes.ellipsoid((x, an.y + 0.075 * sc, mid_top + 0.045 * sc), (0.040 * sc, 0.030 * sc, 0.048 * sc), bone, 4, 10)
        # side stripe in the secondary colour
        for sx in (-1, 1):
            pts = [Vector((x + sx * (profile[i][1] * sc + 0.002), an.y - profile[i][0] * sc, mid_top + profile[i][2] * sc * 0.45)) for i in range(2, 8)]
            tube(trim, pts, [(0.0035 * sc, 0.011 * sc)] * len(pts), [(bone, 1.0)], 5, True, True, up=Vector((1, 0, 0)))
    return shoes, sole, trim
