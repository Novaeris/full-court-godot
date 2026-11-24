"""Basketball player heads (modular): sculpted by function, then built into swappable parts.

The head is a sphere grid displaced in FACE SPACE (u across, v up, front depth): jaw, chin, cheekbones, brow ridge, eye sockets, nose bridge,
mouth groove. Variation is a set of parameters, so one function makes every face. Parts built here (all skinned to the 'head' bone):
  skin_head_<face><jaw>   the head surface with ears and eyelids          (6 faces x 3 jaws)
  nose_<k>, nostrils_<k>  nose styles                                      (3)
  lips_<k>                mouth styles: smile, neutral, smirk              (3)
  brow_<k>                brow thickness                                   (3)
  eyes_<k>                eyeballs with iris and pupil, three sizes        (3)
Everything is measured in head heights (hh) so it scales with the player.
"""
import math

from mathutils import Vector

from fc_character.mesh import Part, gauss, smoothstep, lerp, TAU
from fc_character.mesh_extra import tube

HEAD = [("head", 1.0)]

# face id (face_1..face_6) -> character of the face. cheek: cheekbone bump; brow: ridge; chin: chin prominence; width: head width factor;
# length: how long the lower face is; temple: forehead fullness; ear: ear size factor.
FACES = [
    {"cheek": 0.020, "brow": 0.016, "chin": 0.020, "width": 1.00, "length": 1.00, "temple": 0.0, "ear": 1.00},
    {"cheek": 0.032, "brow": 0.010, "chin": 0.010, "width": 1.04, "length": 0.96, "temple": 0.010, "ear": 1.10},
    {"cheek": 0.014, "brow": 0.024, "chin": 0.030, "width": 0.96, "length": 1.05, "temple": -0.006, "ear": 0.95},
    {"cheek": 0.026, "brow": 0.020, "chin": 0.004, "width": 1.02, "length": 1.00, "temple": 0.006, "ear": 1.20},
    {"cheek": 0.010, "brow": 0.012, "chin": 0.036, "width": 0.94, "length": 1.08, "temple": 0.0, "ear": 0.90},
    {"cheek": 0.036, "brow": 0.022, "chin": 0.016, "width": 1.06, "length": 0.98, "temple": 0.012, "ear": 1.05},
]
JAWS = ["round", "square", "pointed"]
NOSES = [
    {"wing": 0.058, "tip": 0.070, "length": 0.195, "bridge": 0.014},   # small and straight
    {"wing": 0.078, "tip": 0.074, "length": 0.195, "bridge": 0.012},   # broad
    {"wing": 0.062, "tip": 0.092, "length": 0.235, "bridge": 0.020},   # long and pronounced
]
MOUTHS = [(0.020, 0.020), (0.0, 0.0), (0.024, 0.004)]   # (left corner lift, right corner lift) in hh: smile, neutral, smirk
BROWS = [0.012, 0.018, 0.026]
EYE_SIZES = [0.90, 1.0, 1.10]


class HeadFrame:
    """Where the head is, in Blender units, and the face-space maths shared by every head part."""

    def __init__(self, builder):
        H = builder.H
        self.H = H
        self.hh = builder.dims["head_h"] * H
        self.chin_z = (0.995 - builder.dims["head_h"]) * H
        self.z0 = self.chin_z + self.hh * 0.5
        self.rz = self.hh * 0.5
        self.rx = self.hh * 0.355
        self.ry = self.hh * 0.435

    def depth(self, u: float, v: float) -> float:
        """Distance of the undeformed front surface from the centre plane at face-space (u, v), as a positive number."""
        return self.ry * math.sqrt(max(1.0 - u * u - v * v, 0.0))


