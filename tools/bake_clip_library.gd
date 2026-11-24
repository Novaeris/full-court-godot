extends SceneTree
## Converts the clip GLB that came out of Blender (assets/animations/source/fc_player_clips.glb) into a native Godot animation library
## (assets/animations/fc_player_clips.res) that the game loads. Why not just let the editor import the GLB: Godot's scene importer re-fits animation tracks
## with an optimizer tied to the animation/fps import setting, which dropped keys at the peak of fast movements (a sprint cycle lost up to 3% of the body
## height of accuracy; measured in tests/unit/test_player_pipeline.gd); reading the GLB directly keeps every key. A native resource also exports without
## the source file. Every clip is checked with FcAnimationClipValidator first; if anything is wrong nothing is written and the exit code is 1.
##   godot_console --headless --path . --script res://tools/bake_clip_library.gd [-- source=res://...glb out=res://...res]

const SOURCE := "res://assets/animations/source/fc_player_clips.glb"
const OUT := "res://assets/animations/fc_player_clips.res"


func _initialize() -> void:
	var source := SOURCE
	var out := OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("source="):
			source = arg.trim_prefix("source=")
		elif arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(source, state)
	if err != OK:
		print("FAIL: cannot read ", source, " (error ", err, ")")
		quit(1)
		return
	var root := doc.generate_scene(state, 30.0, false, false)
	var library := AnimationLibrary.new()
	var problems: Array[String] = []
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for library_name in player.get_animation_library_list():
			var found := player.get_animation_library(library_name)
			for clip_name in found.get_animation_list():
				var animation := found.get_animation(clip_name).duplicate() as Animation
				problems.append_array(FcAnimationClipValidator.validate_animation(str(clip_name), animation))
				animation.loop_mode = Animation.LOOP_LINEAR   # every state is a loop
				library.add_animation(clip_name, animation)
	root.free()
	if library.get_animation_list().is_empty():
		problems.append("%s contains no animations" % source)
	if not problems.is_empty():
		for p in problems:
			print("PROBLEM  ", p)
		print("FAIL: ", problems.size(), " problem(s); nothing was written")
		quit(1)
		return
	var saved := ResourceSaver.save(library, out)
	print("wrote ", out, ": ", library.get_animation_list().size(), " clips (", saved, ")")
	quit(0 if saved == OK else 1)
