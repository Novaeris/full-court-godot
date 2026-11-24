"""The standard armature (data/player_pipeline/rig_standard.json) plus optional extension bones (x_ prefix)."""
import bpy
from mathutils import Vector


def to_blender(game: Vector) -> Vector:
    """Game (x right-left, y up, z forward) to Blender (x, -z, y): the character faces -Y in Blender."""
    return Vector((game.x, -game.z, game.y))


def build_armature(standard: dict, scale: float, height: float, tails, extra_bones=()):
    """tails(name, rest) gives each standard bone tail. extra_bones: iterable of (name, parent, head, tail) in Blender units (x_ prefixed)."""
    rest = {}
    for bone in standard["bones"]:
        x, y, z = bone["rest"]
        rest[bone["name"]] = to_blender(Vector((x, y, z)) * scale)
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    edit = {}
    for bone in standard["bones"]:
        name = bone["name"]
        e = arm_data.edit_bones.new(name)
        e.head = rest[name]
        e.tail = tails(name, rest)
        e.roll = 0.0
        edit[name] = e
    for name, parent, head, tail in extra_bones:
        e = arm_data.edit_bones.new(name)
        e.head = head
        e.tail = tail
        e.roll = 0.0
        edit[name] = e
    for bone in standard["bones"]:
        if bone["parent"]:
            edit[bone["name"]].parent = edit[bone["parent"]]
    for name, parent, head, tail in extra_bones:
        edit[name].parent = edit[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm["fc_standard_version"] = int(standard["standard_version"])
    arm["fc_height_m"] = float(height)
    return arm, rest
