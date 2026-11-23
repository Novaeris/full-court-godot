extends FcLiveTestCase
## Arena presentation in a real scene (Broadcast pass 2, M5): the one arena is dressed for the home team (LED boards, benches, lights, a
## shader-driven crowd), the crowd reacts to cheers, groans and gasps and calms down again, the LED messages rotate, the screen reacts to the
## audio cues, and the player introductions play and put the replay back exactly.

var game: Dictionary = {}


func before_each() -> void:
	super.before_each()
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	var world := FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ratings := FcPlayerRatings.load_default()
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(12))
	game = {"box": box, "log": sim.recorder}


func _scene() -> FcCourtScene:
	var scene := FcCourtScene.new()
	host.add_child(scene)
	scene.build(Color("3B2F8F"), Color("8B1E2D"), "HOU", FcArenaIdentity.make({"home": {"abbr": "HOU", "name": "Houston Sentinels", "color": Color("3B2F8F")}, "away": {"abbr": "MEX", "name": "Mexico City Bonfires", "color": Color("8B1E2D")}}))
	return scene


func _screen() -> FcReplayScreen:
	host.size = Vector2(1400, 1000)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1400, 1000)
	host.add_child(screen)
	return screen


func test_the_arena_is_dressed_for_the_home_team() -> void:
	var scene := _scene()
	assert_eq(scene.led_label_count(), 16, "5 + 5 + 3 + 3 messages around the court")
	assert_eq(scene.bench_figure_count(), 12, "six players on each bench")
	assert_eq(scene.light_count(), 5, "the key light and four soft spotlights")
	assert_true(scene.instance_count() > 3000, "the crowd is there")
	assert_true(scene.crowd_animated(), "the crowd runs on the animated shader")
	assert_eq(scene.led_text(), "HOU")
	assert_eq(scene.identity["home_nickname"], "SENTINELS")


func test_a_scene_without_an_identity_is_still_built() -> void:
	var scene := FcCourtScene.new()
	host.add_child(scene)
	scene.build(Color("2F6FED"), Color("F28A2E"), "ABC")
	assert_true(scene.instance_count() > 0 and scene.led_label_count() == 16)
	assert_eq(scene.identity["home_abbr"], "ABC")


func test_the_crowd_reacts_and_calms_down() -> void:
	var scene := _scene()
	assert_eq(scene.crowd_state(), {"cheer": 0.0, "groan": 0.0, "wave": -1.0})
	scene.react_crowd("groan")
	assert_eq(scene.crowd_state()["groan"], 1.0)
	scene.advance_crowd(0.5)
	assert_true(scene.crowd_state()["groan"] < 1.0 and scene.crowd_state()["groan"] > 0.0, "fading")
	scene.advance_crowd(3.0)
	assert_eq(scene.crowd_state()["groan"], 0.0, "calm again")
	scene.react_crowd("cheer")
	assert_eq(scene.crowd_state()["cheer"], 0.6)
	scene.react_crowd("cheer_big")
	assert_eq(scene.crowd_state()["cheer"], 1.0)
	assert_eq(scene.crowd_state()["wave"], 0.0, "a big cheer starts the wave")
	scene.advance_crowd(1.0)
	assert_true(scene.crowd_state()["wave"] > 0.2, "the wave travels")
	for i in 8:
		scene.advance_crowd(1.0)
	assert_eq(scene.crowd_state()["wave"], -1.0, "and ends")
	assert_eq(scene.crowd_state()["cheer"], 0.0)
	scene.react_crowd("oh")
	assert_true(scene.crowd_state()["cheer"] > 0.0 and scene.crowd_state()["groan"] > 0.0, "a gasp is a little of both")
	scene.react_crowd("not a reaction")
	await frames(2)


func test_the_led_messages_rotate() -> void:
	var scene := _scene()
	var messages: Array = scene.identity["led_messages"]
	assert_true(messages.size() >= 3)
	var seen: Array = [scene.led_text()]
	for k in messages.size():
		scene.advance_led(float(scene.identity["led_seconds"]) + 0.01)
		seen.append(scene.led_text())
	assert_true(seen.has("FULL COURT BASKETBALL") and seen.has("SENTINELS"), "every message gets its turn: %s" % str(seen))
	assert_eq(scene.led_index(), 0, "and it wraps")
	scene.advance_led(1.0)
	assert_eq(scene.led_index(), 0, "not before its time")


func test_standing_a_section_still_works_with_sized_fans() -> void:
	var scene := _scene()
	assert_eq(scene.standing_section(), -1)
	scene.stand_section(2)
	assert_eq(scene.standing_section(), 2)
	scene.stand_section(3)
	assert_eq(scene.standing_section(), 3)


func test_the_view_passes_every_crowd_cue_to_the_scene() -> void:
	var screen := await _screen()
	await frames(3)
	if screen.court3d == null:
		return
	screen.set_mode("broadcast")
	var scene: FcCourtScene = screen.court3d.scene
	screen.court3d.react(["crowd_groan"])
	assert_true(scene.crowd_state()["groan"] > 0.0)
	screen.court3d.react(["crowd_oh"])
	screen.court3d.react(["crowd_cheer_small"])
	assert_true(scene.crowd_state()["cheer"] >= 0.6)
	screen.court3d.react(["crowd_cheer_big"])
	assert_eq(scene.crowd_state()["wave"], 0.0)
	screen.court3d.react(["ui_click"])


func test_the_introductions_play_and_put_the_replay_back_exactly() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 45, false)
	screen.set_speed(2.0)
	var before := screen.state.snapshot().slice(0, 3)
	var steps := FcPlayerIntroductions.plan(screen.timeline)
	assert_eq(steps.size(), 10)
	screen.start_introductions()
	assert_true(screen.is_intro() and not screen.is_playing())
	assert_eq(screen.current_index(), screen.model.start_index(), "the introductions happen at the tip-off")
	assert_true(screen.spotlight.visible and screen.spotlight.summary().contains(str(steps[0]["name"])), "the first starter: %s" % screen.spotlight.summary())
	assert_eq(screen.court.rig.switch_log().back()["preset"], FcCameraDirector.PRESET_CLOSEUP)
	assert_eq(screen.tools.intro_button.text, "Skip introductions")
	var seen: Array = [str(steps[0]["name"])]
	var guard := 0
	while screen.is_intro() and guard < 100:
		screen.advance(FcPlayerIntroductions.SECONDS_PER_PLAYER + 0.01)
		guard += 1
		if screen.is_intro():
			assert_true(screen.spotlight.summary().contains(str(steps[int(screen.state.intro["at"])]["name"])), "each starter in turn")
			seen.append(str(steps[int(screen.state.intro["at"])]["name"]))
	assert_eq(seen.size(), 10, "all ten were introduced")
	assert_true(not screen.is_intro())
	assert_eq(screen.state.snapshot().slice(0, 3), before, "position, play state and speed are back exactly")
	assert_eq(screen.tools.intro_button.text, "Player introductions")


func test_play_skips_the_introductions() -> void:
	var screen := await _screen()
	await frames(2)
	var at := screen.model.start_index() + 10
	screen.seek(at, false)
	screen.start_introductions()
	screen.toggle_play()
	assert_true(not screen.is_intro() and not screen.is_playing(), "Play skips them without starting the replay")
	assert_eq(screen.current_index(), at)
