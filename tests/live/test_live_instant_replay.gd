extends FcLiveTestCase
## Slow motion, ball trails and the instant replay in the real replay screen (master plan B2b option C): quarter and half speed really are
## slower, the instant replay shows the possession that led to the current event at half speed with a REPLAY badge and then returns to
## EXACTLY where the live replay was (position, speed, playing or paused), whatever the feed filter is; the ball trail is capped and forgets
## on a jump; runs and milestones get the gold edge; no game data changes.

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


func _screen() -> FcReplayScreen:
	host.size = Vector2(1100, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1100, 880)
	host.add_child(screen)
	return screen


func _nth_made(screen: FcReplayScreen, n: int) -> int:
	var seen := 0
	for e in screen.model.entries:
		if e["type"] == FcGameEventLog.EV_SHOT_MADE:
			seen += 1
			if seen == n:
				return e["index"]
	return -1


func _state(screen: FcReplayScreen) -> Array:
	return [screen.current_index(), screen.bug.summary(), screen.caption.text, screen.speed, screen.is_playing(), screen.play_button.text]


func test_quarter_and_half_speed_are_really_slower() -> void:
	var screen := await _screen()
	await frames(2)
	var ids: Array = screen.speed_group.get_children().map(func(c: Node) -> String: return (c as Button).text)
	for label in ["0.25x", "0.5x", "1x", "2x", "4x"]:
		assert_true(ids.has(label), "%s is offered" % label)
	screen.seek(screen.model.start_index(), false)
	var dwell := screen.model.dwell(screen.current_index())
	for rate in [1.0, 0.5, 0.25]:
		screen.seek(screen.model.start_index(), false)
		screen.set_speed(rate)
		assert_eq(screen.speed, rate)
		screen.toggle_play()
		var before := screen.current_index()
		screen.advance(dwell / rate * 0.9)
		assert_eq(screen.current_index(), before, "at %sx the next event is not shown early" % rate)
		screen.advance(dwell / rate * 0.2)
		assert_true(screen.current_index() != before, "at %sx it is shown once the slower time has passed" % rate)
		screen.toggle_play()
	screen.set_speed(0.01)
	assert_eq(screen.speed, 0.25, "never slower than a quarter")


func test_the_instant_replay_shows_the_play_and_returns_to_exactly_where_it_was() -> void:
	var screen := await _screen()
	await frames(2)
	var live := _nth_made(screen, 6)
	screen.seek(live, false)
	screen.set_speed(2.0)
	var before := _state(screen)
	var window := screen.timeline.replay_window(live)
	screen.start_instant_replay()
	assert_true(screen.is_instant_replay() and screen.replay_badge.visible, "the REPLAY badge is up")
	assert_eq(screen.current_index(), int(window["start"]), "it starts at the beginning of the possession")
	assert_eq(screen.speed, FcReplayScreen.INSTANT_REPLAY_SPEED, "at half speed")
	assert_eq(screen.replay_button.text, "Back to the game")
	var visited: Array[int] = [screen.current_index()]
	for i in 200:
		screen.advance(30.0)
		if not screen.is_instant_replay():
			break
		if visited[visited.size() - 1] != screen.current_index():
			visited.append(screen.current_index())
	assert_true(not screen.is_instant_replay(), "it ended by itself")
	assert_eq(visited, range(int(window["start"]), int(window["end"]) + 1), "every event of the play, in order, none skipped")
	assert_eq(_state(screen), before, "and the live replay is exactly as it was: position, scoreboard, caption, speed and paused")
	assert_true(not screen.replay_badge.visible)
	assert_eq(screen.replay_button.text, "Instant replay")


func test_a_replay_started_while_playing_resumes_playing_and_the_button_ends_it_early() -> void:
	var screen := await _screen()
	await frames(2)
	var live := _nth_made(screen, 4)
	screen.seek(live, false)
	screen.toggle_play()
	assert_true(screen.is_playing())
	screen.start_instant_replay()
	assert_true(screen.is_instant_replay())
	screen.toggle_instant_replay()   # the button again: back to the game at once
	assert_true(not screen.is_instant_replay())
	assert_eq(screen.current_index(), live)
	assert_true(screen.is_playing(), "it was playing, so it plays again")
	assert_eq(screen.speed, 1.0)
	screen.start_instant_replay()
	screen.start_instant_replay()   # a second press while one is running does nothing extra
	assert_true(screen.is_instant_replay())
	screen.end_instant_replay()
	screen.end_instant_replay()   # and ending twice is harmless
	assert_eq(screen.current_index(), live)


