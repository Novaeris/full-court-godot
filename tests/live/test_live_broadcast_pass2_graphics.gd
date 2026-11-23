extends FcLiveTestCase
## Broadcast pass 2, M2 in a real scene: the scoreboard shows the estimated shot clock and hides it when it would mislead, the spotlight and
## lower third follow the event, Broadcast mode lets graphics leave by themselves while the review modes keep them, the stats overlay shows
## the same numbers as the team card, and a hidden HUD removes all of it.

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


func _screen(size: Vector2 = Vector2(1400, 900)) -> FcReplayScreen:
	host.size = size
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = size
	host.add_child(screen)
	return screen


func _first_index(screen: FcReplayScreen, want_spotlight: bool) -> int:
	for i in range(screen.model.start_index(), screen.model.size()):
		if want_spotlight == not FcSpotlightModel.at(screen.timeline, i).is_empty():
			return i
	return -1


func test_shot_clock_shows_on_the_scoreboard_and_hides_when_misleading() -> void:
	var screen := await _screen()
	await frames(2)
	var shown := -1
	var hidden := -1
	for i in range(screen.model.start_index(), screen.model.size()):
		var info := FcShotClockModel.at(screen.timeline, i)
		if bool(info["visible"]) and shown < 0:
			shown = i
		if not bool(info["visible"]) and hidden < 0 and i > screen.model.start_index():
			hidden = i
	assert_true(shown >= 0 and hidden >= 0)
	screen.seek(shown, false)
	assert_true(screen.bug.shot_clock_text().begins_with("SHOT CLOCK"), "shown: %s" % screen.bug.shot_clock_text())
	assert_eq(screen.bug.shot_clock_text(), "%s %d" % [FcShotClockModel.at(screen.timeline, shown)["label"], FcShotClockModel.at(screen.timeline, shown)["seconds"]])
	screen.seek(hidden, false)
	assert_true(not screen.bug.shot_clock_text().begins_with("SHOT CLOCK"), "hidden when it would mislead")
	var stop := -1
	for i in range(screen.model.start_index(), screen.model.size()):
		if bool(FcStoppageModel.at(screen.timeline, i)["active"]):
			stop = i
			break
	screen.seek(stop, false)
	assert_true(screen.bug.shot_clock_text().begins_with("PLAY STOPPED"), "a stoppage says why: %s" % screen.bug.shot_clock_text())


func test_the_scoreboard_shows_crests_when_it_is_given_teams() -> void:
	var screen := await _screen()
	assert_true(not screen.bug.has_crests(), "no teams given, no crests (Dynasty and tests)")
	var subjects: Array = [FcTeamLook.subject("team:1", "Houston Sentinels", "HOU", "#3B2F8F", "#FFB547"), FcTeamLook.subject("team:2", "Mexico City Bonfires", "MEX", "#8B1E2D", "#FFB547")]
	screen.bug.set_crests(subjects)
	await frames(2)
	assert_true(screen.bug.has_crests())
	assert_true(screen.bug.find_child("CrestHome", true, false) != null and screen.bug.find_child("CrestAway", true, false) != null)
	screen.bug.set_crests([])
	await frames(2)
	assert_true(not screen.bug.has_crests(), "empty subjects remove them")


func test_the_spotlight_follows_the_event() -> void:
	var screen := await _screen()
	await frames(2)
	var yes := _first_index(screen, true)
	var no := _first_index(screen, false)
	screen.seek(yes, false)
	assert_true(screen.spotlight.visible and screen.spotlight.summary().contains("PTS"), "spotlight: %s" % screen.spotlight.summary())
	assert_eq(screen.spotlight.current_model(), FcSpotlightModel.at(screen.timeline, yes))
	screen.seek(no, false)
	assert_true(not screen.spotlight.visible)


func test_broadcast_graphics_leave_by_themselves_but_review_modes_keep_them() -> void:
	var screen := await _screen()
	await frames(2)
	var idx := _first_index(screen, true)
	screen.set_mode("replay")
	assert_true(not screen.overlay.auto_hide and not screen.spotlight.auto_hide)
	screen.set_mode("broadcast")
	assert_true(screen.overlay.auto_hide and screen.spotlight.auto_hide)
	screen.seek(idx, false)
	assert_true(screen.overlay.visible and screen.spotlight.visible)
	var timing := FcBroadcastStyle.timing("spotlight", FcMotion.reduced)
	await seconds(timing["in"] + timing["hold"] + timing["out"] + 0.4)
	assert_true(not screen.spotlight.visible, "the spotlight left after its hold time")
	assert_true(not screen.overlay.visible, "the lower third left after its hold time")
	screen.set_mode("replay")
	screen.seek(idx, false)
	await frames(3)
	assert_true(screen.overlay.visible, "the review modes keep the lower third")


func test_stats_overlay_matches_the_team_card() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.size() - 1, false)
	assert_true(not screen.stats_overlay.visible)
	screen.toggle_stats()
	assert_true(screen.stats_overlay.visible)
	var card := FcBroadcastGraphics.team_card_at(screen.timeline, screen.current_index())
	var wanted := FcBroadcastStyle.stats_rows()
	var expected: Array = []
	for row in card["rows"]:
		if str(row[0]) in wanted:
			expected.append(row)
	assert_eq(screen.stats_overlay.rows(), expected, "the same numbers as the team comparison card")
	var box: FcBoxScore = screen.model.box
	assert_eq(str(screen.stats_overlay.rows()[0][1]), "%d-%d" % [box.team_totals(0)["fgm"], box.team_totals(0)["fga"]], "field goals equal the box score")
	screen.set_hud("hidden")
	assert_true(not screen.stats_overlay.visible and not screen.spotlight.visible, "a hidden HUD removes the overlays")
	screen.set_hud("full")
	assert_true(screen.stats_overlay.visible, "and they come back with the HUD")


func test_graphics_lay_out_at_the_three_resolutions() -> void:
	for size in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3440, 1440)]:
		var screen := await _screen(size)
		screen.set_mode("replay")
		screen.toggle_stats()
		screen.seek(_first_index(screen, true), false)
		await frames(3)
		var stage := Rect2(Vector2.ZERO, screen.stage.size)
		for c in [screen.spotlight, screen.stats_overlay]:
			var r := Rect2(c.position, c.size)
			assert_true(stage.encloses(r.grow(-1.0)), "%s stays inside the stage at %s (%s in %s)" % [c.name, size, r, stage])
		screen.queue_free()
		await frames(1)
