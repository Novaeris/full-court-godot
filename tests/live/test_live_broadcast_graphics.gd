extends FcLiveTestCase
## The broadcast graphics in the real replay screen (master plan B2b option A): the scorebug's second line (possession, team fouls, bonus)
## and the graphic strip over the court follow the game, say what the timeline says, never take the mouse, respect reduced motion, fit a
## phone, and playing the replay changes no game data.

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


func after_each() -> void:
	FcMotion.reduced = false
	super.after_each()


func _screen(width: float = 1100.0, phone: bool = false) -> FcReplayScreen:
	host.size = Vector2(width, 800)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], phone)
	screen.size = Vector2(width, 780)
	host.add_child(screen)
	return screen


func _detail(screen: FcReplayScreen) -> Label:
	return screen.bug.find_child("BroadcastDetail", true, false) as Label


func test_the_scorebug_second_line_follows_possession_fouls_and_the_bonus() -> void:
	var screen := await _screen()
	await frames(2)
	var abbr: Array = screen.model.box.abbreviations
	var sample := [screen.model.start_index(), screen.model.period_start_index(2), screen.model.period_start_index(3), screen.model.final_index()]
	for i in range(0, screen.model.size(), 37):
		sample.append(i)
	var saw_bonus := false
	for i in sample:
		screen.seek(i, false)
		var snap := screen.timeline.snapshot(i)
		var text := _detail(screen).text
		assert_true(_detail(screen).visible, "the second line is shown")
		for side in 2:
			assert_true(text.contains("%s  fouls %d" % [abbr[side], int(snap["team_fouls"][side])]), "event %d team %d fouls in: %s" % [i, side, text])
			assert_eq(text.contains("%s  fouls %d  in the bonus" % [abbr[side], int(snap["team_fouls"][side])]), bool(snap["bonus_for"][side]), "the bonus tag at event %d" % i)
		assert_eq(text.count("●"), 1, "exactly one team has the ball")
		saw_bonus = saw_bonus or text.contains("in the bonus")
	assert_true(saw_bonus, "the bonus showed at least once in the sample")
	assert_true(screen.bug.summary().contains(str(abbr[0])), "the scoreboard's own text is unchanged")


func test_the_graphic_strip_shows_the_top_item_for_every_event_and_never_takes_the_mouse() -> void:
	var screen := await _screen()
	await frames(2)
	assert_eq(screen.overlay.get_parent(), screen.court, "it sits over the court")
	assert_eq(screen.overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var shown := 0
	for i in range(0, screen.model.size(), 11):
		screen.seek(i, false)
		var item := FcBroadcastGraphics.top_item_at(screen.timeline, i)
		if item.is_empty():
			assert_true(not screen.overlay.visible, "nothing to say at event %d" % i)
		else:
			assert_true(screen.overlay.visible)
			assert_true(screen.overlay.summary().begins_with(str(item["title"])), "event %d: %s" % [i, screen.overlay.summary()])
			shown += 1
	assert_true(shown > 10, "the strip showed on many events (%d)" % shown)
	for control in screen.overlay.find_children("*", "Control", true, false):
		assert_eq((control as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % control.name)


func test_the_final_event_shows_the_final_panel_with_the_box_score() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.final_index(), false)
	var box: FcBoxScore = game["box"]
	assert_true(screen.overlay.summary().begins_with("Final"), screen.overlay.summary())
	assert_true(screen.overlay.summary().contains("%d" % box.scores[0]) and screen.overlay.summary().contains("%d" % box.scores[1]))


func test_with_reduced_motion_the_strip_simply_appears() -> void:
	FcMotion.reduced = true
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.final_index(), false)
	await seconds(FcUiTokens.DUR_REDUCED_FADE * 3.0)   # reduced motion still allows one very short fade (FcMotion.duration)
	assert_true(screen.overlay.visible and is_equal_approx(screen.overlay.modulate.a, 1.0), "fully visible right after the short fade")


func test_the_strip_stays_inside_the_court_on_a_phone() -> void:
	var screen := await _screen(360.0, true)
	await frames(3)
	screen.seek(screen.model.final_index(), false)
	await frames(3)
	var court_rect := screen.court.get_global_rect()
	var strip := screen.overlay.get_global_rect()
	assert_true(strip.position.x >= court_rect.position.x - 1.0 and strip.end.x <= court_rect.end.x + 1.0, "inside the court sideways: strip %s court %s" % [str(strip), str(court_rect)])
	assert_true(screen.get_combined_minimum_size().x <= 360.0, "the replay screen still fits a 360 px phone (%d)" % int(screen.get_combined_minimum_size().x))


func test_playing_the_replay_with_graphics_changes_no_game_data() -> void:
	var box: FcBoxScore = game["box"]
	var rows_before := FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows)
	var box_before := FcOnlineCrypto.canonical(box.to_dict())
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	for i in 60:
		screen.advance(1.0)
	screen.seek(screen.model.final_index(), true)
	assert_eq(FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows), rows_before, "the event rows are unchanged")
	assert_eq(FcOnlineCrypto.canonical(box.to_dict()), box_before, "the box score is unchanged")


func test_the_team_comparison_card_shows_the_box_score_at_the_end_and_grows_with_the_game() -> void:
	var screen := await _screen()
	await frames(2)
	var box: FcBoxScore = game["box"]
	screen.seek(screen.model.final_index(), false)
	await frames(2)
	var labels: Array = screen.team_card.get_children().map(func(c: Node) -> String: return (c as Label).text)
	assert_eq(labels.size(), 3 * 9, "a header row and eight stat rows of three cells")
	assert_eq(labels[1], box.abbreviations[0])
	var totals := box.team_totals(0)
	assert_eq(labels[3 + 1], "%d-%d" % [totals["fgm"], totals["fga"]], "home field goals")
	assert_eq(labels[3 * 4 + 1], str(int(totals["oreb"]) + int(totals["dreb"])), "home rebounds")
	screen.seek(screen.model.start_index(), false)
	await frames(2)
	var early: Array = screen.team_card.get_children().map(func(c: Node) -> String: return (c as Label).text)
	assert_eq(early[3 + 1], "0-0", "no shots at the tip-off")
	assert_eq(early.size(), 3 * 9)
