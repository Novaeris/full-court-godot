extends FcLiveTestCase
## Replay v2 in a real scene (Broadcast pass 2, M4): the tools belong to the Replay mode, the marks on the timeline match the collections,
## bookmarks toggle, navigate and are remembered in the person's own file, the highlight reel plays every highlight window in order and then
## puts everything back exactly, the angle picker steers the replay camera, and the keys work. Everything says "reconstructed".

const PATH := "user://test_live_replay_tools_bookmarks.json"

var game: Dictionary = {}


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PATH)
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


func after_each() -> void:
	DirAccess.remove_absolute(PATH)
	super.after_each()


func _screen() -> FcReplayScreen:
	host.size = Vector2(1400, 1000)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1400, 1000)
	host.add_child(screen)
	return screen


func test_the_tools_belong_to_the_replay_mode_and_say_reconstructed() -> void:
	var screen := await _screen()
	await frames(2)
	assert_eq(screen.mode, "replay")
	assert_true(screen.tools.visible and screen.marks.visible)
	assert_true(screen.tools.wording.text.contains("reconstructed") and screen.tools.wording.text.contains("not video"))
	screen.set_mode("broadcast")
	assert_true(not screen.tools.visible, "the broadcast mode shows no review tools")
	screen.set_mode("analysis")
	assert_true(not screen.tools.visible and screen.marks.visible, "analysis shows the timeline marks but not the replay tools")
	screen.seek(screen.model.start_index() + 30, false)
	assert_true(screen.tools.time_label.text.begins_with("Replay time "), screen.tools.time_label.text)


func test_the_marks_match_the_collections() -> void:
	var screen := await _screen()
	await frames(2)
	var counts: Dictionary = screen.marks.mark_counts()
	assert_eq(counts["highlight"], screen.package["refs"].size())
	assert_eq(counts["key"], FcReplayCollections.key_plays(screen.timeline).size())
	assert_eq(counts["bookmark"], 0)
	assert_true(screen.tools.reel_note.text.begins_with("Reel: "), screen.tools.reel_note.text)
	assert_true(screen.tools.prev_mark.disabled and screen.tools.next_mark.disabled, "no bookmarks, nothing to jump to")


func test_bookmarks_toggle_navigate_and_are_remembered() -> void:
	var screen := await _screen()
	screen.set_bookmark_store(FcBookmarkStore.new(PATH))
	await frames(2)
	var a := screen.model.start_index() + 30
	var b := screen.model.start_index() + 90
	screen.seek(a, false)
	screen.toggle_bookmark()
	assert_eq(screen.tools.bookmark_button.text, "Remove bookmark")
	screen.seek(b, false)
	screen.toggle_bookmark()
	assert_eq(screen.marks.mark_counts()["bookmark"], 2)
	assert_true(not screen.tools.next_mark.disabled)
	screen.seek(screen.model.start_index(), false)
	screen.jump_mark(1)
	assert_eq(screen.current_index(), a, "next mark")
	screen.jump_mark(1)
	assert_eq(screen.current_index(), b)
	screen.jump_mark(1)
	assert_eq(screen.current_index(), b, "no mark after the last")
	screen.jump_mark(-1)
	assert_eq(screen.current_index(), a, "previous mark")
	assert_eq(FcBookmarkStore.new(PATH).indices(screen.model.game_key()), [a, b], "remembered in the file")
	screen.toggle_bookmark()
	assert_eq(screen.tools.bookmark_button.text, "Bookmark this play")
	assert_eq(screen.marks.mark_counts()["bookmark"], 1)


func test_a_default_screen_never_touches_the_players_bookmark_file() -> void:
	var screen := await _screen()
	await frames(1)
	assert_eq(screen.bookmarks.path, "", "tests and previews keep bookmarks in memory only")


func test_the_highlight_reel_plays_every_window_in_order_and_puts_everything_back() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 25, false)
	screen.set_speed(2.0)
	var before := screen.state.snapshot()
	var windows: Array = screen.package["refs"]
	assert_true(windows.size() >= 3)
	var seen: Array = []
	screen.event_shown.connect(func(i: int) -> void: seen.append(i))
	screen.start_reel()
	assert_true(screen.is_reel() and screen.is_playing())
	assert_eq(screen.replay_badge.text, FcReplayReference.REEL_BADGE_TEXT)
	assert_eq(screen.speed, 1.0, "the reel plays at normal speed")
	assert_eq(screen.tools.reel_button.text, "Stop reel")
	assert_eq(screen.court.rig.switch_log().back()["preset"], FcCameraDirector.PRESET_REPLAY)
	var guard := 0
	while screen.is_reel() and guard < 4000:
		screen.advance(2.0)
		guard += 1
	assert_true(not screen.is_reel(), "the reel ends by itself")
	for k in windows.size():
		var start := int(windows[k]["start"])
		assert_true(seen.has(start), "window %d starts at event %d" % [k, start])
		for i in range(int(windows[k]["start"]), int(windows[k]["end"]) + 1):
			assert_true(seen.has(i), "event %d of window %d was shown" % [i, k])
	assert_eq(screen.state.snapshot().slice(0, 3), before.slice(0, 3), "position, play state and speed are back exactly")
	assert_true(not screen.replay_badge.visible)
	assert_eq(screen.tools.reel_button.text, "Highlight reel")


func test_the_reel_can_be_stopped_and_excludes_an_instant_replay() -> void:
	var screen := await _screen()
	await frames(2)
	var at := screen.model.start_index() + 40
	screen.seek(at, false)
	screen.start_instant_replay()
	screen.start_reel()
	assert_true(screen.is_reel() and not screen.is_instant_replay(), "starting the reel ends the instant replay")
	screen.toggle_reel()
	assert_true(not screen.is_reel())
	assert_eq(screen.current_index(), at, "stopping the reel returns to where the replay was")


func test_the_angle_picker_steers_the_replay_camera() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 60, false)
	screen.start_instant_replay()
	for pair in [["1", "baseline"], ["2", "overhead"], ["0", "main"]]:
		screen.set_replay_angle(pair[0])
		assert_eq(screen.court.rig.pose_angle()["angle"], pair[1], "angle %s" % pair[0])
	screen.set_replay_angle("auto")
	assert_eq(screen.state.replay_angle, -1)
	screen.end_instant_replay()


func test_the_keys_bookmark_replay_step_speeds_and_jump_highlights() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_speed(1.0)
	screen._nudge_speed(1)
	assert_eq(screen.speed, 2.0)
	screen._nudge_speed(1)
	screen._nudge_speed(1)
	assert_eq(screen.speed, 4.0, "stops at the last speed")
	screen._nudge_speed(-1)
	assert_eq(screen.speed, 2.0)
	screen.set_speed(0.5)
	assert_eq(screen.speed, 0.5)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_B
	screen.seek(screen.model.start_index() + 20, false)
	screen._unhandled_input(key)
	assert_true(screen.bookmarks.has_bookmark(screen.model.game_key(), screen.current_index()), "B bookmarks the play")
	key.keycode = KEY_R
	screen._unhandled_input(key)
	assert_true(screen.is_instant_replay(), "R starts an instant replay")
	screen.end_instant_replay()
	var first := int(screen.highlights[0]["index"])
	screen.seek(screen.model.start_index(), false)
	key.keycode = KEY_PERIOD
	screen._unhandled_input(key)
	assert_eq(screen.current_index(), first, "the period key jumps to the next highlight")
