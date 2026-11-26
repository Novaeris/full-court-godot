"""Modeling pass: moves the master's base shape by a weighted mix of its own morph targets (D-076). Every mesh that carries a listed morph moves by the
same amounts (the garments, hair and equipment were captured from the body, so they stay fitted), and every morph keeps working on the new base.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_bake_shape.py -- --label <label> --mix fcb_vshape=0.4,fcf_cheeks_hollow=0.3 [--dry-run]
Backs up the master first (master_lib.save_master)."""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    mix = {}
    for item in argv[argv.index("--mix") + 1].split(","):
        k, v = item.split("=")
        mix[k.strip()] = float(v)
    dry = "--dry-run" in argv
    moved = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        kbs = obj.data.shape_keys.key_blocks
        basis = kbs[0]
        offsets = {}
        for name, w in mix.items():
            kb = kbs.get(name)
            if kb is None:
                continue
            for i in range(len(basis.data)):
                d = (kb.data[i].co - basis.data[i].co) * w
                if d.length_squared > 1e-12:
                    offsets[i] = offsets.get(i, d * 0) + d
        if offsets:
            M.move_vertices(obj, offsets)
            moved[obj.name] = len(offsets)
    arm = bpy.data.objects["Armature"]
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: %s" % (label, ",".join("%s=%g" % kv for kv in mix.items())))
    arm["fc_master_passes"] = history
    print("FC_PASS %s moved %s" % (label, {k: v for k, v in sorted(moved.items())[:12]}))
    if not dry:
        M.save_master(label)


main()
