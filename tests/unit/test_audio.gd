extends FcTestCase
## Phase 11: the sound layer. Sounds are built by the game (no third-party audio, D4), come from a data map, are silent when anything is
## missing, climb with rarity, obey the player's volumes and mute, and never decide anything in the game.

const PREFS := "user://test_preferences_audio.cfg"

var audio: FcAudio
var app: FcApp


func after_each() -> void:
	if audio != null:
		if audio.get_parent() != null:
			audio.get_parent().remove_child(audio)
		audio.free()
		audio = null
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	FcAudio.current = null


func _map() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FcAudio.MAP_PATH))


func _app() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_audio")
	Engine.get_main_loop().root.add_child(app)
	app.setup()


# --- the synthesiser --------------------------------------------------------------------------------------------------------------------

func test_a_recipe_renders_the_same_samples_every_time() -> void:
	var recipe: Dictionary = _map()["sounds"]["rarity_4"]["synth"]
	var a := FcAudioSynth.render(recipe, "rarity_4")
	var b := FcAudioSynth.render(recipe, "rarity_4")
	assert_eq(a, b, "deterministic")
	assert_eq(a.size(), int(FcAudioSynth.duration_ms(recipe) / 1000.0 * FcAudioSynth.MIX_RATE), "the length follows the recipe")
	assert_true(FcAudioSynth.render(recipe, "other") != a, "noise differs between sounds")


func test_every_sound_has_a_recipe_that_is_audible_and_never_clips() -> void:
	for id in _map()["sounds"]:
		var recipe: Dictionary = _map()["sounds"][id]["synth"]
		var samples := FcAudioSynth.render(recipe, id)
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		assert_true(samples.size() > 200, "%s has some length" % id)
		assert_true(peak > 0.05 and peak <= 0.9, "%s is audible and not clipped (peak %.2f)" % [id, peak])


func test_a_stream_is_a_16_bit_mono_wave() -> void:
	var recipe: Dictionary = _map()["sounds"]["ui_click"]["synth"]
	var wav := FcAudioSynth.stream(recipe, "ui_click")
	assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_true(not wav.stereo and wav.mix_rate == FcAudioSynth.MIX_RATE)
	assert_eq(wav.data.size(), FcAudioSynth.render(recipe, "ui_click").size() * 2)


# --- the sound map -------------------------------------------------------------------------------------------------------------------------

func test_the_map_is_well_formed() -> void:
	var map := _map()
	var buses: Array = map["buses"]
	assert_eq(buses, ["UI", "SFX", "Music"])
	for id in map["sounds"]:
		var def: Dictionary = map["sounds"][id]
		assert_true(def["bus"] in buses, "%s is on a real bus" % id)
		assert_true(def.has("synth"), "%s can always be heard (no file needed)" % id)
		assert_true(float(def["gain_db"]) <= 0.0, "%s is not boosted" % id)


func test_rarity_stings_climb_in_one_key() -> void:
	var sounds: Dictionary = _map()["sounds"]
	var last := 0
	for tier in 5:
		var id := "rarity_%d" % tier
		assert_true(sounds.has(id), "%s exists for every rarity intensity" % id)
		var length := FcAudioSynth.duration_ms(sounds[id]["synth"])
		assert_true(length > last, "%s is longer than the one before (%d ms)" % [id, length])
		last = length
		for layer in sounds[id]["synth"]["layers"]:
			if layer.get("wave", "") != "noise":
				assert_true(float(layer["freq"]) in [196.0, 262.0, 294.0, 392.0, 523.0, 659.0, 784.0, 1047.0], "%s stays in C major (%s Hz)" % [id, layer["freq"]])


func test_every_rarity_intensity_has_a_cue() -> void:
	for id in FcRarityStyle.STYLES.keys():
		var tier := clampi(FcRarityStyle.intensity(id), 0, 4)
		assert_true(_map()["sounds"].has("rarity_%d" % tier), "%s plays rarity_%d" % [id, tier])


func test_a_missing_map_or_file_is_silent_not_an_error() -> void:
	audio = FcAudio.new(FcPreferences.new(PREFS), "res://data/ui/does_not_exist.json")
	assert_eq(audio.sound_ids().size(), 0, "no map, no sounds")
	assert_true(not audio.play("ui_click"), "and playing nothing is fine")
	audio.free()
	audio = FcAudio.new(FcPreferences.new(PREFS))
	assert_eq(audio.source_of("ui_click"), "synth", "the audio file is missing, so the built sound is used")
	assert_true(not audio.play("no_such_sound"), "an unknown id is silent")


