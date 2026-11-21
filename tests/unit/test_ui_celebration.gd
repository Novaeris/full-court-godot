extends FcTestCase
## Phase I (animation, audio, atmosphere): the new sounds exist and build, the achievement toast, the championship celebration (capped confetti,
## still under reduced motion), the back sound, the quick mute, and a build-time budget for every Owner tab.

const NEW_SOUNDS := ["transition", "level_up", "achievement", "championship"]


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false


func test_the_new_sounds_are_in_the_map_and_render_to_audible_samples() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/audio.json"))
	for id in NEW_SOUNDS:
		assert_true(parsed["sounds"].has(id), id + " is in the sound map")
		var samples := FcAudioSynth.render(parsed["sounds"][id]["synth"], id)
		assert_true(samples.size() > 1000, "%s has %d samples" % [id, samples.size()])
		var loudest := 0.0
		for v in samples:
			loudest = maxf(loudest, absf(v))
		assert_true(loudest > 0.05 and loudest <= 0.9, "%s is audible and does not clip (%f)" % [id, loudest])


func test_every_sound_in_the_map_still_renders() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/audio.json"))
	assert_true(parsed["sounds"].size() >= 21, "the 17 old sounds plus the 4 new ones")
	for id in parsed["sounds"]:
		assert_true(FcAudioSynth.render(parsed["sounds"][id]["synth"], id).size() > 0, id)


func test_an_achievement_toast_is_gold_with_a_trophy_and_is_recorded() -> void:
	assert_eq(FcToast.COLORS[FcToast.Kind.ACHIEVEMENT], FcUiTokens.GOLD)
	assert_eq(FcToast.ICONS[FcToast.Kind.ACHIEVEMENT], "trophy")
	var n := FcNotifier.new()
	n.achievement("Level up! You are now level 4.", "level_up")
	assert_eq(n.last()["kind"], FcToast.Kind.ACHIEVEMENT)
	assert_eq(n.last()["text"], "Level up! You are now level 4.")
	n.achievement("   ")
	assert_eq(n.history.size(), 1, "a blank message is ignored")
	var toast := FcToast.new(FcToast.Kind.ACHIEVEMENT, "Champions")
	toast.free()


func test_the_celebration_names_the_title_and_is_readable_as_text() -> void:
	var c := FcCelebration.new("Champions!", "Houston Sentinels")
	assert_eq(c.tooltip_text, "Champions!. Houston Sentinels")
	c.free()


func test_confetti_is_capped_and_smaller_on_touch_layouts() -> void:
	assert_eq(FcCelebration.piece_count(), FcCelebration.MAX_PIECES)
	FcUiTokens.touch_mode = true
	assert_eq(FcCelebration.piece_count(), FcCelebration.MAX_PIECES_TOUCH)
	assert_true(FcCelebration.MAX_PIECES <= 80, "the particle budget")


func test_reduced_motion_celebration_has_no_confetti_but_still_dismisses_once() -> void:
	FcMotion.reduced = true
	var host := Control.new()
	Engine.get_main_loop().root.add_child(host)
	host.size = Vector2(800, 600)
	var c := FcCelebration.show_on(host, "Champions!", "Team")
	assert_eq(c.confetti, null, "no particles when motion is reduced")
	var done: Array = []
	c.finished.connect(func() -> void: done.append(true))
	c.dismiss()
	c.dismiss()
	assert_eq(done.size(), 1)
	Engine.get_main_loop().root.remove_child(host)
	host.free()


func test_normal_motion_celebration_bursts_confetti_within_the_cap() -> void:
	var host := Control.new()
	Engine.get_main_loop().root.add_child(host)
	host.size = Vector2(800, 600)
	var c := FcCelebration.show_on(host, "Champions!")
	assert_true(c.confetti != null and c.confetti.amount <= FcCelebration.MAX_PIECES and c.confetti.one_shot, "one burst, capped")
	c.dismiss()
	Engine.get_main_loop().root.remove_child(host)
	host.free()


func test_going_back_plays_the_back_sound_and_the_menu_has_a_quick_mute() -> void:
	var app := FcApp.new()
	app.preferences = FcPreferences.new("user://test_prefs_celebration.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_celebration")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	var toggle := app._root.find_child("SoundToggle", true, false) as FcToggle
	assert_true(toggle != null, "the menu footer has a Sound switch")
	assert_true(toggle.button_pressed, "sound starts on")
	toggle.button_pressed = false
	assert_true(app.preferences.audio_muted, "switching it off mutes the game")
	assert_true(FcPreferences.new("user://test_prefs_celebration.cfg").audio_muted, "and the choice is remembered in the settings file")
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	DirAccess.remove_absolute("user://test_prefs_celebration.cfg")


func test_every_owner_tab_builds_within_the_time_budget() -> void:
	var app := FcApp.new()
	app.preferences = FcPreferences.new("user://test_prefs_perf.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_perf")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 12, "conferences": 2, "divisions": 1, "free_agents": 20, "seed": "3", "name": "Perf"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(20)
	var slowest := 0.0
	var slowest_name := ""
	for name in FcApp.TAB_NAMES:
		var t0 := Time.get_ticks_usec()
		var tab := app.build_tab(name)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > slowest:
			slowest = ms
			slowest_name = name
		assert_true(ms < 250.0, "%s tab built in %.0f ms (budget 250)" % [name, ms])
		tab.free()
	print("PERF owner tabs: slowest is %s at %.0f ms" % [slowest_name, slowest])
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	FcSafeFile.remove_tree("user://test_saves_perf")
	DirAccess.remove_absolute("user://test_prefs_perf.cfg")
