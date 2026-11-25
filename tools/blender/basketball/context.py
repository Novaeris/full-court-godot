"""Shared build context: the standard, the player height, rest positions and the body type, so every basketball part agrees on the same numbers."""
import json
import os

from mathutils import Vector

from fc_character.rig import to_blender
from fc_character.mesh import smoothstep

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

BODY_TYPES = {
    # mass: torso and limb thickness; muscle: definition bumps; shoulder: shoulder and chest width; thigh: leg mass; belly: waist depth
    "lean": {"mass": 0.90, "muscle": 0.70, "shoulder": 0.95, "thigh": 0.90, "belly": 0.0},
    "athletic": {"mass": 1.00, "muscle": 1.00, "shoulder": 1.00, "thigh": 1.00, "belly": 0.0},
    "heavy": {"mass": 1.14, "muscle": 1.05, "shoulder": 1.07, "thigh": 1.16, "belly": 0.06},
}


def load_standard() -> dict:
    with open(os.path.join(ROOT, "data", "player_pipeline", "rig_standard.json"), encoding="utf-8") as handle:
        return json.load(handle)


class Context:
    def __init__(self, standard: dict, height: float, body: str = "athletic"):
        self.std = standard
        self.H = height
        self.scale = height / standard["height_m"]
        self.dims = standard["proportions_as_fractions_of_height"]
        self.body_name = body
        self.body = BODY_TYPES[body]
        self.rest = {}
        for bone in standard["bones"]:
            x, y, z = bone["rest"]
            self.rest[bone["name"]] = to_blender(Vector((x, y, z)) * self.scale)

    # --- torso profile (shared by the skin and the clothes so they fit) ----------------------------------------------------------
    def torso_section(self, t: float):
        """Half-width and half-depth (as fractions of H) of the torso at t (0 hips, 1 neck base), including the body type."""
        d = self.dims
        b = self.body
        hip = (d["hip_rx"] * b["mass"], d["hip_rz"] * b["mass"])
        waist = (d["waist_rx"] * b["mass"], (d["waist_rz"] + b["belly"] * 0.2 * d["waist_rz"] * 5) * b["mass"])
        chest = (d["chest_rx"] * b["shoulder"], d["chest_rz"] * b["mass"] * (1.0 + 0.06 * b["muscle"]))
        mix = lambda a, c, k: (a[0] + (c[0] - a[0]) * k, a[1] + (c[1] - a[1]) * k)
        if t < 0.17:
            return mix((hip[0] * 0.96, hip[1] * 0.95), hip, t / 0.17)
        if t < 0.40:
            return mix(hip, waist, smoothstep(0, 1, (t - 0.17) / 0.23))
        if t < 0.82:
            return mix(waist, chest, smoothstep(0, 1, (t - 0.40) / 0.42))
        girdle = (chest[0] * 1.10, chest[1] * 0.80)   # the shoulder girdle: wider than the chest, flatter front to back
        neck = (d["neck_r"] * 1.26 * (0.95 + 0.1 * b["mass"]), d["neck_r"] * 1.22)
        if t < 0.90:
            return mix(chest, girdle, smoothstep(0, 1, (t - 0.82) / 0.08))
        if t > 1.0:
            return neck
        return mix(girdle, neck, smoothstep(0, 1, (t - 0.90) / 0.10) ** 1.8)

    def torso_z(self, t: float) -> float:
        return (self.rest["pelvis"].z - 0.06 * self.H) * (1 - t) + 0.835 * self.H * t

    def torso_weights(self, z: float):
        k = smoothstep(self.rest["pelvis"].z - 0.01 * self.H, self.rest["pelvis"].z + 0.16 * self.H, z)
        return [("pelvis", 1 - k), ("torso", k)]
