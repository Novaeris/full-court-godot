"""Full Court player V2 base character (D-075): MakeHuman CC0 base mesh made by MPFB, converted to the Full Court rig, with named body and face morphs.

    blender -b --python tools/blender/v2/build_v2.py -- --out assets/players/v2/fc_v2_body.glb [--keep-blend dir] [--quick]

Steps: create the base human -> game_engine rig -> eyes, brows, lashes -> pose the arms down (the standard rest) -> snapshot every mesh -> for each morph:
apply it, refit the attached assets, capture every mesh as a shape key -> new armature with Full Court names -> export GLB (no images: the game owns
the shaders and textures). --quick limits the morphs to a handful for fast iteration.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))

import mh  # noqa: E402
import morphs as MO  # noqa: E402
import rig_convert as RC  # noqa: E402
import garments as G  # noqa: E402
import hair as HA  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BROWS = ["eyebrow001", "eyebrow006", "eyebrow009", "eyebrow011"]


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"out": os.path.join(ROOT, "assets", "players", "v2", "fc_v2_body.glb"), "keep": None, "quick": False, "no_garments": False}
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out["out"] = os.path.abspath(argv[i + 1]); i += 2
        elif argv[i] == "--keep-blend":
            out["keep"] = os.path.abspath(argv[i + 1]); i += 2
        elif argv[i] == "--no-garments":
            out["no_garments"] = True; i += 1
        elif argv[i] == "--quick":
            out["quick"] = True; i += 1
        else:
            i += 1
    return out


def coords(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    out = [v.co.copy() for v in me.vertices]
    ev.to_mesh_clear()
    return out


def snapshot(obj, name):
    """A plain mesh object holding the evaluated shape of `obj` (modifiers applied), with the same vertex group names."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.name = name
    new = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(new)
    for g in obj.vertex_groups:
        new.vertex_groups.new(name=g.name)
    if me.shape_keys is None:
        new.shape_key_add(name="Basis", from_mix=False)
    return new


