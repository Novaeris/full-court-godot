"""The basketball athlete body: torso, neck, arms, legs and hands with fingers (one skin surface), by body type (lean, athletic, heavy).
Limb profiles carry the muscle groups (deltoid, biceps and triceps, forearm, quadriceps, calf); the hand has a palm and five digits skinned to x_ finger bones."""
import math

from mathutils import Vector

from fc_character.mesh import Part, smoothstep, lerp
from fc_character.mesh_extra import tube

DIGITS = {
    # name: (y offset across the palm (front is -Y), start along the palm 0..1, length m, segment split, radius m, spread toward the front in radians)
    "thumb": (-0.040, 0.30, 0.062, 0.55, 0.0100, 0.55),
    "index": (-0.0285, 1.0, 0.076, 0.55, 0.0082, 0.04),
    "middle": (-0.0095, 1.0, 0.084, 0.55, 0.0084, 0.0),
    "ring": (0.0095, 1.0, 0.076, 0.55, 0.0078, -0.03),
    "pinky": (0.0265, 1.0, 0.060, 0.55, 0.0068, -0.07),
}


def finger_bone_name(side: str, digit: str, index: int) -> str:
    return "x_%s_%s_%d" % (side, digit, index)


def finger_bones(ctx):
    """The extension bones (name, parent, head, tail) for both hands, at rest straight down along the palm."""
    out = []
    palm = 0.052 * ctx.H * ctx.dims["hand"]
    for side in ("l", "r"):
        wr = ctx.rest[side + "_hand"]
        for digit, (yo, start, length, split, radius, spread) in DIGITS.items():
            z0 = wr.z - palm * start
            head = Vector((wr.x, wr.y + yo, z0))
            mid = head + Vector((0, -math.sin(spread) * length * split, -math.cos(spread) * length * split))
            end = mid + Vector((0, -math.sin(spread) * length * (1 - split), -math.cos(spread) * length * (1 - split)))
            out.append((finger_bone_name(side, digit, 1), side + "_hand", head, mid))
            out.append((finger_bone_name(side, digit, 2), finger_bone_name(side, digit, 1), mid, end))
    return out


def tails(ctx):
    """Bone tails for the standard bones (Blender units)."""
    s = ctx.scale

    def f(name, rest):
        fixed = {
            "pelvis": rest["pelvis"] + Vector((0, 0, 0.14 * s)), "torso": rest["neck"], "neck": rest["head"], "head": rest["head"] + Vector((0, 0, 0.2 * s)),
            "l_hand": rest["l_hand"] + Vector((0, 0, -0.09 * s)), "r_hand": rest["r_hand"] + Vector((0, 0, -0.09 * s)),
            "l_foot": rest["l_foot"] + Vector((0, -0.2 * s, 0)), "r_foot": rest["r_foot"] + Vector((0, -0.2 * s, 0)),
        }
        for side in ("l", "r"):
            fixed[side + "_shoulder"] = rest[side + "_elbow"]
            fixed[side + "_elbow"] = rest[side + "_hand"]
            fixed[side + "_hip"] = rest[side + "_knee"]
            fixed[side + "_knee"] = rest[side + "_foot"]
        return fixed[name]
    return f


def build_skin(ctx, with_fingers: bool = True) -> Part:
    part = Part()
    H = ctx.H
    rings = []
    ts = [0.0, 0.06, 0.12, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.78, 0.84, 0.88, 0.92, 0.96, 1.0, 1.05]
    for t in ts:
        rx, ry = ctx.torso_section(t)
        z = ctx.torso_z(t)
        # muscle: pectorals thicken the chest front, lats widen the back of the upper torso
        chest_bump = math.exp(-((t - 0.68) ** 2) / (2 * 0.10 ** 2))
        ry *= 1.0 + 0.07 * ctx.body["muscle"] * chest_bump
        rx *= 1.0 + 0.04 * ctx.body["muscle"] * math.exp(-((t - 0.60) ** 2) / (2 * 0.12 ** 2))
        rings.append((Vector((0, 0, z)), rx * H, ry * H, ctx.torso_weights(z)))
    part.loft(rings, 24, True, False, squareness=2.3)
    # neck: from the trapezius up into the head
    nr = ctx.dims["neck_r"] * H * 1.12 * (0.95 + 0.1 * ctx.body["mass"])   # an athlete neck: thick, so it reads short
    neck = []
    for zf in (0.845, 0.86, 0.885, 0.915):
        flare = 1.0 + 0.12 * max(0.0, (0.86 - zf) / 0.03)   # the trapezius widens the base of the neck
        k = smoothstep(0.855 * H, 0.9 * H, zf * H)
        if zf < 0.855:
            w = [("torso", 0.5), ("neck", 0.5)]
        else:
            w = [("neck", 1 - k), ("head", k)]
        neck.append((Vector((0, 0.004 * H, zf * H)), nr * flare, nr * 0.95 * flare, w))
    part.loft(neck, 16, False, True)
    for side in ("l", "r"):
        arm(ctx, part, side)
        leg(ctx, part, side)
        hand(ctx, part, side, with_fingers)
    return part


