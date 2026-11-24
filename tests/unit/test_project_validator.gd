extends FcTestCase
## The project validator (tools/validate_project.gd, run in CI) and the animation clip validator: each check is proven to catch the breakage it claims to,
## on fixture folders and hand-made clips, and the real player models of the project are valid.

const DIR := "user://validator_fixture"


func before_each() -> void:
	super.before_each()
	FcSafeFile.remove_tree(DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func after_each() -> void:
	FcSafeFile.remove_tree(DIR)
	super.after_each()


func _write(name: String, text: String) -> String:
	var path := DIR.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func _contains(problems: Array[String], text: String) -> bool:
	for p in problems:
		if p.contains(text):
			return true
	return false


## Runs tools/validate_project.gd in a SEPARATE Godot process on a fixture folder (a script with an error makes the test harness abort the test that
## loads it, so the proof that a broken script is caught runs outside it). Returns {"code": exit code, "text": its output}.
func _run_validator_on(folder: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/validate_project.gd", "--", "root=" + ProjectSettings.globalize_path(folder)], output, true)
	return {"code": code, "text": "
".join(PackedStringArray(output))}


func test_scripts_that_do_not_compile_are_found_by_the_validator_tool() -> void:
	_write("good.gd", "extends RefCounted
func ok() -> int:
	return 1
")
	var clean := _run_validator_on(DIR)
	assert_eq(clean["code"], 0, "a folder with only good scripts passes: %s" % clean["text"])
	assert_true(FcProjectValidator.compiles(DIR.path_join("good.gd")), "a good script compiles")
	_write("bad.gd", "extends RefCounted
func broken( -> int:
	return
")
	var broken := _run_validator_on(DIR)
	assert_eq(broken["code"], 1, "a folder with a broken script fails (exit code 1)")
	assert_true(str(broken["text"]).contains("bad.gd does not compile"), "and names the script: %s" % broken["text"])
	assert_true(not str(broken["text"]).contains("good.gd does not compile"), "but not the good one")


func test_invalid_json_is_found_with_its_line() -> void:
	_write("good.json", "{\"a\": 1}")
	_write("bad.json", "{\n\"a\": 1,\n\"b\": \n}")
	var problems := FcProjectValidator.check_json(DIR)
	assert_eq(problems.size(), 1)
	assert_true(_contains(problems, "bad.json") and _contains(problems, "line"))


func test_a_resource_that_needs_a_missing_file_is_found() -> void:
	_write("ok.tres", "[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	_write("broken.tres", "[gd_resource type=\"Resource\" load_steps=2 format=3]\n\n[ext_resource type=\"Texture2D\" path=\"res://assets/definitely_not_here.png\" id=\"1_a\"]\n\n[resource]\n")
	var problems := FcProjectValidator.check_resources(DIR)
	assert_true(_contains(problems, "broken.tres"), "the resource with a missing dependency is reported: %s" % str(problems))
	assert_true(not _contains(problems, "ok.tres"), "the good one is not")


func test_assets_that_are_not_imported_are_found_and_gdignore_hides_a_folder() -> void:
	_write("pic.png", "not really a png")
	_write("hidden/.gdignore", "")
	_write("hidden/secret.png", "x")
	_write("model.glb", "x")
	_write("model.glb.import", "[remap]\nimporter=\"scene\"\n")
	var problems := FcProjectValidator.check_assets(DIR)
	assert_true(_contains(problems, "pic.png has no .import file"), "an asset with no .import file is reported: %s" % str(problems))
	assert_true(_contains(problems, "model.glb is not imported"), "an asset whose import is not loadable is reported")
	assert_true(not _contains(problems, "secret.png"), "a folder with .gdignore is skipped, as Godot skips it")


func test_the_real_player_models_of_the_project_are_valid() -> void:
	assert_eq(FcProjectValidator.check_player_models("res://assets/players"), [], "every model in assets/players passes the validator")
	assert_true(FcProjectValidator.files("res://assets/players", ["glb"]).size() >= 1, "and there is at least the prototype")


func _clip(name_value: String, length: float = 1.0) -> Animation:
	var a := Animation.new()
	a.length = length
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("Armature/Skeleton3D:l_hip"))
	a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	a.rotation_track_insert_key(t, length, Quaternion(Vector3.RIGHT, 0.5))
	return a


func test_a_good_clip_is_compatible_and_each_kind_of_bad_clip_is_caught() -> void:
	assert_eq(FcAnimationClipValidator.validate_animation("run", _clip("run")), [], "a clip named after a state that rotates a standard bone is fine")
	assert_eq(FcAnimationClipValidator.validate_animation("x_wave", _clip("x_wave")), [], "an x_ extension name is allowed")
	assert_true(_contains(FcAnimationClipValidator.validate_animation("dance", _clip("dance")), "not named after an animation state"), "a name that is not a state")
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", _clip("run", 0.05)), "s long"), "too short")
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", _clip("run", 30.0)), "s long"), "too long")
	var empty := Animation.new()
	empty.length = 1.0
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", empty), "no tracks"), "no tracks")
	var tail := _clip("run")
	tail.track_set_path(0, NodePath("Armature/Skeleton3D:tail"))
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", tail), "not a standard bone"), "a bone that is not in the standard")
	var moved := _clip("run")
	var t := moved.add_track(Animation.TYPE_POSITION_3D)
	moved.track_set_path(t, NodePath("Armature/Skeleton3D:l_knee"))
	moved.position_track_insert_key(t, 0.0, Vector3.ZERO)
	moved.position_track_insert_key(t, 1.0, Vector3.UP)
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", moved), "only the pelvis may be translated"), "moving a bone other than the pelvis")
	var root_ok := _clip("run")
	var r := root_ok.add_track(Animation.TYPE_POSITION_3D)
	root_ok.track_set_path(r, NodePath("Armature/Skeleton3D:pelvis"))
	root_ok.position_track_insert_key(r, 0.0, Vector3(0, 1, 0))
	root_ok.position_track_insert_key(r, 1.0, Vector3(0, 0.9, 0))
	assert_eq(FcAnimationClipValidator.validate_animation("run", root_ok), [], "the pelvis may move")
	var scaled := _clip("run")
	var s := scaled.add_track(Animation.TYPE_SCALE_3D)
	scaled.track_set_path(s, NodePath("Armature/Skeleton3D:l_hip"))
	scaled.scale_track_insert_key(s, 0.0, Vector3.ONE)
	scaled.scale_track_insert_key(s, 1.0, Vector3.ONE * 2.0)
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", scaled), "scale tracks are not allowed"), "scaling a bone")
	var no_keys := Animation.new()
	no_keys.length = 1.0
	var k := no_keys.add_track(Animation.TYPE_ROTATION_3D)
	no_keys.track_set_path(k, NodePath("Armature/Skeleton3D:l_hip"))
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", no_keys), "has no keys"), "a rotation track with no keys")
	var constant := Animation.new()
	constant.length = 1.0
	var c := constant.add_track(Animation.TYPE_ROTATION_3D)
	constant.track_set_path(c, NodePath("Armature/Skeleton3D:l_hip"))
	constant.rotation_track_insert_key(c, 0.0, Quaternion.IDENTITY)
	assert_eq(FcAnimationClipValidator.validate_animation("run", constant), [], "a bone that does not move has one key, which is fine")
	var value := Animation.new()
	value.length = 1.0
	var v := value.add_track(Animation.TYPE_VALUE)
	value.track_set_path(v, NodePath("Armature/Skeleton3D:l_hip"))
	value.track_insert_key(v, 0.0, 1.0)
	assert_true(_contains(FcAnimationClipValidator.validate_animation("run", value), "unsupported type"), "a track that is not a bone transform")


func test_the_project_has_no_animation_clips_that_break_the_standard_yet() -> void:
	assert_eq(FcProjectValidator.check_animation_clips("res://assets/animations"), [])


func test_the_audio_data_is_valid_and_each_kind_of_mistake_is_caught() -> void:
	assert_eq(FcProjectValidator.check_audio("res://data/ui/audio.json"), [], "the real audio data passes")
	var good := {"buses": ["UI", "SFX"], "sounds": {"click": {"bus": "UI", "gain_db": -6.0, "synth": {"layers": [{"wave": "sine", "freq": 440, "ms": 50}]}}}}
	assert_eq(FcProjectValidator.check_audio(_write("good_audio.json", JSON.stringify(good))), [])
	var bad_bus := {"buses": ["UI"], "sounds": {"x": {"bus": "Nowhere", "gain_db": 0.0, "synth": {"layers": [{"wave": "sine", "ms": 10}]}}}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a1.json", JSON.stringify(bad_bus))), "not in the bus list"), "a sound on an unknown bus")
	var loud := {"buses": ["SFX"], "sounds": {"x": {"bus": "SFX", "gain_db": 20.0, "synth": {"layers": [{"wave": "sine", "ms": 10}]}}}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a2.json", JSON.stringify(loud))), "allowed -40 to 6"), "a gain that would blow the speakers")
	var empty_sound := {"buses": ["SFX"], "sounds": {"x": {"bus": "SFX", "gain_db": 0.0}}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a3.json", JSON.stringify(empty_sound))), "neither a synth recipe nor a file"), "a sound with nothing to play")
	var missing_file := {"buses": ["SFX"], "sounds": {"x": {"bus": "SFX", "gain_db": 0.0, "file": "res://assets/audio/not_there.ogg"}}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a4.json", JSON.stringify(missing_file))), "does not exist"), "a missing file with no synth fallback")
	var loop_on_sfx := {"buses": ["SFX"], "sounds": {"x": {"bus": "SFX", "gain_db": 0.0, "loop": true, "synth": {"layers": [{"wave": "sine", "ms": 10}]}}}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a5.json", JSON.stringify(loop_on_sfx))), "only Ambience and Music loop"), "a looping effect")
	var no_setting := {"buses": ["Foghorn"], "sounds": {}}
	assert_true(_contains(FcProjectValidator.check_audio(_write("a6.json", JSON.stringify(no_setting))), "no volume setting"), "a bus that has no volume setting")
	assert_true(_contains(FcProjectValidator.check_audio(_write("a7.json", "[1, 2]")), "must be a JSON object"), "not even an object")


func test_every_bus_can_be_turned_down_and_the_bounce_sound_is_a_real_effect() -> void:
	var audio := FcAudio.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/audio.json"))
	assert_eq((data["buses"] as Array).size(), 7, "seven buses: UI, SFX, Music, Crowd, Ambience, Commentary, Announcer")
	for bus in data["buses"]:
		assert_true(audio.bus_percent(str(bus)) >= 0, "%s has a volume" % bus)
	assert_true(data["sounds"].has("court_bounce") and data["sounds"]["court_bounce"]["bus"] == "SFX", "the bounce is an effect, so the Effects volume controls it")
	assert_true(FcBroadcastAudio.bounce_heard(5.0, 4.0, 1.0, true), "a bounce a second after the last, at normal speed, while playing")
	assert_true(not FcBroadcastAudio.bounce_heard(5.0, 4.9, 1.0, true), "not in a rapid burst")
	assert_true(not FcBroadcastAudio.bounce_heard(5.0, 4.0, 2.0, true), "not at fast forward")
	assert_true(not FcBroadcastAudio.bounce_heard(5.0, 4.0, 1.0, false), "not while paused")
	audio.free()
