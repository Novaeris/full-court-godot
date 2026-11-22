extends FcLiveTestCase
## The replay screen in a real scene (Phase 2C): it draws, plays and pauses, steps, filters, jumps by period, scrubs, follows clicks in the
## feed, honours reduced motion, fits a phone, and is reachable from the post-game dialog of an Owner game. Playback is driven with
## advance(delta) so the tests do not depend on real time. (Runtime script errors fail the test through the live runner's logger.)

const PREFS := "user://test_preferences_live_replay.cfg"

var world: FcWorld
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
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ratings := FcPlayerRatings.load_default()
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(12))
	game = {"box": box, "log": sim.recorder}


func _screen(width: float = 1100.0, phone: bool = false) -> FcReplayScreen:
	host.size = Vector2(width, 800)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], phone)
	screen.size = Vector2(width, 780)
	host.add_child(screen)
	return screen


func test_it_opens_on_the_tip_off_and_draws() -> void:
	var screen := await _screen()
	await frames(3)
	assert_eq(screen.current_index(), screen.model.start_index())
	assert_true(screen.bug.summary().contains("Q1 12:00"), "the scoreboard starts the first quarter: %s" % screen.bug.summary())
	assert_true(screen.caption.text.contains("Tip-off"))
	assert_true(screen.feed.item_count > 100, "the feed lists the plays")
	assert_true(not screen.is_playing())
	screen.court.queue_redraw()
	await frames(2)


func test_play_pause_and_the_end() -> void:
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	assert_true(screen.is_playing() and screen.play_button.text == "Pause")
	var start := screen.current_index()
	for i in 12:
		screen.advance(1.0)
	assert_true(screen.current_index() > start + 3, "playing moves through the game")
	screen.toggle_play()
	assert_true(not screen.is_playing() and screen.play_button.text == "Play")
	var held := screen.current_index()
	screen.advance(5.0)
	assert_eq(screen.current_index(), held, "a paused replay does not move")
	screen.set_speed(8.0)
	screen.toggle_play()
	var guard := 0
	while screen.is_playing() and guard < 5000:
		screen.advance(2.0)
		guard += 1
	assert_eq(screen.current_index(), screen.model.final_index(), "it plays to the final")
	assert_true(not screen.is_playing(), "and pauses there")
	assert_true(screen.bug.summary().contains("FINAL"))
	assert_eq(screen.bug.summary().split(" ")[1], str(game["box"].scores[0]), "the final score is the box score")
	screen.toggle_play()
	assert_eq(screen.current_index(), screen.model.start_index(), "pressing Play at the end starts over")
	screen.toggle_play()


func test_speed_changes_how_fast_it_plays() -> void:
	var slow := await _screen()
	slow.toggle_play()
	for i in 10:
		slow.advance(1.0)
	var slow_at := slow.current_index()
	var fast := await _screen()
	fast.set_speed(4.0)
	fast.toggle_play()
	for i in 10:
		fast.advance(1.0)
	assert_true(fast.current_index() > slow_at, "4x gets further than 1x in the same time")


func test_stepping_filters_period_jumps_and_the_scrubber() -> void:
	var screen := await _screen()
	await frames(2)
	var first := screen.current_index()
	screen.step(1)
	assert_true(screen.current_index() > first)
	screen.step(-1)
	assert_eq(screen.current_index(), first)
	var all_count := screen.feed.item_count
	screen.set_filter(FcReplayModel.FILTER_SCORING)
	assert_true(screen.feed.item_count < all_count and screen.feed.item_count > 10, "the scoring filter shortens the feed")
	screen.step(1)
	var e: Dictionary = screen.model.entries[screen.current_index()]
	assert_true(e["points"] > 0 or e["type"] == FcGameEventLog.EV_GAME_END, "stepping in the scoring filter lands on a score")
	screen.set_filter(FcReplayModel.FILTER_ALL)
	screen.period_group.button_for("3").pressed.emit()
	assert_eq(screen.model.entries[screen.current_index()]["period"], 3, "the Q3 button jumps to the third quarter")
	assert_true(screen.bug.summary().contains("Q3"))
	screen.scrubber.value = screen.model.size() - 1
	assert_eq(screen.current_index(), screen.model.size() - 1, "dragging the scrubber to the end shows the last event")
	await frames(1)