def arm(ctx, part: Part, p: str):
    H, d, b = ctx.H, ctx.dims, ctx.body
    sh, el, wr = ctx.rest[p + "_shoulder"], ctx.rest[p + "_elbow"], ctx.rest[p + "_hand"]
    ra, rf = d["arm_r"] * H * 0.80 * (0.92 + 0.12 * b["mass"]), d["forearm_r"] * H * 0.84 * (0.92 + 0.12 * b["mass"])
    m = b["muscle"]
    rings = []
    # t along the upper arm; k = radius factor (deltoid at the top, biceps and triceps in the middle, the elbow narrow), yo = back offset for the triceps
    for t, k, yo in [(-0.075, 0.40, 0.0), (-0.055, 0.70, 0.0), (-0.03, 0.92, 0.0), (0.0, 1.08 + 0.10 * m, 0.0), (0.12, 1.20 + 0.10 * m, 0.0), (0.3, 1.10 + 0.08 * m, 0.003), (0.55, 1.03 + 0.06 * m, 0.004), (0.8, 0.86, 0.0), (1.0, 0.78, 0.0)]:
        c = sh + (el - sh) * t + Vector((0, yo * H, 0))
        if t < 0.0:
            w = [("torso", 0.55), (p + "_shoulder", 0.45)]
        elif t < 0.15:
            mm = 0.4 + t * 4
            w = [("torso", 1 - mm), (p + "_shoulder", mm)]
        elif t > 0.9:
            mm = 0.35 + (t - 0.9) * 6
            w = [(p + "_shoulder", 1 - mm), (p + "_elbow", mm)]
        elif t > 0.75:
            mm = (t - 0.75) / 0.25 * 0.35
            w = [(p + "_shoulder", 1 - mm), (p + "_elbow", mm)]
        else:
            w = [(p + "_shoulder", 1.0)]
        rings.append((c, ra * k, ra * k * 0.95, w))
    for t, k in [(0.0, 1.02), (0.14, 1.1 + 0.05 * m), (0.35, 1.0), (0.62, 0.80), (0.85, 0.66), (1.0, 0.60)]:
        c = el + (wr - el) * t
        if t == 0.0:
            w = [(p + "_shoulder", 0.35), (p + "_elbow", 0.65)]
        elif t < 0.2:
            w = [(p + "_shoulder", 0.1), (p + "_elbow", 0.9)]
        else:
            w = [(p + "_elbow", 1.0)]
        rings.append((c, rf * k * 1.05, rf * k * 0.92, w))
    part.loft(rings, 12, True, False)