def displace(frame: HeadFrame, face: dict, jaw: int, u: float, v: float, w: float):
    """Face-space displacement for a base-surface point: returns (lateral factor, forward push in hh, down push in hh)."""
    hh = frame.hh
    # lateral factor: the jaw angle region, the cheek and the temple
    jaw_amount = [0.13, 0.30, -0.02][jaw]
    lateral = 1.0 + jaw_amount * math.exp(-((v + 0.58) ** 2) / (2 * 0.30 ** 2)) + face["temple"] * 4.0 * math.exp(-((v - 0.35) ** 2) / (2 * 0.25 ** 2))
    lateral *= 1.0 + 0.5 * face["cheek"] * math.exp(-((v + 0.12) ** 2) / (2 * 0.2 ** 2))
    push = 0.0
    au = abs(u)
    front = smoothstep(0.15, 0.75, w)   # 0 at the sides, 1 straight ahead
    # brow ridge
    push += face["brow"] * math.exp(-((v - 0.2) ** 2) / (2 * 0.085 ** 2)) * smoothstep(0.95, 0.15, au) * front
    # eye sockets (dents)
    for s in (1.0, -1.0):
        d2 = ((u - s * 0.40) / 0.17) ** 2 + ((v - 0.06) / 0.10) ** 2
        push -= 0.040 * math.exp(-d2 / 2.0) * front
    # cheekbones
    for s in (1.0, -1.0):
        d2 = ((u - s * 0.58) / 0.20) ** 2 + ((v + 0.14) / 0.17) ** 2
        push += face["cheek"] * math.exp(-d2 / 2.0) * front
    # nose bridge and the muzzle under the nose
    push += 0.012 * math.exp(-((u / 0.11) ** 2 + ((v - 0.05) / 0.25) ** 2) / 2.0) * front
    push += 0.016 * math.exp(-((u / 0.34) ** 2 + ((v + 0.30) / 0.11) ** 2) / 2.0) * front
    # mouth groove and the dent under the lower lip
    push -= 0.008 * math.exp(-((u / 0.3) ** 2 + ((v + 0.44) / 0.025) ** 2) / 2.0) * front
    push -= 0.012 * math.exp(-((u / 0.25) ** 2 + ((v + 0.60) / 0.045) ** 2) / 2.0) * front
    # chin
    push += face["chin"] * math.exp(-((u / (0.22 + 0.06 * (jaw == 1))) ** 2 + ((v + 0.80) / 0.14) ** 2) / 2.0) * front
    # forehead slope: a gentle bulge above the brow
    push += 0.010 * math.exp(-((u / 0.55) ** 2 + ((v - 0.58) / 0.18) ** 2) / 2.0) * front
    down = 0.012 * smoothstep(-0.75, -1.0, v)   # a flatter chin underside than a pole
    if jaw == 1:   # square: flatten the chin underside
        down = -0.030 * smoothstep(-0.7, -1.0, v)
    elif jaw == 2:   # pointed: draw the chin down a little
        down = 0.014 * math.exp(-((u / 0.2) ** 2 + ((v + 0.9) / 0.18) ** 2) / 2.0)
    return lateral, push, down


def build_skin_head(builder, face_index: int, jaw: int) -> Part:
    frame = HeadFrame(builder)
    face = FACES[face_index]
    part = Part()
    nlat, nseg = 22, 28
    z0, hh = frame.z0, frame.hh
    rx, ry, rz = frame.rx * face["width"], frame.ry, frame.rz * (0.98 + 0.02 * face["length"])
    first = 0
    for i in range(nlat + 1):
        phi = -math.pi / 2 + math.pi * i / nlat
        for k in range(nseg):
            th = TAU * k / nseg
            dx, dy, dz = math.sin(th) * math.cos(phi), -math.cos(th) * math.cos(phi), math.sin(phi)
            u, v, w = dx, dz, -dy
            lateral, push, down = displace(frame, face, jaw, u, v, w)
            # the back of the skull is a little fuller than the front, the crown flatter
            back = 1.0 + 0.04 * smoothstep(0.0, -1.0, w) * max(0.0, 1.0 - abs(v))
            x = rx * dx * lateral
            y = ry * dy * back - hh * push
            z = z0 + rz * dz + hh * down * (1.0 if v < 0 else 0.0)
            part.vert((x, y, z), [("head", 1.0)])
    part.bm.verts.ensure_lookup_table()
    for i in range(nlat):
        for k in range(nseg):
            a = i * nseg + k
            b = i * nseg + (k + 1) % nseg
            c = (i + 1) * nseg + (k + 1) % nseg
            d = (i + 1) * nseg + k
            part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c], part.bm.verts[d])
    # eyelids (skin shells over the eyeball), ears
    for s in (1, -1):
        add_eyelids(part, frame, face, jaw, s)
        add_ear(part, frame, face, s)
    return part


