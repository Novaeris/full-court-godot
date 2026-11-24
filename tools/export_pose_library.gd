extends SceneTree
## Bakes the whole animation library (every state of FcBroadcastPose, including the ground contact and the two-hand ball IK the character adds on top) into
## keyframes at 30 frames a second, as JSON, so Blender can turn each state into an Action on the standard armature (tools/blender/import_pose_library.py),
## an animator can polish it there, and it can come back as a GLB clip file (assets/animations/fc_player_clips.glb) that Godot validates and plays.
##   godot_console --headless --path . --script res://tools/export_pose_library.gd [-- out=res://build_tmp/pose_library.json]
## The numbers are what the generated skeleton does: per bone the local rotation as a quaternion (the generated rest pose has no rest rotations, so this
## is the world-aligned rotation the retarget layer expects, see FcRigRetarget), and the pelvis position in metres. One loop of a state is `frames`
## frames; the frame after the last one is the first (all states loop). The file is derived data: it is not committed (build_tmp is git-ignored).

const FPS := 30
const FEET_PER_METRE := 3.28084


func _initialize() -> void:
	var out := "res://build_tmp/pose_library.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	var subject := {"key": "rig-standard", "name": "Standard", "jersey": 7, "position": "SF", "appearance": {"skin": "tone_3", "hair": "short", "facial_hair": "none"},
		"physical": {"height_cm": 198, "weight_kg": 95}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "STD", "name": "Standard"}}
	var c := FcBroadcastCharacter.new().setup(subject)
	c.auto_advance = false
	var clips := {}
	for state in FcBroadcastPose.STATES:
		var frames := maxi(2, roundi(float(FcBroadcastPose.CYCLE[state]) * FPS))
		var bones := {}
		for name in FcBodyBuilder.BONES:
			bones[name] = []
		var pelvis: Array = []
		for f in frames:
			c.pose_at(state, float(f) / float(frames))
			for name in FcBodyBuilder.BONES:
				var q := c.skeleton.get_bone_pose_rotation(c.skeleton.find_bone(name))
				(bones[name] as Array).append([snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)])
			var p := c.skeleton.get_bone_pose_position(c.skeleton.find_bone("pelvis")) / FEET_PER_METRE
			pelvis.append([snappedf(p.x, 0.00001), snappedf(p.y, 0.00001), snappedf(p.z, 0.00001)])
		clips[state] = {"length": float(FcBroadcastPose.CYCLE[state]), "frames": frames, "pelvis": pelvis, "bones": bones}
	var library := {"fps": FPS, "unit": "metres", "rotations": "local quaternions [x, y, z, w] in the Godot axes (Y up, +Z forward)", "clips": clips}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(library))
	file.close()
	print("wrote ", out, ": ", clips.size(), " clips")
	quit()
