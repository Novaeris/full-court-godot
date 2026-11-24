"""Production player build (Production Phase M1): headless Blender, reproducible.

    blender -b --python tools/blender/build_player_m1.py -- --out-dir assets/players [--only athletic|lean|heavy|heads|hair] [--height 1.98] [--keep-blend dir]

Writes (all on the rig standard, 16 bones; the main players also carry the x_ finger bones):
    fc_player_lean.glb / fc_player_athletic.glb / fc_player_heavy.glb   body, hands with fingers, clothing, shoes, default eyes and short hair
    parts/fc_parts_head.glb    swappable head parts: skin_head_<face><jaw>, nose_<k>, nostrils_<k>, lips_<k>, brow_<k>, eyes_<k>
    parts/fc_parts_hair.glb    hair_<style>, facial_<style>_<jaw>, acc_headband
The game (FcPlayerAssetLibrary) attaches the parts that match a player identity. docs/development/PLAYER_ASSET_LIBRARY.md has the names.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "basketball"))

import body as B  # noqa: E402
import clothing as C  # noqa: E402
import context as X  # noqa: E402
import hair as R  # noqa: E402
import head as H  # noqa: E402
from fc_character.export import export_glb, triangles  # noqa: E402
from fc_character.materials import material  # noqa: E402
from fc_character.rig import build_armature  # noqa: E402

SKIN = (0.62, 0.42, 0.28)


def arguments() -> dict:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"out_dir": os.path.join(X.ROOT, "assets", "players"), "only": None, "height": 1.98, "keep": None}
    i = 0
    while i < len(argv):
        key = argv[i]
        if key == "--out-dir":
            out["out_dir"] = os.path.abspath(argv[i + 1]); i += 2
        elif key == "--only":
            out["only"] = argv[i + 1]; i += 2
        elif key == "--height":
            out["height"] = float(argv[i + 1]); i += 2
        elif key == "--keep-blend":
            out["keep"] = os.path.abspath(argv[i + 1]); i += 2
        else:
            i += 1
    return out


def materials() -> dict:
    return {
        "skin": material("skin", SKIN, 0.55),
        "features": material("features", (1, 1, 1), 0.3, vertex_color=True),
        "hair": material("hair", (0.06, 0.04, 0.03), 0.8),
        "lips": material("lips", (0.45, 0.22, 0.18), 0.5),
        "jersey": material("jersey", (0.18, 0.44, 0.93), 0.8),
        "shorts": material("shorts", (0.18, 0.44, 0.93), 0.8),
        "socks": material("socks", (0.95, 0.95, 0.95), 0.85),
        "shoes": material("shoes", (0.95, 0.95, 0.95), 0.5),
        "sole": material("sole", (0.9, 0.9, 0.9), 0.6),
        "trim": material("trim", (0.95, 0.95, 0.95), 0.7),
        "accessory": material("accessory", (0.95, 0.95, 0.95), 0.8),
    }


def start(ctx, fingers: bool):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    extra = B.finger_bones(ctx) if fingers else ()
    arm, _ = build_armature(ctx.std, ctx.scale, ctx.H, B.tails(ctx), extra)
    return arm, materials()


def build_main(opts: dict, body: str) -> str:
    ctx = X.Context(X.load_standard(), opts["height"], body)
    arm, mats = start(ctx, True)
    skin = B.build_skin(ctx, True)
    skin.merge(H.build_base_head(ctx))
    objs = [skin.to_object("skin", mats["skin"], arm)]
    objs.append(H.build_eyes(ctx, 1).to_object("features", mats["features"], arm))
    jersey, jtrim = C.build_jersey(ctx)
    shorts, strim = C.build_shorts(ctx)
    socks, ktrim = C.build_socks(ctx)
    shoes, sole, shtrim = C.build_shoes(ctx)
    trim = jtrim
    for extra in (strim, ktrim, shtrim):
        trim.merge(extra)
    objs += [jersey.to_object("jersey", mats["jersey"], arm, uv=C.cylinder_uv(ctx)), shorts.to_object("shorts", mats["shorts"], arm, uv=C.cylinder_uv(ctx)), socks.to_object("socks", mats["socks"], arm),
             shoes.to_object("shoes", mats["shoes"], arm), sole.to_object("sole", mats["sole"], arm), trim.to_object("trim", mats["trim"], arm),
             R.build_hair(ctx, "short").to_object("hair_short", mats["hair"], arm)]
    path = os.path.join(opts["out_dir"], "fc_player_%s.glb" % body)
    export_glb(path)
    save_blend(opts, "player_%s" % body)
    return "%s: %d triangles, %d bones" % (os.path.basename(path), triangles(objs), len(arm.data.bones))


def build_heads(opts: dict) -> str:
    ctx = X.Context(X.load_standard(), opts["height"], "athletic")
    arm, mats = start(ctx, False)
    objs = []
    for f in range(len(H.FACES)):
        for j in range(3):
            objs.append(H.build_skin_head(ctx, f, j).to_object("skin_head_%d%d" % (f, j), mats["skin"], arm))
    for k in range(3):
        nose, nostrils = H.build_nose(ctx, k)
        objs.append(nose.to_object("nose_%d" % k, mats["skin"], arm))
        objs.append(nostrils.to_object("nostrils_%d" % k, mats["features"], arm))
        objs.append(H.build_lips(ctx, k).to_object("lips_%d" % k, mats["lips"], arm))
        objs.append(H.build_brows(ctx, k).to_object("brow_%d" % k, mats["hair"], arm))
        objs.append(H.build_eyes(ctx, k).to_object("eyes_%d" % k, mats["features"], arm))
    path = os.path.join(opts["out_dir"], "parts", "fc_parts_head.glb")
    export_glb(path)
    save_blend(opts, "parts_head")
    return "fc_parts_head.glb: %d triangles over %d parts" % (triangles(objs), len(objs))


def build_hair(opts: dict) -> str:
    ctx = X.Context(X.load_standard(), opts["height"], "athletic")
    arm, mats = start(ctx, False)
    objs = []
    for style in ("short", "fade", "afro", "curly", "long", "braids", "locs"):
        objs.append(R.build_hair(ctx, style).to_object("hair_" + style, mats["hair"], arm))
    for style in ("stubble", "goatee", "beard"):
        for j in range(3):
            objs.append(R.build_facial_hair(ctx, style, j).to_object("facial_%s_%d" % (style, j), mats["hair"], arm))
    objs.append(R.build_headband(ctx).to_object("acc_headband", mats["accessory"], arm))
    path = os.path.join(opts["out_dir"], "parts", "fc_parts_hair.glb")
    export_glb(path)
    save_blend(opts, "parts_hair")
    return "fc_parts_hair.glb: %d triangles over %d parts" % (triangles(objs), len(objs))


def save_blend(opts: dict, name: str):
    if opts["keep"]:
        os.makedirs(opts["keep"], exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(opts["keep"], name + ".blend"))


def main():
    opts = arguments()
    only = opts["only"]
    lines = []
    for body in ("lean", "athletic", "heavy"):
        if only in (None, body):
            lines.append(build_main(opts, body))
    if only in (None, "heads"):
        lines.append(build_heads(opts))
    if only in (None, "hair"):
        lines.append(build_hair(opts))
    for line in lines:
        print("FC_BUILD_OK " + line)


if __name__ == "__main__":
    main()