def surface_front_y(frame: HeadFrame, face: dict, jaw: int, x: float, z: float) -> float:
    """Blender Y of the displaced front surface at (x, z) (negative: the front is -Y)."""
    rx = frame.rx * face["width"]
    u = x / rx
    v = (z - frame.z0) / frame.rz
    base = frame.depth(u, v)
    w = base / frame.ry
    lateral, push, down = displace(frame, face, jaw, u, v, w)
    return -(base - frame.hh * push)


def eye_centre(frame: HeadFrame, face: dict, jaw: int, side: int, size: float = 1.0):
    x = side * frame.rx * face["width"] * 0.40
    z = frame.z0 + frame.rz * 0.06
    r = frame.hh * 0.056 * size
    y = surface_front_y(frame, face, jaw, x, z) + r * 0.62
    return Vector((x, y, z)), r


def add_eyelids(part: Part, frame: HeadFrame, face: dict, jaw: int, side: int):
    c, r = eye_centre(frame, face, jaw, side)
    # upper and lower lid shells just outside the eyeball, only their front is visible
    part.ellipsoid(c, (r * 1.10, r * 1.10, r * 1.10), "head", 3, 12, 0.66, 1.2)
    part.ellipsoid(c, (r * 1.08, r * 1.08, r * 1.08), "head", 2, 12, -1.1, -0.70)


def add_ear(part: Part, frame: HeadFrame, face: dict, side: int):
    hh = frame.hh
    cx = side * frame.rx * face["width"] * 0.985
    cy = frame.ry * 0.06
    cz = frame.z0 - hh * 0.035
    ew, eh = hh * 0.052 * face["ear"], hh * 0.112 * face["ear"]
    rings, segs = 5, 16
    first = len(part.weights)
    for i in range(rings + 1):
        r = i / rings
        for k in range(segs):
            th = TAU * k / segs
            # outline: an ellipse slightly wider at the top; depth profile: raised rim, dented bowl, lobe
            ox = r * ew * math.sin(th)
            oz = r * eh * math.cos(th) * (1.0 + 0.08 * math.cos(th))
            out = hh * (0.012 * gauss((r - 0.88) ** 2, 0.14) - 0.014 * gauss(r * r, 0.30) + 0.010 * (1 - r))
            x = cx + side * out * 1.6 + side * hh * 0.012
            part.vert((x, cy + ox * 1.0, cz + oz), [("head", 1.0)])
    part.bm.verts.ensure_lookup_table()
    for i in range(rings):
        for k in range(segs):
            a = first + i * segs + k
            b = first + i * segs + (k + 1) % segs
            c2 = first + (i + 1) * segs + (k + 1) % segs
            d = first + (i + 1) * segs + k
            part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c2], part.bm.verts[d])


def build_nose(builder, k: int) -> tuple:
    """(nose Part, nostrils Part) in the neutral face (face 0, round jaw); the nose sits on every head."""
    frame = HeadFrame(builder)
    face, jaw = FACES[0], 0
    n = NOSES[k]
    hh = frame.hh
    top_z = frame.z0 + hh * 0.07
    base_z = top_z - hh * n["length"]
    rings = []
    steps = 9
    for i in range(steps + 1):
        t = i / steps
        z = lerp(top_z, base_z, t)
        # protrusion profile: starts at the bridge, grows to the tip near the end, wings spread at the base
        prot = n["bridge"] + (n["tip"] - n["bridge"]) * smoothstep(0.0, 0.9, t) ** 1.2
        if t > 0.92:
            prot *= lerp(1.0, 0.72, (t - 0.92) / 0.08)
        width = hh * (0.020 + (n["wing"] - 0.020) * smoothstep(0.15, 0.85, t))
        ry = hh * (prot * 0.62 + 0.010)
        front = surface_front_y(frame, face, jaw, 0.0, z)
        y_c = front - hh * prot + ry
        rings.append((Vector((0.0, y_c, z)), width, ry, HEAD))
    nose = Part()
    nose.loft(rings, 12, True, True)
    # wings: two small ellipsoids at the base
    for s in (1, -1):
        zc = base_z + hh * 0.025
        front = surface_front_y(frame, face, jaw, s * hh * n["wing"] * 0.75, zc)
        nose.ellipsoid((s * hh * n["wing"] * 0.78, front - hh * 0.010, zc), (hh * 0.026, hh * 0.030, hh * 0.030), "head", 4, 10)
    nostrils = Part()
    dark = (0.05, 0.03, 0.03, 1.0)
    for s in (1, -1):
        zc = base_z + hh * 0.004
        nostrils.ellipsoid((s * hh * n["wing"] * 0.40, rings[-1][0].y - hh * 0.004, zc), (hh * 0.012, hh * 0.016, hh * 0.007), "head", 3, 8, color=dark)
    return nose, nostrils


