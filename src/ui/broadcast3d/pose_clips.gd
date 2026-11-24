class_name FcPoseClips
extends RefCounted
## The animation clips made in Blender (assets/animations/fc_player_clips.res, baked from the pose library and polished or replaced by an animator, exported as a
## GLB and converted by tools/bake_clip_library.gd; see docs/development/PLAYER_ANIMATION_PIPELINE.md): loaded once, checked with FcAnimationClipValidator, and sampled by animation state and loop phase.
## A clip stores, for the standard Blender armature, each bone's absolute local rotation (its own rest included) and the pelvis position, in metres, so a
## clip plays directly on a player model built from the same standard (FcBroadcastCharacter with `imported`). This class only reads and samples; it does not
## change how the game animates (the procedural pose library is still the live system: the migration plan is in the pipeline document).

var path: String = ""
var _animations: Dictionary = {}   # state -> Animation
var _tracks: Dictionary = {}       # state -> {bone: [rotation track index, position track index (-1 if none)]}


## Loads the clip file. Returns null when it is missing, cannot be loaded, has no clips, or any clip fails FcAnimationClipValidator (so a bad clip file is never
## half-used); `problems` (optional) receives the reasons.
static func load_file(clip_path: String, problems: Array[String] = []) -> FcPoseClips:
	var found := FcAnimationClipValidator.validate_path(clip_path)
	if not found.is_empty():
		problems.append_array(found)
		return null
	var result := FcPoseClips.new()
	result.path = clip_path
	var library := load(clip_path) as AnimationLibrary
	if library == null:
		problems.append("%s is not a native animation library (.res): convert a GLB with tools/bake_clip_library.gd" % clip_path)
		return null
	for clip_name in library.get_animation_list():
		result._add(str(clip_name), library.get_animation(clip_name))
	return result


func _add(state: String, animation: Animation) -> void:
	_animations[state] = animation
	var map := {}
	for t in animation.get_track_count():
		var bone := str(animation.track_get_path(t)).get_slice(":", 1)
		if not map.has(bone):
			map[bone] = [-1, -1]
		if animation.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			map[bone][0] = t
		elif animation.track_get_type(t) == Animation.TYPE_POSITION_3D:
			map[bone][1] = t
	_tracks[state] = map


func clip_names() -> Array:
	return _animations.keys()


func has_clip(state: String) -> bool:
	return _animations.has(state)


## How long one loop of the clip lasts, in seconds.
func length_of(state: String) -> float:
	return (_animations[state] as Animation).length if _animations.has(state) else 0.0


## The clip at `phase` (0 to 1 around the loop): {"rotations": {bone: Quaternion (absolute local)}, "pelvis": Vector3 or null (the pelvis position, metres)}.
func sample(state: String, phase: float) -> Dictionary:
	var animation: Animation = _animations[state]
	var time := fposmod(phase, 1.0) * animation.length
	var rotations := {}
	var pelvis: Variant = null
	var map: Dictionary = _tracks[state]
	for bone in map:
		var pair: Array = map[bone]
		if int(pair[0]) >= 0:
			rotations[bone] = animation.rotation_track_interpolate(int(pair[0]), time)
		if bone == "pelvis" and int(pair[1]) >= 0:
			pelvis = animation.position_track_interpolate(int(pair[1]), time)
	return {"rotations": rotations, "pelvis": pelvis}


## Poses `skeleton` (a player model built to the standard, in metres) with the clip at `phase`.
func apply(skeleton: Skeleton3D, state: String, phase: float) -> void:
	var sampled := sample(state, phase)
	for bone in sampled["rotations"]:
		var index := skeleton.find_bone(bone)
		if index >= 0:
			skeleton.set_bone_pose_rotation(index, sampled["rotations"][bone])
	if sampled["pelvis"] != null:
		skeleton.set_bone_pose_position(skeleton.find_bone("pelvis"), sampled["pelvis"])
