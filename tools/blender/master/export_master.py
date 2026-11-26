"""Exports the master player to the game (D-076). READ ONLY: it never saves the master, and it proves it by comparing the master's SHA-256 before and
after. Writes assets/players/v2/fc_v2_body.glb (rig, body, head, uniform, shoes) and assets/players/v2/parts/fc_v2_parts.glb (hair, facial hair,
equipment). Validation, levels of detail and integration happen in Godot (FcPlayerModelValidator, FcPlayerLod), so this script only exports.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/export_master.py [-- --out-dir assets/players/v2]
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def export(path, objects, arm):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for ob in objects:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=False, export_yup=True, export_skins=True, export_animations=False,
                              export_extras=True, export_materials="EXPORT", export_morph=True, export_morph_normal=True, export_try_sparse_sk=True,
                              use_selection=True, export_image_format="NONE", export_vertex_color="ACTIVE")


def main():
    if os.path.abspath(bpy.data.filepath) != os.path.abspath(M.MASTER):
        raise SystemExit("open the master: blender -b %s --python ..." % M.MASTER)
    before = M.file_hash(M.MASTER)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[argv.index("--out-dir") + 1]) if "--out-dir" in argv else os.path.join(M.ROOT, "assets", "players", "v2")
    arm = bpy.data.objects["Armature"]
    body = M.meshes_in(M.BODY_COLLECTIONS)
    parts = M.meshes_in(M.PART_COLLECTIONS)
    export(os.path.join(out_dir, "fc_v2_body.glb"), body, arm)
    export(os.path.join(out_dir, "parts", "fc_v2_parts.glb"), parts, arm)
    tris = sum(len(p.vertices) - 2 for o in body for p in o.data.polygons)
    after = M.file_hash(M.MASTER)
    if before != after:
        raise SystemExit("FC_MASTER_CHANGED: the master file changed during export (it must never be written by an export)")
    print("FC_EXPORT_OK body %d meshes %d triangles, parts %d meshes; master unchanged %s" % (len(body), tris, len(parts), before[:12]))


main()