func test_an_instant_replay_shows_every_event_even_when_the_feed_is_filtered() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_filter(FcReplayModel.FILTER_SCORING)
	var live := _nth_made(screen, 8)
	screen.seek(live, false)
	var window := screen.timeline.replay_window(live)
	screen.start_instant_replay()
	var visited: Array[int] = [screen.current_index()]
	for i in 200:
		screen.advance(30.0)
		if not screen.is_instant_replay():
			break
		if visited[visited.size() - 1] != screen.current_index():
			visited.append(screen.current_index())
	assert_eq(visited, range(int(window["start"]), int(window["end"]) + 1), "the filter does not hide the play")
	assert_eq(screen.filter, FcReplayModel.FILTER_SCORING, "and the filter is kept")
	assert_eq(screen.current_index(), live)


func test_an_instant_replay_changes_no_game_data() -> void:
	var rows_before := FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows)
	var box_before := FcOnlineCrypto.canonical((game["box"] as FcBoxScore).to_dict())
	var screen := await _screen()
	await frames(2)
	for n in [2, 5, 9]:
		screen.seek(_nth_made(screen, n), false)
		screen.start_instant_replay()
		for i in 100:
			screen.advance(30.0)
	assert_eq(FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows), rows_before)
	assert_eq(FcOnlineCrypto.canonical((game["box"] as FcBoxScore).to_dict()), box_before)


func test_the_ball_trail_is_capped_forgets_on_a_jump_and_can_be_switched_off() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index(), false)
	assert_eq(screen.court.trail_points().size(), 1, "a jump starts a fresh trail")
	for i in 40:
		screen.step(1)
	var trail := screen.court.trail_points()
	assert_true(trail.size() >= 2 and trail.size() <= FcCourtView.TRAIL_MAX, "a trail of the recent play, never more than %d points (%d)" % [FcCourtView.TRAIL_MAX, trail.size()])
	for p in trail:
		assert_true(FcCourtLayout.inside_court(p), "every trail point is on the court")
	screen.court.queue_redraw()
	await frames(2)
	screen.seek(_nth_made(screen, 10), false)
	assert_eq(screen.court.trail_points().size(), 1, "a scrub forgets it")
	screen.toggle_trail()
	assert_true(not screen.court.show_trail and screen.trail_toggle.text == "Ball trail: off")
	screen.set_view("flat")
	screen.court.queue_redraw()
	await frames(2)
	screen.toggle_trail()
	assert_true(screen.court.show_trail)


func test_runs_and_milestones_get_the_gold_edge() -> void:
	var screen := await _screen()
	await frames(2)
	var gold_seen := false
	var normal_seen := false
	for i in range(0, screen.model.size(), 1):
		var item := FcBroadcastGraphics.top_item_at(screen.timeline, i)
		if item.is_empty():
			continue
		screen.seek(i, false)
		var edge := screen.overlay.find_children("*", "ColorRect", true, false)[0] as ColorRect
		var emphasised := [FcBroadcastGraphics.MILESTONE, FcBroadcastGraphics.RUN, FcBroadcastGraphics.FINAL, FcBroadcastGraphics.CLUTCH].has(str(item["kind"]))
		assert_eq(edge.color == FcUiTokens.GOLD, emphasised, "event %d (%s)" % [i, item["kind"]])
		gold_seen = gold_seen or emphasised
		normal_seen = normal_seen or not emphasised
	assert_true(gold_seen and normal_seen)


func test_highlight_buttons_jump_pause_and_stop_at_the_ends() -> void:
	var screen := await _screen()
	await frames(2)
	assert_true(screen.highlights.size() >= 1, "the game has highlights")
	screen.seek(screen.model.start_index(), false)
	screen.toggle_play()
	assert_true(screen.is_playing())
	screen.highlight_next.pressed.emit()
	assert_eq(screen.current_index(), int(screen.highlights[0]["index"]), "jumped to the first highlight")
	assert_true(not screen.is_playing(), "paused there")
	var seen: Array = [screen.current_index()]
	for k in screen.highlights.size() + 2:
		screen.highlight_next.pressed.emit()
		if screen.current_index() != seen[seen.size() - 1]:
			seen.append(screen.current_index())
	assert_eq(seen.size(), screen.highlights.size(), "every highlight visited once, then it stops at the end")
	screen.highlight_prev.pressed.emit()
	assert_eq(screen.current_index(), int(screen.highlights[screen.highlights.size() - 2]["index"]) if screen.highlights.size() > 1 else seen[0], "and back")
