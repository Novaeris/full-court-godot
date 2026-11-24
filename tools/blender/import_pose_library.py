"""Turns the baked Full Court animation library into Blender Actions on the standard armature and exports them as a GLB clip file.

    godot_console --headless --path . --script res://tools/export_pose_library.gd          (writes build_tmp/pose_library.json)
    blender -b --python tools/blender/import_pose_library.py -- --library build_tmp/pose_library.json --out assets/animations/source/fc_player_clips.glb [--keep-blend clips.blend]
    godot_console --headless --path . --script res://tools/bake_clip_library.gd     (GLB to the native animation library the game loads)

One Action per animation state, named after the state, 30 frames a second, the last frame equal to the first so it loops. An animator opens the kept .blend,
edits any Action (the armature and bone names are the standard's), and exports again: the Godot side checks every clip with FcAnimationClipValidator.

The conversion (docs/development/PLAYER_ANIMATION_PIPELINE.md): the game stores each bone rotation q as a world-aligned rotation in Godot axes. Blender's axes
are rotated 90 degrees about X from Godot's, so q_blender = C q C^-1, and a Blender pose bone stores its rotation relative to its own global rest orientation B,
so the value to key is B^-1 q_blender B (the same conjugation FcRigRetarget does in the game). The pelvis translation is rotated into Blender axes and then into
the pelvis rest frame.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_player  # noqa: E402  (the same armature as the player model)

ROOT = build_player.ROOT


def arguments() -> dict:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"library": os.path.join(ROOT, "build_tmp", "pose_library.json"), "out": os.path.join(ROOT, "assets", "animations", "source", "fc_player_clips.glb"), "keep": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--library":
            out["library"] = os.path.abspath(argv[i + 1]); i += 2
        elif argv[i] == "--out":
            out["out"] = os.path.abspath(argv[i + 1]); i += 2
        elif argv[i] == "--keep-blend":
            out["keep"] = os.path.abspath(argv[i + 1]); i += 2
        else:
            i += 1
    return out


def main() -> None:
    options = arguments()
    with open(options["library"], encoding="utf-8") as handle:
        library = json.load(handle)
    with open(os.path.join(ROOT, "data", "player_pipeline", "rig_standard.json"), encoding="utf-8") as handle:
        standard = json.load(handle)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = int(library["fps"])
    builder = build_player.Builder(standard, standard["height_m"])
    arm = builder.armature()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    axes = Quaternion((1.0, 0.0, 0.0), math.pi / 2.0)           # Godot axes to Blender axes
    rest_q = {pb.name: pb.bone.matrix_local.to_quaternion() for pb in arm.pose.bones}
    rest_game = {b["name"]: Vector(b["rest"]) for b in standard["bones"]}
    arm.animation_data_create()
    made = 0
    for state, clip in library["clips"].items():
        action = bpy.data.actions.new(state)
        action.use_fake_user = True
        arm.animation_data.action = action
        frames = int(clip["frames"])
        for f in range(frames + 1):          # the extra last frame repeats the first, so the loop closes
            i = f % frames
            for pb in arm.pose.bones:
                x, y, z, w = clip["bones"][pb.name][i]
                q_blender = axes @ Quaternion((w, x, y, z)) @ axes.inverted()
                b = rest_q[pb.name]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = b.inverted() @ q_blender @ b
                pb.keyframe_insert("rotation_quaternion", frame=f)
            pelvis = arm.pose.bones["pelvis"]
            delta = Vector(clip["pelvis"][i]) - rest_game["pelvis"]
            pelvis.location = rest_q["pelvis"].inverted() @ (axes @ delta)
            pelvis.keyframe_insert("location", frame=f)
        # frames start at 0 because glTF time is frame / fps (a first key at frame 1 would put every key one frame late); the range is the loop, N + 1 keys
        action.use_frame_range = True
        action.frame_start = 0
        action.frame_end = frames
        for fcurve in getattr(action, "fcurves", []):
            for key in fcurve.keyframe_points:
                key.interpolation = "LINEAR"
        made += 1
    arm.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")
    os.makedirs(os.path.dirname(options["out"]), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=options["out"], export_format="GLB", export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
                              export_extras=True, export_force_sampling=False, export_optimize_animation_size=False, use_selection=False)
    if options["keep"]:
        bpy.ops.wm.save_as_mainfile(filepath=options["keep"])
    print("FC_CLIPS_OK out=%s actions=%d fps=%d" % (options["out"], made, scene.render.fps))


if __name__ == "__main__":
    main()
