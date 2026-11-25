"""Thin wrapper over the MPFB add-on (MakeHuman for Blender; GPL, a build tool only: nothing of it ships). Only CC0 data is used: the MPFB core data
(base mesh, targets, rigs, weights) and the makehuman_system_assets pack. Installed by tools/blender/install_mpfb.ps1 (D-075)."""
import importlib
import os

import bpy

PKG = "bl_ext.user_default.mpfb"


def _service(module: str, name: str):
    return getattr(importlib.import_module("%s.services.%s" % (PKG, module)), name)


def services():
    return {
        "human": _service("humanservice", "HumanService"),
        "target": _service("targetservice", "TargetService"),
        "location": _service("locationservice", "LocationService"),
        "clothes": _service("clothesservice", "ClothesService"),
        "props": getattr(importlib.import_module(PKG + ".entities.objectproperties"), "HumanObjectProperties"),
    }


def available() -> bool:
    try:
        importlib.import_module(PKG + ".services.humanservice")
        return True
    except ImportError:
        return False


def user_asset(*parts) -> str:
    return os.path.join(services()["location"].get_user_data(), *parts)


def system_target(name: str) -> str:
    return services()["target"].target_full_path(name)


def create(macros: dict):
    """A basemesh with the given macro values (gender, age, muscle, weight, proportions, height, race {...})."""
    s = services()
    info = s["target"].get_default_macro_info_dict()
    for k, v in macros.items():
        if k == "race":
            info["race"].update(v)
        else:
            info[k] = v
    return s["human"].create_human(macro_detail_dict=info)


def set_macros(basemesh, values: dict):
    s = services()
    for k, v in values.items():
        s["props"].set_value(k, v, entity_reference=basemesh)
    s["target"].reapply_macro_details(basemesh, remove_zero_weight_targets=False)


def get_macros(basemesh, names) -> dict:
    s = services()
    return {n: s["props"].get_value(n, entity_reference=basemesh) for n in names}


def add_target_key(basemesh, target: str, key_name: str):
    """Loads a MakeHuman target as a shape key with weight 0 (returns the key)."""
    s = services()
    s["target"].load_target(basemesh, system_target(target), weight=0.0, name=key_name)
    return basemesh.data.shape_keys.key_blocks[key_name]


def add_asset(basemesh, mhclo: str, asset_type: str, material_type: str = "MAKESKIN"):
    return services()["human"].add_mhclo_asset(mhclo, basemesh, asset_type=asset_type, subdiv_levels=0, material_type=material_type)


def refit(basemesh, assets):
    clothes = services()["clothes"]
    for a in assets:
        clothes.fit_clothes_to_human(a, basemesh, set_parent=False)
    bpy.context.view_layer.update()
