"""Builds the Full Court prototype player in Blender and exports it as a GLB.

Run headless (no window):
    blender -b --python tools/blender/build_player.py -- --out assets/players/fc_player_proto.glb [--height 1.98] [--keep-blend path.blend]

What it makes (docs/development/ASSET_PRODUCTION_PIPELINE.md is the full standard):
  * ONE armature with the 16 standard bones of data/player_pipeline/rig_standard.json (taken from the skeleton the game already builds), at the standard
    rest pose: standing, arms hanging, feet flat. The character faces -Y in Blender (+Z in glTF and Godot); the left side is +X.
  * One mesh object per standard surface (skin, features, jersey, shorts, socks, shoes, sole) plus hair_short and hair_afro, each with a material of the
    SAME name (the game recolours materials by name: skin tone, team colours, hair colour), skinned to the armature with explicit weights so the joints bend
    smoothly. The proportions follow rig_standard.json, scaled to --height.
  * Custom properties (glTF extras) on the armature: fc_standard_version and fc_height_m, which the Godot validator checks.
This is a PROTOTYPE made by script so the whole pipeline (Blender, GLB, import, validation, retargeting, the game) can be proven end to end; an artist
replaces any part by modelling it in Blender under the same names and weights, and re-exports. Blender 4.5 LTS tested.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def arguments() -> dict:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"out": os.path.join(ROOT, "assets", "players", "fc_player_proto.glb"), "height": None, "keep": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out["out"] = os.path.abspath(argv[i + 1]); i += 2
        elif argv[i] == "--height":
            out["height"] = float(argv[i + 1]); i += 2
        elif argv[i] == "--keep-blend":
            out["keep"] = os.path.abspath(argv[i + 1]); i += 2
        else:
            i += 1
    return out


def smooth(a: float, b: float, v: float) -> float:
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


class Builder:
    def __init__(self, standard: dict, height: float):
        self.std = standard
        self.H = height
        self.scale = height / standard["height_m"]
        self.dims = standard["proportions_as_fractions_of_height"]
        self.rest = {}
        for bone in standard["bones"]:
            x, y, z = bone["rest"]
            self.rest[bone["name"]] = self.to_blender(Vector((x, y, z)) * self.scale)
        self.parents = {b["name"]: b["parent"] for b in standard["bones"]}

    @staticmethod
    def to_blender(game: Vector) -> Vector:
        """Game (x right-left, y up, z forward) to Blender (x, -z, y): the character faces -Y in Blender."""
        return Vector((game.x, -game.z, game.y))

    # --- armature ------------------------------------------------------------------------------------------------------------
    def armature(self) -> bpy.types.Object:
        arm_data = bpy.data.armatures.new("Armature")
        arm = bpy.data.objects.new("Armature", arm_data)
        bpy.context.collection.objects.link(arm)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        tails = {
            "pelvis": self.rest["pelvis"] + Vector((0, 0, 0.14 * self.scale)),
            "torso": self.rest["neck"], "neck": self.rest["head"], "head": self.rest["head"] + Vector((0, 0, 0.2 * self.scale)),
            "l_hand": self.rest["l_hand"] + Vector((0, 0, -0.09 * self.scale)), "r_hand": self.rest["r_hand"] + Vector((0, 0, -0.09 * self.scale)),
            "l_foot": self.rest["l_foot"] + Vector((0, -0.2 * self.scale, 0)), "r_foot": self.rest["r_foot"] + Vector((0, -0.2 * self.scale, 0)),
        }
        for side in ("l", "r"):
            tails[side + "_shoulder"] = self.rest[side + "_elbow"]
            tails[side + "_elbow"] = self.rest[side + "_hand"]
            tails[side + "_hip"] = self.rest[side + "_knee"]
            tails[side + "_knee"] = self.rest[side + "_foot"]
        edit = {}
        for bone in self.std["bones"]:
            name = bone["name"]
            e = arm_data.edit_bones.new(name)
            e.head = self.rest[name]
            e.tail = tails[name]
            e.roll = 0.0
            edit[name] = e
        for bone in self.std["bones"]:
            if bone["parent"]:
                edit[bone["name"]].parent = edit[bone["parent"]]
        bpy.ops.object.mode_set(mode="OBJECT")
        arm["fc_standard_version"] = int(self.std["standard_version"])
        arm["fc_height_m"] = float(self.H)
        return arm

    # --- mesh helpers --------------------------------------------------------------------------------------------------------
    def make_object(self, name: str, bm: bmesh.types.BMesh, weights: list, material: str, armature: bpy.types.Object) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = True
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        mat = bpy.data.materials.get(material) or bpy.data.materials.new(material)
        mat.use_nodes = True
        if not mesh.materials:
            mesh.materials.append(mat)
        groups = {}
        for i, pairs in enumerate(weights):
            for bone, w in pairs:
                if w <= 0.0001:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([i], w, "REPLACE")
        obj.parent = armature
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        return obj

    def loft(self, bm, weights, rings, segs=14, cap_start=False, cap_end=False, partial=None):
        """Sweep rings (centre, rx, ry, weights[(bone, w)]) along their order. rx is the width (X), ry the depth (Y, the front is -Y)."""
        first = len(bm.verts)
        per = segs
        for c, rx, ry, w in rings:
            for k in range(per):
                th = TAU * k / per
                v = bm.verts.new(Vector((c.x + rx * math.sin(th), c.y - ry * math.cos(th), c.z)))
                weights.append(w)
        bm.verts.ensure_lookup_table()
        for i in range(len(rings) - 1):
            for k in range(per):
                a = first + i * per + k
                b = first + i * per + (k + 1) % per
                c2 = first + (i + 1) * per + (k + 1) % per
                d = first + (i + 1) * per + k
                if len({a, b, c2, d}) == 4:
                    try:
                        bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[c2], bm.verts[d]))
                    except ValueError:
                        pass
        bm.verts.ensure_lookup_table()
        for index, cap in ((0, cap_start), (len(rings) - 1, cap_end)):
            if cap:
                ring = [bm.verts[first + index * per + k] for k in range(per)]
                try:
                    bm.faces.new(ring)
                except ValueError:
                    pass

    def ellipsoid(self, bm, weights, centre, radii, bone, rings=8, segs=14, lat_min=-math.pi / 2, lat_max=math.pi / 2):
        ring_list = []
        for i in range(rings + 1):
            phi = lat_min + (lat_max - lat_min) * i / rings
            r = max(math.cos(phi), 0.001)
            ring_list.append((Vector((centre.x, centre.y, centre.z + radii[2] * math.sin(phi))), radii[0] * r, radii[1] * r, [(bone, 1.0)]))
        self.loft(bm, weights, ring_list, segs, False, False)

    # --- profiles (ported from FcBodyBuilder, in metres) ---------------------------------------------------------------------------
    def torso_section(self, t: float):
        d = self.dims
        hip, waist, chest = (d["hip_rx"], d["hip_rz"]), (d["waist_rx"], d["waist_rz"]), (d["chest_rx"], d["chest_rz"])
        mix = lambda a, b, k: (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
        if t < 0.17:
            return mix((hip[0] * 0.96, hip[1] * 0.95), hip, t / 0.17)
        if t < 0.40:
            return mix(hip, waist, smooth(0, 1, (t - 0.17) / 0.23))
        if t < 0.82:
            return mix(waist, chest, smooth(0, 1, (t - 0.40) / 0.42))
        return mix(chest, (chest[0] * 0.66, chest[1] * 0.84), smooth(0, 1, (t - 0.82) / 0.18))

    def torso_y(self, t: float) -> float:
        return (self.rest["pelvis"].z - 0.06 * self.H) * (1 - t) + 0.835 * self.H * t

    def torso_weights(self, z: float):
        k = smooth(self.rest["pelvis"].z - 0.01 * self.H, self.rest["pelvis"].z + 0.16 * self.H, z)
        return [("pelvis", 1 - k), ("torso", k)]

    # --- the parts -------------------------------------------------------------------------------------------------------------
    def skin(self, arm):
        bm = bmesh.new()
        weights = []
        H = self.H
        rings = []
        for t in [0.0, 0.08, 0.17, 0.28, 0.40, 0.55, 0.70, 0.82, 0.91, 0.97, 1.0]:
            rx, ry = self.torso_section(t)
            z = self.torso_y(t)
            rings.append((Vector((0, 0, z)), rx * H, ry * H, self.torso_weights(z)))
        nr = self.dims["neck_r"] * H
        for zf in (0.845, 0.865, 0.89):
            k = smooth(0.855 * H, 0.89 * H, zf * H)
            rings.append((Vector((0, 0, zf * H)), nr, nr * 0.92, [("neck", 1 - k), ("head", k)]))
        self.loft(bm, weights, rings, 16, True, True)
        for side in ("l", "r"):
            self.arm(bm, weights, side)
            self.leg(bm, weights, side)
        self.head(bm, weights)
        return self.make_object("skin", bm, weights, "skin", arm)

    def arm(self, bm, weights, p):
        H, d = self.H, self.dims
        sh, el, wr = self.rest[p + "_shoulder"], self.rest[p + "_elbow"], self.rest[p + "_hand"]
        ra, rf = d["arm_r"] * H, d["forearm_r"] * H
        rings = []
        for t, k, _ in [(-0.045, 0.9, 0), (0.0, 1.12, 0), (0.18, 1.1, 0), (0.5, 1.0, 0), (0.85, 0.82, 0), (1.0, 0.8, 0)]:
            c = sh + (el - sh) * t
            if t < 0.0:
                w = [("torso", 0.55), (p + "_shoulder", 0.45)]
            elif t < 0.15:
                m = 0.4 + t * 4
                w = [("torso", 1 - m), (p + "_shoulder", m)]
            elif t > 0.9:
                m = 0.35 + (t - 0.9) * 6
                w = [(p + "_shoulder", 1 - m), (p + "_elbow", m)]
            else:
                w = [(p + "_shoulder", 1.0)]
            rings.append((c, ra * k, ra * k * 0.95, w))
        for t, k in [(0.0, 0.98), (0.15, 1.0), (0.35, 0.92), (0.7, 0.72), (1.0, 0.62)]:
            c = el + (wr - el) * t
            w = [(p + "_shoulder", 0.35), (p + "_elbow", 0.65)] if t == 0.0 else [(p + "_elbow", 1.0)]
            rings.append((c, rf * k * 1.05, rf * k * 0.9, w))
        self.loft(bm, weights, rings, 10, True, False)
        # hand: a flat palm with four fingers and a thumb as one tapered block (a prototype; an artist models the real hand)
        bone = p + "_hand"
        palm = 0.052 * H * self.dims["hand"]
        width = 0.0185 * H * self.dims["hand"]
        rings = [(wr + Vector((0, 0, 0.004 * H)), 0.0085 * H, width * 0.62, [(bone, 1.0)]), (wr + Vector((0, 0, -palm * 0.35)), 0.0095 * H, width * 0.95, [(bone, 1.0)]),
                 (wr + Vector((0, 0, -palm)), 0.0080 * H, width, [(bone, 1.0)]), (wr + Vector((0, 0, -palm - 0.06 * H)), 0.0050 * H, width * 0.8, [(bone, 1.0)])]
        # the palm's width runs along Y (front-back) in this frame: swap so it spans the front-back direction like the game's hand
        rings = [(c, ry, rx, w) for c, rx, ry, w in rings]
        self.loft(bm, weights, rings, 8, True, True)

    def leg(self, bm, weights, p):
        H, d = self.H, self.dims
        hip, kn, an = self.rest[p + "_hip"], self.rest[p + "_knee"], self.rest[p + "_foot"]
        rt, rc = d["thigh_r"] * H, d["calf_r"] * H
        rings = []
        for t, k in [(-0.18, 1.04), (0.0, 1.0), (0.35, 0.9), (0.72, 0.72), (1.0, 0.66)]:
            c = hip + (kn - hip) * t
            if t < 0.0:
                m = 0.7 + (t + 0.18) * 1.5
                w = [("pelvis", 1 - m), (p + "_hip", m)]
            elif t > 0.9:
                w = [(p + "_hip", 0.65), (p + "_knee", 0.35)]
            else:
                w = [(p + "_hip", 1.0)]
            rings.append((c, rt * k, rt * k * 1.02, w))
        for t, k in [(0.04, 0.82), (0.14, 1.0), (0.3, 1.04), (0.6, 0.8), (0.9, 0.58), (1.0, 0.54)]:
            c = kn + (an - kn) * t + Vector((0, 0.1 * rc * math.sin(t * math.pi), 0))
            if t < 0.05:
                w = [(p + "_hip", 0.35), (p + "_knee", 0.65)]
            elif t > 0.8:
                m = smooth(0.82, 1.0, t) * 0.5
                w = [(p + "_knee", 1 - m), (p + "_foot", m)]
            else:
                w = [(p + "_knee", 1.0)]
            rings.append((c, rc * k, rc * k * 1.1, w))
        self.loft(bm, weights, rings, 10, True, True)

    def head_ring(self, u: float):
        d, H = self.dims, self.H
        hh = d["head_h"] * H
        chin = (0.995 - d["head_h"]) * H
        base = math.sqrt(max(1 - u * u, 0.0005))
        rx0, ry0 = hh * 0.34, hh * 0.425
        yc = ry0 * (0.07 * max(0, -u) - 0.05 * max(0, u))
        return chin + hh * 0.5 * (u + 1.0), rx0 * base, ry0 * base, yc, hh

    def head(self, bm, weights):
        rings = []
        n = 16
        for i in range(n + 1):
            u = -math.cos(math.pi * i / n)
            z, rx, ry, yc, hh = self.head_ring(u)
            rings.append((Vector((0, -yc, z)), rx, ry, [("head", 1.0)]))
        self.loft(bm, weights, rings, 18, False, False)
        z0, rx0, ry0, _, hh = self.head_ring(0.0)
        # nose and ears so the head is not a bare egg
        self.ellipsoid(bm, weights, Vector((0, -(ry0 + hh * 0.02), z0 - hh * 0.1)), (hh * 0.06, hh * 0.06, hh * 0.08), "head", 5, 8)
        for sx in (1, -1):
            self.ellipsoid(bm, weights, Vector((sx * rx0 * 0.97, ry0 * 0.05, z0)), (hh * 0.02, hh * 0.075, hh * 0.11), "head", 5, 8)

    def features(self, arm):
        bm = bmesh.new()
        weights = []
        z0, rx0, ry0, _, hh = self.head_ring(0.0)
        for sx in (1, -1):
            self.ellipsoid(bm, weights, Vector((sx * rx0 * 0.36, -(ry0 * 0.93), z0 + hh * 0.04)), (hh * 0.06, hh * 0.03, hh * 0.034), "head", 5, 8)
        self.ellipsoid(bm, weights, Vector((0, -(ry0 * 0.9), z0 - hh * 0.26)), (hh * 0.09, hh * 0.02, hh * 0.016), "head", 4, 10)
        return self.make_object("features", bm, weights, "features", arm)

    def hair(self, arm, style: str):
        bm = bmesh.new()
        weights = []
        z0, rx0, ry0, _, hh = self.head_ring(0.0)
        if style == "short":
            self.ellipsoid(bm, weights, Vector((0, ry0 * 0.04, z0)), (rx0 * 1.05, ry0 * 1.05, hh * 0.5 * 1.05), "head", 6, 14, math.asin(0.26), math.pi / 2)
        else:
            self.ellipsoid(bm, weights, Vector((0, ry0 * 0.3, z0 + hh * 0.15)), (rx0 * 1.5, ry0 * 1.35, hh * 0.5 * 1.36), "head", 8, 18, 0.08, math.pi / 2)
        return self.make_object("hair_" + style, bm, weights, "hair", arm)

    def jersey(self, arm):
        bm = bmesh.new()
        weights = []
        H = self.H
        rings = []
        for t in [0.30, 0.38, 0.50, 0.62, 0.74, 0.86, 0.91, 0.95, 0.985, 1.0]:
            rx, ry = self.torso_section(min(t, 0.88))
            rx, ry = rx + 0.008, ry + 0.007
            if t > 0.88:
                rx = rx + (self.dims["chest_rx"] * 0.52 - rx) * smooth(0.88, 1.0, t)
            z = self.torso_y(t)
            rings.append((Vector((0, 0, z)), rx * H, ry * H, self.torso_weights(z)))
        self.loft(bm, weights, rings, 28, False, False)
        return self.make_object("jersey", bm, weights, "jersey", arm)

    def shorts(self, arm):
        bm = bmesh.new()
        weights = []
        H, d = self.H, self.dims
        py = self.rest["pelvis"].z
        block = []
        for z, extra in [(py + 0.095 * H, 0.0), (py + 0.083 * H, 0.0), (py + 0.045 * H, 0.012), (py - 0.05 * H, 0.018), (py - 0.095 * H, 0.014)]:
            block.append((Vector((0, 0, z)), (d["hip_rx"] + 0.012 + extra) * H, (d["hip_rz"] + 0.012 + extra) * H, [("pelvis", 1.0)]))
        self.loft(bm, weights, block, 16, True, False)
        for p in ("l", "r"):
            hip, knee = self.rest[p + "_hip"], self.rest[p + "_knee"]
            hem = hip.z + (knee.z - hip.z) * 0.6
            legs = []
            for k in range(5):
                t = k / 4
                z = (py - 0.08 * H) * (1 - t) + hem * t
                r = d["thigh_r"] * H * (1.14 + 0.06 * t) + 0.008 * H
                m = smooth(py - 0.08 * H, hip.z, z) * 0.9 + (0.1 if k > 1 else 0.0)
                legs.append((Vector((hip.x, 0, z)), r, r * 1.04, [("pelvis", 1 - m), (p + "_hip", m)]))
            self.loft(bm, weights, legs, 12, False, True)
        return self.make_object("shorts", bm, weights, "shorts", arm)

    def socks(self, arm):
        bm = bmesh.new()
        weights = []
        H, d = self.H, self.dims
        for p in ("l", "r"):
            kn, an = self.rest[p + "_knee"], self.rest[p + "_foot"]
            rc = d["calf_r"] * H
            rings = []
            for t, k in [(0.3, 1.1), (0.55, 0.9), (0.8, 0.68), (1.0, 0.62)]:
                c = kn + (an - kn) * t + Vector((0, 0.1 * rc * math.sin(t * math.pi), 0))
                w = [(p + "_knee", 1.0)] if t < 0.8 else [(p + "_knee", 0.5), (p + "_foot", 0.5)]
                rings.append((c, rc * k, rc * k * 1.1, w))
            self.loft(bm, weights, rings, 10, False, False)
        return self.make_object("socks", bm, weights, "socks", arm)

    def shoes(self, arm):
        shoes, soles = bmesh.new(), bmesh.new()
        ws, wl = [], []
        H, d = self.H, self.dims
        fs = d["foot"]
        for p in ("l", "r"):
            an = self.rest[p + "_foot"]
            sole_z = an.z - 0.045 * H
            rings, slab = [], []
            for fz, hw, top in [(-0.04, 0.020, 0.062), (-0.028, 0.030, 0.075), (-0.006, 0.034, 0.078), (0.030, 0.036, 0.056), (0.068, 0.040, 0.038), (0.104, 0.038, 0.027), (0.128, 0.028, 0.017), (0.138, 0.012, 0.008)]:
                y = an.y - fz * H * fs   # the toes point to -Y
                cz = sole_z + 0.012 * H + (top * H * fs - 0.012 * H) * 0.5
                rings.append((Vector((an.x, y, cz)), hw * H * fs, 0.0, [(p + "_foot", 1.0)]))
                slab.append((Vector((an.x, y, sole_z + 0.006 * H)), hw * H * fs * 1.07, 0.0, [(p + "_foot", 1.0)]))
            self.shoe_loft(shoes, ws, rings, [top for _, _, top in [(0, 0, 0.062), (0, 0, 0.075), (0, 0, 0.078), (0, 0, 0.056), (0, 0, 0.038), (0, 0, 0.027), (0, 0, 0.017), (0, 0, 0.008)]], H * fs, sole_z)
            self.shoe_loft(soles, wl, slab, [0.012] * 8, H * fs, sole_z, thin=True)
        return self.make_object("shoes", shoes, ws, "shoes", arm), self.make_object("sole", soles, wl, "sole", arm)

    def shoe_loft(self, bm, weights, rings, tops, scale, sole_z, thin=False):
        """A shoe is swept along the foot (Y) with an ellipse in the X-Z plane: a width (rx) and a height."""
        first = len(bm.verts)
        segs = 10
        for (c, rx, _, w), top in zip(rings, tops):
            height = (top * scale - 0.012 * scale) * 0.5 if not thin else 0.006 * scale
            for k in range(segs):
                th = TAU * k / segs
                bm.verts.new(Vector((c.x + rx * math.sin(th), c.y, c.z + max(height, 0.001) * math.cos(th))))
                weights.append(w)
        bm.verts.ensure_lookup_table()
        for i in range(len(rings) - 1):
            for k in range(segs):
                a, b = first + i * segs + k, first + i * segs + (k + 1) % segs
                c2, d = first + (i + 1) * segs + (k + 1) % segs, first + (i + 1) * segs + k
                try:
                    bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[c2], bm.verts[d]))
                except ValueError:
                    pass
        for index in (0, len(rings) - 1):
            try:
                bm.faces.new([bm.verts[first + index * segs + k] for k in range(segs)])
            except ValueError:
                pass


TAU = math.tau


def main() -> None:
    options = arguments()
    with open(os.path.join(ROOT, "data", "player_pipeline", "rig_standard.json"), encoding="utf-8") as handle:
        standard = json.load(handle)
    height = options["height"] or standard["height_m"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    builder = Builder(standard, height)
    arm = builder.armature()
    builder.skin(arm)
    builder.features(arm)
    builder.jersey(arm)
    builder.shorts(arm)
    builder.socks(arm)
    builder.shoes(arm)
    for style in ("short", "afro"):
        builder.hair(arm, style)
    # default material colours so the model looks right even before the game recolours it (the game overrides them by material name)
    colours = {"skin": (0.80, 0.58, 0.41), "features": (0.1, 0.07, 0.06), "jersey": (0.18, 0.44, 0.93), "shorts": (0.18, 0.44, 0.93), "socks": (0.95, 0.95, 0.95),
               "shoes": (0.95, 0.95, 0.95), "sole": (0.9, 0.9, 0.9), "hair": (0.08, 0.06, 0.05)}
    for name, rgb in colours.items():
        mat = bpy.data.materials.get(name)
        if mat and mat.node_tree:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
                bsdf.inputs["Roughness"].default_value = 0.6
    os.makedirs(os.path.dirname(options["out"]), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=options["out"], export_format="GLB", export_apply=False, export_yup=True, export_skins=True, export_animations=False,
                              export_extras=True, export_materials="EXPORT", use_selection=False)
    if options["keep"]:
        bpy.ops.wm.save_as_mainfile(filepath=options["keep"])
    triangles = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == "MESH")
    print("FC_BUILD_OK out=%s height=%.3f bones=%d meshes=%d approx_triangles=%d" % (options["out"], height, len(arm.data.bones), sum(1 for o in bpy.data.objects if o.type == "MESH"), triangles))


if __name__ == "__main__":
    main()