func test_clicking_the_feed_jumps_there_and_the_score_matches_the_play() -> void:
	var screen := await _screen()
	await frames(2)
	var item := floori(screen.feed.item_count / 2.0)
	screen.feed.item_selected.emit(item)
	var shown := screen.current_index()
	var st := screen.model.state_at(shown)
	assert_true(screen.bug.summary().contains(" %d " % st["home"]) or screen.bug.summary().contains(" %d" % st["away"]))
	assert_true(screen.caption.text.contains(st["text"]), "the caption is the play's sentence")
	assert_eq(screen.feed.get_selected_items().size(), 1, "the feed highlights where we are")


func test_players_listed_on_court_match_the_model() -> void:
	var screen := await _screen()
	screen.seek(floori(screen.model.size() / 2.0), false)
	var st := screen.model.state_at(screen.current_index())
	for side in 2:
		var names: Array = []
		for l in screen._roster_labels[side]:
			if (l as Label).text != "":
				names.append((l as Label).text)
		assert_eq(names.size(), 5, "five players listed for side %d" % side)
		assert_eq((st["on_court"][side] as Array).size(), 5)


func test_reduced_motion_shows_each_event_at_once() -> void:
	FcMotion.reduced = true
	var screen := await _screen()
	await frames(2)
	screen.step(1)
	assert_eq(screen.court.progress, 1.0, "no gliding when motion is reduced")
	FcMotion.reduced = false
	screen.step(1)
	await frames(2)
	assert_true(screen.court.progress >= 0.0)


func test_a_phone_sized_layout_fits() -> void:
	var screen := await _screen(412.0, true)
	await frames(3)
	assert_true(screen.get_combined_minimum_size().x <= 412.0, "the replay needs %d px of 412" % int(screen.get_combined_minimum_size().x))


func test_an_empty_replay_says_so() -> void:
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(null, FcBoxScore.new()))
	host.add_child(screen)
	await frames(2)
	assert_true(screen.get_child_count() == 1 and (screen.get_child(0) as Label).text.contains("No replay"), "an old game with no events explains itself")
	screen.toggle_play()
	screen.advance(1.0)


func test_the_space_and_arrow_keys_control_playback() -> void:
	var screen := await _screen()
	await frames(2)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	screen._unhandled_input(key)
	assert_true(screen.is_playing(), "space plays")
	screen._unhandled_input(key)
	assert_true(not screen.is_playing(), "space pauses")
	var at := screen.current_index()
	var right := InputEventKey.new()
	right.pressed = true
	right.keycode = KEY_RIGHT
	screen._unhandled_input(right)
	assert_true(screen.current_index() > at, "the right arrow steps forward")


# --- reaching it from the game ---------------------------------------------------------------------------------------------

func test_an_owner_post_game_dialog_offers_the_replay_and_it_opens() -> void:
	DirAccess.remove_absolute(PREFS)
	var app := FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_replay")
	host.add_child(app)
	app.setup()
	await frames(2)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Replay Owner"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	app.controller.advance_days(12)
	var entry: Dictionary = app.controller.season().recent_boxes[0]
	var built := FcPostGame.for_owner(app.controller, entry["box"], entry["events"])
	assert_true(not (built["replay"] as Dictionary).is_empty(), "the stored game has a replay")
	FcPostGame.open(app, built)
	await frames(2)
	var button := _find_button(app, "Watch replay")
	assert_true(button != null, "the post-game dialog has a Watch replay button")
	button.pressed.emit()
	await frames(3)
	var replay := app.find_child("ReplayScreen", true, false) as FcReplayScreen
	assert_true(replay != null, "the replay opened")
	assert_eq(replay.model.box.scores[0], int(entry["box"]["scores"][0]), "it is this game")
	var without := FcPostGame.for_owner(app.controller, entry["box"], {})
	assert_true((without["replay"] as Dictionary).is_empty(), "no events, no replay button")
	app.queue_free()
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree("user://test_saves_live_replay")


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null
