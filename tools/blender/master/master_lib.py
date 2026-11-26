"""The master player workflow (D-076): ONE hand-improved Blender file is the source of truth for the Full Court player; scripts only export, validate and
integrate it. Shared helpers for the master scripts:

  art_source/players/fc_master_player.blend   the master (Git LFS). Only modeling passes write it, and only after a versioned backup.
  art_source/players/versions/                  backups: fc_master_player_<UTC timestamp>_<label>.blend (Git LFS)

Component collections in the master (modular: a uniform or a pair of shoes can be swapped without touching the body):
  FC_Rig        the Armature (16 standard bones + x_ extensions)
  FC_Body       skin
  FC_Head       eyes, lashes, brow_*
  FC_Uniform    jersey, shorts, socks, trim
  FC_Shoes      shoes, sole, equip_laces
  FC_Hair       hair_*          (exported to the part file)
  FC_Facial     facial_*        (part file)
  FC_Equipment  equip_* except the laces, acc_*   (part file)
Every mesh carries the same named morph targets (fcb_ body, fcf_ face) as shape keys. Shape keys in Blender store ABSOLUTE positions, so an edit of the
basis alone would be undone by every morph: modeling passes must move vertices through move_vertices(), which applies the same offset to every key.
"""
import datetime
import hashlib
import os
import shutil

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MASTER_DIR = os.path.join(ROOT, "art_source", "players")
MASTER = os.path.join(MASTER_DIR, "fc_master_player.blend")
VERSIONS = os.path.join(MASTER_DIR, "versions")

BODY_COLLECTIONS = ["FC_Rig", "FC_Body", "FC_Head", "FC_Uniform", "FC_Shoes"]
PART_COLLECTIONS = ["FC_Hair", "FC_Facial", "FC_Equipment"]


def collection_for(name: str) -> str:
    if name == "Armature":
        return "FC_Rig"
    if name == "skin":
        return "FC_Body"
    if name in ("eyes", "lashes") or name.startswith("brow_"):
        return "FC_Head"
    if name in ("jersey", "shorts", "socks", "trim"):
        return "FC_Uniform"
    if name in ("shoes", "sole", "equip_laces"):
        return "FC_Shoes"
    if name.startswith("hair_"):
        return "FC_Hair"
    if name.startswith("facial_"):
        return "FC_Facial"
    if name.startswith("equip_") or name.startswith("acc_"):
        return "FC_Equipment"
    return ""


def file_hash(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def backup(label: str) -> str:
    """Copies the master to versions/ before any change. Returns the backup path."""
    os.makedirs(VERSIONS, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in label)[:40]
    dst = os.path.join(VERSIONS, "fc_master_player_%s_%s.blend" % (stamp, safe))
    shutil.copy2(MASTER, dst)
    return dst


def save_master(label: str):
    """Saves the open master after a versioned backup of the previous one. Only modeling passes call this; exports never do."""
    if os.path.abspath(bpy.data.filepath) != os.path.abspath(MASTER):
        raise RuntimeError("the open file is not the master; refusing to save over it")
    path = backup(label)
    bpy.ops.wm.save_mainfile(filepath=MASTER, compress=True)
    for extra in (MASTER + "1",):   # Blender's own .blend1 copy: the versions folder is the backup
        if os.path.exists(extra):
            os.remove(extra)
    print("FC_MASTER saved (backup %s)" % os.path.basename(path))


def move_vertices(obj, offsets: dict):
    """Moves vertices by offset in the basis AND in every morph target, so the morphs keep working on the improved shape. offsets: {index: Vector}."""
    me = obj.data
    if me.shape_keys is None:
        for i, d in offsets.items():
            me.vertices[i].co += d
        me.update()
        return
    for kb in me.shape_keys.key_blocks:
        for i, d in offsets.items():
            kb.data[i].co += d
    for i, d in offsets.items():
        me.vertices[i].co = me.shape_keys.key_blocks[0].data[i].co
    me.update()


def meshes_in(collections):
    out = []
    for cname in collections:
        c = bpy.data.collections.get(cname)
        if c is not None:
            out += [o for o in c.objects if o.type == "MESH"]
    return out
