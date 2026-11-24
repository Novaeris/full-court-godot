class_name FcAnimationClipValidator
extends RefCounted
## Checks the animation clips inside a GLB (made in Blender, see docs/development/PLAYER_ANIMATION_PIPELINE.md) for compatibility with the Full Court player
## rig, and reports every problem in plain words (empty = compatible). A clip that passes can be played on any standard player, whatever its proportions.
##
## The rules: a clip is named after the animation state it plays (one of FcBroadcastPose.STATES, or x_something for an extension); it animates only the 16
## standard bones (or x_ extension bones), by rotation, and by position only on the pelvis (the root: a jump or a crouch moves the hips, but moving any other
## bone would change the proportions of the player), never by scale; it is between 0.2 and 8 seconds long; every rotation track has at least one key (a bone that does not move has one: Godot collapses constant tracks on import); every
## value is finite and every rotation is a unit quaternion. Tracks for properties other than bones (blend shapes, methods) are not allowed.

const MIN_SECONDS := 0.2
const MAX_SECONDS := 8.0


## Validates every clip of a clip file: a native animation library (.res or .tres, what the game loads) or a GLB (the Blender output).
static func validate_path(path: String) -> Array[String]:
	var out: Array[String] = []
	if path.get_extension().to_lower() in ["res", "tres"]:
		var library := load(path) as AnimationLibrary
		if library == null:
			out.append("is not an animation library or cannot be loaded")
			return out
		if library.get_animation_list().is_empty():
			out.append("contains no animation clips")
		for clip_name in library.get_animation_list():
			out.append_array(validate_animation(str(clip_name), library.get_animation(clip_name)))
		return out
	if not ResourceLoader.exists(path):
		out.append("does not exist or has not been imported")
		return out
	var packed := load(path) as PackedScene
	if packed == null:
		out.append("cannot be loaded as a scene")
		return out
	var root := packed.instantiate()
	var clips := 0
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for clip_name in library.get_animation_list():
				clips += 1
				out.append_array(validate_animation(str(clip_name), library.get_animation(clip_name)))
	root.free()
	if clips == 0:
		out.append("contains no animation clips")
	return out


## Every problem with one animation (empty = compatible).
static func validate_animation(clip_name: String, animation: Animation) -> Array[String]:
	var out: Array[String] = []
	var standard_bones := {}
	for bone in FcPlayerModelValidator.standard().get("bones", []):
		standard_bones[str(bone["name"])] = true
	if not (FcBroadcastPose.STATES.has(clip_name) or clip_name.begins_with("x_")):
		out.append("clip '%s' is not named after an animation state (%s) or x_something" % [clip_name, ", ".join(FcBroadcastPose.STATES)])
	if animation.length < MIN_SECONDS or animation.length > MAX_SECONDS:
		out.append("clip '%s' is %.2f s long (allowed %.1f to %.1f)" % [clip_name, animation.length, MIN_SECONDS, MAX_SECONDS])
	if animation.get_track_count() == 0:
		out.append("clip '%s' has no tracks" % clip_name)
	for t in animation.get_track_count():
		var path := str(animation.track_get_path(t))
		var bone := path.get_slice(":", 1) if path.contains(":") else ""
		var type := animation.track_get_type(t)
		if bone == "" or not (standard_bones.has(bone) or bone.begins_with("x_")):
			out.append("clip '%s' animates '%s', which is not a standard bone" % [clip_name, path])
			continue
		match type:
			Animation.TYPE_ROTATION_3D:
				if animation.track_get_key_count(t) < 1:
					out.append("clip '%s': the rotation of %s has no keys (a constant bone needs one key)" % [clip_name, bone])
				for k in animation.track_get_key_count(t):
					var q: Quaternion = animation.track_get_key_value(t, k)
					if not q.is_finite() or absf(q.length() - 1.0) > 0.01:
						out.append("clip '%s': %s has a rotation key that is not a unit quaternion" % [clip_name, bone])
						break
			Animation.TYPE_POSITION_3D:
				if bone != "pelvis" and not bone.begins_with("x_"):
					out.append("clip '%s' moves %s: only the pelvis may be translated (it would change the proportions)" % [clip_name, bone])
				for k in animation.track_get_key_count(t):
					if not (animation.track_get_key_value(t, k) as Vector3).is_finite():
						out.append("clip '%s': %s has a position key that is not a number" % [clip_name, bone])
						break
			Animation.TYPE_SCALE_3D:
				out.append("clip '%s' scales %s: scale tracks are not allowed" % [clip_name, bone])
			_:
				out.append("clip '%s' has a track of an unsupported type on %s" % [clip_name, bone])
	return out
