"""Turns MPFB's game_engine rig (53 bones) into the Full Court rig: the 16 standard bone names (data/player_pipeline/rig_standard.json) and the rest as x_
extensions, with the standard rest pose (arms hanging straight down). The skin weights MakeHuman ships for that rig are kept; only the names change."""
import bpy
from mathutils import Vector

STANDARD = {
    "pelvis": "pelvis", "spine_01": "torso", "neck_01": "neck", "head": "head",
    "upperarm_l": "l_shoulder", "lowerarm_l": "l_elbow", "hand_l": "l_hand", "upperarm_r": "r_shoulder", "lowerarm_r": "r_elbow", "hand_r": "r_hand",
    "thigh_l": "l_hip", "calf_l": "l_knee", "foot_l": "l_foot", "thigh_r": "r_hip", "calf_r": "r_knee", "foot_r": "r_foot",
}
EXTRA = {"spine_02": "x_spine_02", "spine_03": "x_spine_03", "clavicle_l": "x_clavicle_l", "clavicle_r": "x_clavicle_r", "ball_l": "x_l_toe", "ball_r": "x_r_toe"}
for _side in ("l", "r"):
    for _digit in ("thumb", "index", "middle", "ring", "pinky"):
        for _j in (1, 2, 3):
            EXTRA["%s_0%d_%s" % (_digit, _j, _side)] = "x_%s_%s_%d" % (_side, _digit, _j)
NAMES = dict(STANDARD)
NAMES.update(EXTRA)


def pose_arms_down(rig, outward: float = 0.10):
    """Poses the MakeHuman A-pose into the standard rest: each upper arm hangs straight down (a little away from the body) and the forearm is in line."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for side, sx in (("l", 1.0), ("r", -1.0)):
        upper = rig.data.bones["upperarm_" + side]
        lower = rig.data.bones["lowerarm_" + side]
        hand = rig.data.bones["hand_" + side]
        d_up = (lower.head_local - upper.head_local).normalized()
        d_low = (hand.head_local - lower.head_local).normalized()
        target = Vector((sx * outward, 0.0, -1.0)).normalized()
        q_up = d_up.rotation_difference(target)
        lu = upper.matrix_local.to_quaternion()
        pb = rig.pose.bones["upperarm_" + side]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = lu.inverted() @ q_up @ lu
        q_low = d_low.rotation_difference(d_up)
        ll = lower.matrix_local.to_quaternion()
        pl = rig.pose.bones["lowerarm_" + side]
        pl.rotation_mode = "QUATERNION"
        pl.rotation_quaternion = ll.inverted() @ q_low @ ll
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()


def build_standard_armature(rig, height: float, model_version: int = 2):
    """A new armature whose rest is the CURRENT pose of the MakeHuman rig, with Full Court names. Returns it."""
    bpy.context.view_layer.update()
    posed = {}
    for pb in rig.pose.bones:
        if pb.name in NAMES:
            m = rig.matrix_world @ pb.matrix
            posed[pb.name] = (rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail, m)
    data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    edit = {}
    for src, (head, tail, m) in posed.items():
        e = data.edit_bones.new(NAMES[src])
        e.head = head
        e.tail = tail
        e.align_roll(m.to_3x3() @ Vector((0, 0, 1)))
        edit[src] = e
    for src in posed:
        parent = rig.data.bones[src].parent
        while parent is not None and parent.name not in NAMES:
            parent = parent.parent
        if parent is not None:
            edit[src].parent = edit[parent.name]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm["fc_standard_version"] = 1
    arm["fc_model_version"] = model_version
    arm["fc_height_m"] = float(height)
    return arm


def rename_groups(obj):
    for g in obj.vertex_groups:
        if g.name in NAMES:
            g.name = NAMES[g.name]