def build_lips(builder, k: int) -> Part:
    frame = HeadFrame(builder)
    face, jaw = FACES[0], 0
    hh = frame.hh
    zc = frame.z0 - hh * 0.215
    lift_l, lift_r = MOUTHS[k]
    half = hh * 0.145
    part = Part()
    upper, lower = [], []
    steps = 9
    for i in range(steps + 1):
        t = i / steps * 2 - 1   # -1..1 across the mouth
        x = t * half
        lift = hh * (lift_l if t > 0 else lift_r) * (t * t)
        mouth_curve = hh * 0.006 * (1 - t * t)
        z = zc + lift
        front = surface_front_y(frame, face, jaw, x, z)
        taper = 1.0 - 0.55 * abs(t) ** 2
        upper.append((Vector((x, front + hh * 0.004, z + hh * 0.011 * taper + mouth_curve * 0.2)), (hh * 0.011 * taper + hh * 0.002, hh * 0.010 * taper + hh * 0.002)))
        lower.append((Vector((x, front + hh * 0.003, z - hh * 0.012 * taper + mouth_curve * 0.2)), (hh * 0.012 * taper + hh * 0.002, hh * 0.013 * taper + hh * 0.002)))
    for pts in (upper, lower):
        tube(part, [p for p, _ in pts], [r for _, r in pts], HEAD, 8, True, True)
    return part


def build_brows(builder, k: int) -> Part:
    frame = HeadFrame(builder)
    face, jaw = FACES[0], 0
    hh = frame.hh
    thick = BROWS[k]
    part = Part()
    for s in (1, -1):
        pts, radii = [], []
        steps = 7
        for i in range(steps + 1):
            t = i / steps
            x = s * frame.rx * (0.18 + 0.50 * t)
            z = frame.z0 + hh * (0.130 + 0.030 * math.sin(t * math.pi) - 0.012 * t)
            front = surface_front_y(frame, face, jaw, x, z)
            r = hh * thick * 0.5 * (1.0 - 0.45 * t)
            pts.append(Vector((x, front + r * 0.35, z)))
            radii.append((r * 0.8, r))
        tube(part, pts, radii, HEAD, 6, True, True)
    return part


def build_eyes(builder, k: int) -> Part:
    frame = HeadFrame(builder)
    face, jaw = FACES[0], 0
    part = Part()
    sclera = (0.84, 0.80, 0.76, 1.0)
    iris = (0.20, 0.12, 0.07, 1.0)
    pupil = (0.02, 0.02, 0.02, 1.0)
    for s in (1, -1):
        c, r = eye_centre(frame, face, jaw, s, EYE_SIZES[k])
        rings, segs = 10, 16
        first = len(part.weights)
        for i in range(rings + 1):
            phi = -math.pi / 2 + math.pi * i / rings
            for j in range(segs):
                th = TAU * j / segs
                dx, dy, dz = math.sin(th) * math.cos(phi), -math.cos(th) * math.cos(phi), math.sin(phi)
                ang = math.acos(max(-1.0, min(1.0, -dy)))   # angle from straight ahead
                col = pupil if ang < 0.24 else (iris if ang < 0.62 else sclera)
                part.vert((c.x + r * dx, c.y + r * dy, c.z + r * dz), HEAD, col)
        part.bm.verts.ensure_lookup_table()
        for i in range(rings):
            for j in range(segs):
                a = first + i * segs + j
                b = first + i * segs + (j + 1) % segs
                c2 = first + (i + 1) * segs + (j + 1) % segs
                d = first + (i + 1) * segs + j
                part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c2], part.bm.verts[d])
    return part


def build_base_head(builder) -> Part:
    """A plain cranium inside the body skin so a bare model (no head parts attached) is still a complete figure; every head part covers it."""
    frame = HeadFrame(builder)
    part = Part()
    part.ellipsoid((0, 0, frame.z0), (frame.rx * 0.9, frame.ry * 0.9, frame.rz * 0.93), "head", 8, 14)
    return part