def drop_cornea(eyes):
    """The MakeHuman eye has a clear cornea shell in front of the eyeball, mapped onto the black corner of the eye texture (meant to be transparent).
    The game eye shader gives the eyeball its gloss, so the shell is removed: faces whose texture coordinates all lie in that corner."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(eyes.data)
    uv = bm.loops.layers.uv.active
    doomed = []
    if uv is not None:
        for f in bm.faces:
            if all(l[uv].uv.x > 0.80 and l[uv].uv.y < 0.20 for l in f.loops):
                doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(eyes.data)
    bm.free()
    print("FC_V2 eyes: removed %d cornea faces" % len(doomed))


def export(path, arm, objects):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for ob in objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=False, export_yup=True, export_skins=True, export_animations=False,
                              export_extras=True, export_materials="EXPORT", export_morph=True, export_morph_normal=True, export_try_sparse_sk=True,
                              use_selection=True, export_image_format="NONE", export_vertex_color="ACTIVE")


def build_parts(skin, arm):
    """M4 and M6: every hair style, facial hair style, the headband and the equipment, in a separate part file the game attaches per player."""
    L = G.landmarks(arm)
    face_keys = [k.name for k in skin.data.shape_keys.key_blocks[1:] if k.name.startswith("fcf_")]
    scalp_keys = [k for k in face_keys if k.startswith(("fcf_head", "fcf_forehead", "fcf_brow_ridge", "fcf_ears"))]
    jaw_keys = [k for k in face_keys if k.startswith(("fcf_head", "fcf_jaw", "fcf_chin", "fcf_cheek", "fcf_mouth", "fcf_lips", "fcf_nose", "fcf_asym_jaw", "fcf_asym_mouth"))]
    body_keys = [k.name for k in skin.data.shape_keys.key_blocks[1:] if k.name.startswith("fcb_")]
    made = {}
    for style in HA.STYLES:
        made["hair_" + style] = (HA.build_style(skin, style), scalp_keys, "hair")
    for style in HA.FACIAL:
        made["facial_" + style] = (HA.build_facial(skin, style), jaw_keys, "hair")
    made["acc_headband"] = (HA.build_headband(skin), scalp_keys, "accessory")
    for name, obj in G.equipment(skin, L).items():
        made[name] = (obj, body_keys, "equipment")
    out = {}
    for name, (obj, keys, mat_name) in made.items():
        obj.name = obj.data.name = name
        G.transfer_weights(obj, skin)
        G.fill_unweighted(obj)
        G.box_uv(obj)
        G.bind_morphs(obj, skin, keys)
        obj.parent = arm
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        out[name] = obj
    return out


def clean_weights(finals, arm):
    """Only bone groups ship: MakeHuman helper groups are removed, then every vertex has a bone weight, at most four, normalised."""
    bones = set(b.name for b in arm.data.bones)
    for obj in finals.values():
        for g in list(obj.vertex_groups):
            if g.name not in bones:
                obj.vertex_groups.remove(g)
        G.fill_unweighted(obj)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.vertex_group_limit_total(limit=4)
        bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def build_garments(skin, arm):
    """M5: jersey, shorts, socks and their trim, made from the body and following every body morph (see garments.py)."""
    L = G.landmarks(arm)
    body_keys = [k.name for k in skin.data.shape_keys.key_blocks[1:] if k.name.startswith("fcb_")]
    made = {}
    pieces = {"jersey": G.jersey(skin, L), "shorts": G.shorts(skin, L), "socks": G.socks(skin, L)}
    z0 = 0.997 * float(arm["fc_height_m"]) / 1.98
    loops = G.border_loops(pieces["jersey"]) + [lp for lp in G.border_loops(pieces["shorts"]) if sum(c.z for c, _ in lp) / len(lp) < L["pelvis"].z]
    loops += [lp for lp in G.border_loops(pieces["socks"]) if sum(c.z for c, _ in lp) / len(lp) > L["l_foot"].z + 0.08]
    trim = G.trim("trim", loops, 0.0045)
    for name, obj in pieces.items():
        G.finish(obj, thickness=0.004 if name != "socks" else 0.0)
        if name in ("jersey", "shorts"):
            G.cylinder_uv(obj, z0, 0.62 * float(arm["fc_height_m"]) / 1.98)
        made[name] = obj
    made["trim"] = trim
    upper, sole, laces = G.shoes(skin, L)
    print("FC_V2 shoes: hid %d foot faces" % G.hide_feet(skin, L))
    made["shoes"], made["sole"], made["equip_laces"] = upper, sole, laces
    laces.name = laces.data.name = "equip_laces"
    for name, obj in made.items():
        G.transfer_weights(obj, skin)
        if name in ("jersey", "shorts", "socks", "trim"):
            G.drop_groups(obj, keep_shoulders=False)   # cloth follows the spine and pelvis; an arm moving must not lift the jersey sides
        G.fill_unweighted(obj)
        G.box_uv(obj)
        G.bind_morphs(obj, skin, body_keys)
        obj.parent = arm
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        mat_name = "equipment" if name.startswith("equip_") else name
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return made


def main():
    o = args()
    if not mh.available():
        raise SystemExit("MPFB is not installed: run tools/blender/install_mpfb.ps1")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = mh.services()
    base = mh.create(MO.BASE_MACROS)
    rig = s["human"].add_builtin_rig(base, "game_engine")
    assets = {"eyes": mh.add_asset(base, mh.user_asset("eyes", "high-poly", "high-poly.mhclo"), "Eyes", "PROCEDURAL_EYES"),
              "lashes": mh.add_asset(base, mh.user_asset("eyelashes", "eyelashes01", "eyelashes01.mhclo"), "Eyelashes")}
    for b in BROWS:
        assets["brow_" + b[-3:]] = mh.add_asset(base, mh.user_asset("eyebrows", b, b + ".mhclo"), "Eyebrows")
    RC.pose_arms_down(rig)
    # morph target shape keys (weight 0) on the basemesh
    chosen = MO.ALL[:4] + MO.FACE[:4] if o["quick"] else MO.ALL
    target_keys = {}
    for name, kind, spec in chosen:
        if kind == "targets":
            target_keys[name] = [(mh.add_target_key(base, t, "%s__%d" % (name, i)), w) for i, (t, w) in enumerate(spec)]
    macro_names = ["gender", "age", "muscle", "weight", "proportions", "height"]
    base_macros = mh.get_macros(base, macro_names)
    bpy.context.view_layer.update()
    finals = {"skin": snapshot(base, "skin")}
    for key, a in assets.items():
        finals[key] = snapshot(a, key)
    height = max(v.z for v in coords(base)) - min(v.z for v in coords(base))
    # body macros (mass, muscle) must not change the face: athletes do not get a fat face with weight. Head weight per skin vertex masks them.
    head_gi = finals["skin"].vertex_groups["head"].index if "head" in finals["skin"].vertex_groups else -1
    neck_gi = finals["skin"].vertex_groups["neck_01"].index if "neck_01" in finals["skin"].vertex_groups else -1
    head_mask = []
    for v in finals["skin"].data.vertices:
        w = 0.0
        for g in v.groups:
            if g.group == head_gi:
                w += g.weight
            elif g.group == neck_gi:
                w += 0.5 * g.weight
        head_mask.append(min(1.0, w))
    base_coords = {fname: [v.co.copy() for v in ob.data.vertices] for fname, ob in finals.items()}
    print("FC_V2 base height %.3f m, skin %d verts" % (height, len(finals["skin"].data.vertices)))
    for name, kind, spec in chosen:
        if kind == "macro":
            mh.set_macros(base, spec)
        else:
            for key, w in target_keys[name]:
                key.value = w
        mh.refit(base, list(assets.values()))
        sources = {"skin": base}
        sources.update(assets)
        for fname, src in sources.items():
            c = coords(src)
            k = finals[fname].shape_key_add(name=name, from_mix=False)
            base_c = base_coords[fname]
            for i, p in enumerate(c):
                if kind == "macro":
                    keep = 0.0 if fname != "skin" else 1.0 - head_mask[i]
                    p = base_c[i] + (p - base_c[i]) * keep
                k.data[i].co = p
        if kind == "macro":
            mh.set_macros(base, base_macros)
        else:
            for key, w in target_keys[name]:
                key.value = 0.0
    mh.refit(base, list(assets.values()))
    arm = RC.build_standard_armature(rig, height)
    drop_cornea(finals["eyes"])
    for fname, obj in finals.items():
        RC.rename_groups(obj)
        if fname != "skin":
            for g in list(obj.vertex_groups):
                obj.vertex_groups.remove(g)
            g = obj.vertex_groups.new(name="head")
            g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        obj.parent = arm
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        # plain materials named for the game (no images: the game owns the shaders and textures)
        mat_name = {"skin": "skin", "eyes": "eyes", "lashes": "lashes"}.get(fname, "brows")
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    for ob in [base, rig] + list(assets.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    parts = {}
    if not o["no_garments"]:
        finals.update(build_garments(finals["skin"], arm))
        if not o["quick"]:
            parts = build_parts(finals["skin"], arm)
    for ob in list(bpy.data.objects):
        if ob.type == "MESH" and ob.name not in finals and ob.name not in parts:
            bpy.data.objects.remove(ob, do_unlink=True)
    clean_weights(finals, arm)
    clean_weights(parts, arm)
    os.makedirs(os.path.dirname(o["out"]), exist_ok=True)
    export(o["out"], arm, finals.values())
    if parts:
        parts_out = os.path.join(os.path.dirname(o["out"]), "parts", "fc_v2_parts.glb")
        os.makedirs(os.path.dirname(parts_out), exist_ok=True)
        export(parts_out, arm, parts.values())
        print("FC_V2_PARTS %s %d parts" % (parts_out, len(parts)))
    if o["keep"]:
        os.makedirs(o["keep"], exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(o["keep"], "fc_v2_body.blend"))
    tris = sum(len(p.vertices) - 2 for ob in finals.values() for p in ob.data.polygons)
    print("FC_V2_OK %s height %.3f bones %d meshes %d triangles %d morphs %d" % (o["out"], height, len(arm.data.bones), len(finals), tris, len(chosen)))


if __name__ == "__main__":
    main()