func test_no_audio_file_is_added_without_a_recorded_source() -> void:
	# D4: nothing unlicensed. A file under assets/audio must be listed, with its source and licence, in assets/audio/SOURCES.md.
	var dir := DirAccess.open("res://assets/audio")
	if dir == null:
		return
	var sources := FileAccess.get_file_as_string("res://assets/audio/SOURCES.md")
	for f in dir.get_files():
		if f.get_extension() in ["ogg", "wav", "mp3"]:
			assert_true(sources.contains(f), "%s has a recorded source and licence" % f)


# --- settings ----------------------------------------------------------------------------------------------------------------------------------

func test_the_sound_settings_are_saved_and_clamped() -> void:
	var p := FcPreferences.new(PREFS)
	assert_eq([p.audio_master, p.audio_ui, p.audio_sfx, p.audio_music, p.audio_muted, p.haptics], [80, 80, 80, 60, false, true], "defaults")
	p.audio_master = 35
	p.audio_sfx = 0
	p.audio_muted = true
	p.haptics = false
	assert_true(p.save_file())
	var back := FcPreferences.new(PREFS)
	assert_eq([back.audio_master, back.audio_sfx, back.audio_muted, back.haptics], [35, 0, true, false])
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("audio", "master", 500)
	cfg.save(PREFS)
	assert_eq(FcPreferences.new(PREFS).audio_master, 100, "a damaged value is clamped")


func test_volumes_and_mute_reach_the_audio_buses() -> void:
	var p := FcPreferences.new(PREFS)
	p.audio_master = 50
	p.audio_sfx = 25
	audio = FcAudio.new(p)
	audio.setup_buses()
	audio.setup_buses()   # safe to call twice
	for bus_name in ["UI", "SFX", "Music"]:
		assert_true(AudioServer.get_bus_index(bus_name) >= 0, "%s bus exists" % bus_name)
	audio.apply_settings()
	assert_true(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "master volume")
	assert_true(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.25)) < 0.01, "effects volume")
	p.audio_muted = true
	audio.apply_settings()
	assert_true(AudioServer.is_bus_mute(0), "mute")
	p.audio_muted = false
	p.audio_master = 80
	audio.apply_settings()


func test_every_request_is_recorded_even_when_nothing_can_be_heard() -> void:
	var p := FcPreferences.new(PREFS)
	audio = FcAudio.new(p)   # not in the tree (the unit runner has no running scene), so nothing is started
	assert_true(not audio.play("ui_click"))
	p.audio_muted = true
	assert_true(not audio.play("ui_click"), "muted")
	assert_eq(audio.requested, ["ui_click", "ui_click"])
	assert_eq(audio.bus_percent("UI"), 80)
	assert_eq(audio.bus_percent("Nowhere"), 100)


func test_cue_does_nothing_when_no_audio_is_running() -> void:
	FcAudio.current = null
	FcAudio.cue("ui_click")   # must not error
	assert_true(true)


# --- the app ----------------------------------------------------------------------------------------------------------------------------------

func test_toasts_and_flips_ask_for_their_sounds() -> void:
	_app()
	assert_true(FcAudio.current == app.audio, "the running audio is the one the app owns")
	app.notifier.error("Could not do that")
	assert_eq(app.audio.requested.back(), "toast_error")
	app.notifier.success("Saved")
	assert_eq(app.audio.requested.back(), "toast_success")
	var face := FcCardFace.new()
	face.flip_to(true, 0.0)
	assert_eq(app.audio.requested.back(), "card_flip")
	face.free()


func test_the_settings_screen_has_a_sound_panel_that_saves() -> void:
	_app()
	app.show_settings()
	var sliders: Array = []
	var stack: Array = [app._root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is FcSlider:
			sliders.append(n)
		stack.append_array(n.get_children())
	assert_eq(sliders.size(), 4, "master, interface, effects and music")
	for slider in sliders:
		(slider as FcSlider).value_changed.emit(40.0)
	var saved := FcPreferences.new(PREFS)
	assert_eq([app.preferences.audio_master, app.preferences.audio_ui, app.preferences.audio_sfx, app.preferences.audio_music], [40, 40, 40, 40], "each slider sets its own volume")
	assert_eq([saved.audio_master, saved.audio_ui, saved.audio_sfx, saved.audio_music], [40, 40, 40, 40], "saved at once")
