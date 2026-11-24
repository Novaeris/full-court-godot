"""glTF binary export with the settings the Full Court pipeline requires (see docs/development/ASSET_PRODUCTION_PIPELINE.md)."""
import os

import bpy


def export_glb(path: str, only=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    use_selection = only is not None
    if use_selection:
        for obj in only:
            obj.select_set(True)
    else:
        bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=False, export_yup=True, export_skins=True, export_animations=False,
                              export_extras=True, export_materials="EXPORT", use_selection=use_selection)


def triangles(objects) -> int:
    return sum(len(p.vertices) - 2 for o in objects if o.type == "MESH" for p in o.data.polygons)