def leg(ctx, part: Part, p: str):
    H, d, b = ctx.H, ctx.dims, ctx.body
    hip, kn, an = ctx.rest[p + "_hip"], ctx.rest[p + "_knee"], ctx.rest[p + "_foot"]
    rt, rc = d["thigh_r"] * H * 0.84 * (0.88 + 0.14 * b["thigh"]), d["calf_r"] * H * 0.88 * (0.9 + 0.1 * b["thigh"])
    m = b["muscle"]
    rings = []
    # glute and hip at the top, quadriceps sweep, narrowing to the knee
    for t, k, yo in [(-0.18, 1.04, 0.004), (-0.05, 1.07, 0.006), (0.12, 1.07 + 0.04 * m, 0.0), (0.35, 1.08 + 0.05 * m, -0.003), (0.62, 0.92, -0.002), (0.88, 0.72, 0.0), (1.0, 0.68, 0.0)]:
        c = hip + (kn - hip) * t + Vector((0, yo * H, 0))
        if t < 0.0:
            mm = 0.7 + (t + 0.18) * 1.5
            w = [("pelvis", 1 - mm), (p + "_hip", mm)]
        elif t > 0.85:
            w = [(p + "_hip", 0.65), (p + "_knee", 0.35)]
        elif t > 0.6:
            mm = (t - 0.6) / 0.25 * 0.3
            w = [(p + "_hip", 1 - mm), (p + "_knee", mm)]
        else:
            w = [(p + "_hip", 1.0)]
        rings.append((c, rt * k, rt * k * 1.02, w))
    # calf: the gastrocnemius bulges at the back (+Y) below the knee
    for t, k, yo in [(0.04, 0.80, 0.0), (0.14, 1.0 + 0.1 * m, 0.006), (0.28, 1.10 + 0.12 * m, 0.010), (0.5, 0.92, 0.006), (0.78, 0.62, 0.0), (0.93, 0.55, 0.0), (1.0, 0.54, 0.0)]:
        c = kn + (an - kn) * t + Vector((0, yo * H, 0))
        if t < 0.05:
            w = [(p + "_hip", 0.35), (p + "_knee", 0.65)]
        elif t > 0.8:
            mm = smoothstep(0.82, 1.0, t) * 0.5
            w = [(p + "_knee", 1 - mm), (p + "_foot", mm)]
        else:
            w = [(p + "_knee", 1.0)]
        rings.append((c, rc * k, rc * k * 1.08, w))
    part.loft(rings, 12, True, True)


def hand(ctx, part: Part, p: str, with_fingers: bool):
    H = ctx.H
    wr = ctx.rest[p + "_hand"]
    bone = p + "_hand"
    palm = 0.052 * H * ctx.dims["hand"]
    hs = ctx.dims["hand"]
    rings = [
        (wr + Vector((0, 0, 0.006)), 0.0125 * hs, 0.026 * hs, [(bone, 0.85), (p + "_elbow", 0.15)]),
        (wr + Vector((0, 0, -palm * 0.2)), 0.0150 * hs, 0.036 * hs, [(bone, 1.0)]),
        (wr + Vector((0, 0, -palm * 0.6)), 0.0142 * hs, 0.042 * hs, [(bone, 1.0)]),
        (wr + Vector((0, 0, -palm)), 0.0115 * hs, 0.043 * hs, [(bone, 1.0)]),
    ]
    part.loft(rings, 10, True, True, squareness=2.4)
    # the thenar pad at the base of the thumb
    part.ellipsoid((wr.x, wr.y - 0.026 * hs, wr.z - palm * 0.38), (0.013 * hs, 0.016 * hs, 0.026 * hs), bone, 4, 8)
    if not with_fingers:
        # a mitten when the model has no finger bones
        part.loft([(wr + Vector((0, 0, -palm)), 0.0105 * hs, 0.041 * hs, [(bone, 1.0)]), (wr + Vector((0, 0, -palm - 0.07 * hs)), 0.0065 * hs, 0.034 * hs, [(bone, 1.0)])], 8, False, True)
        return
    for digit, (yo, start, length, split, radius, spread) in DIGITS.items():
        b1 = finger_bone_name(p, digit, 1)
        b2 = finger_bone_name(p, digit, 2)
        z0 = wr.z - palm * start
        dy = -math.sin(spread)
        dz = -math.cos(spread)
        base = Vector((wr.x, wr.y + yo * hs, z0))
        pts = []
        radii = []
        weights = []
        n = 6
        for i in range(n + 1):
            t = i / n
            pts.append(base + Vector((0, dy * length * t * hs, dz * length * t * hs)))
            r = radius * hs * (1.0 - 0.28 * t)
            radii.append((r * 0.9, r))
            if t < split - 0.12:
                weights.append([(b1, 1.0)])
            elif t < split + 0.12:
                mm = (t - (split - 0.12)) / 0.24
                weights.append([(b1, 1 - mm), (b2, mm)])
            else:
                weights.append([(b2, 1.0)])
        tube(part, pts, radii, weights, 7, True, True)
