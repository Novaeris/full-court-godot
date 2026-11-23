extends FcLiveTestCase
## The replay screen's presentation modes and HUD (Broadcast pass 2, M1) in a real scene: the three modes look different, switching never
## moves the replay, the HUD levels hide what they should, panels fold away, the camera panel is contextual, the choice is remembered, and
## the screen still lays out at 1080p, 1440p and ultrawide sizes.

const PREFS := "user://test_preferences_live_modes.cfg"

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


func _screen(size: Vector2 = Vector2(1100, 800), prefs: FcPreferences = null) -> FcReplayScreen:
	host.size = size
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false, prefs)
	screen.size = size
	host.add_child(screen)
	return screen


func test_default_is_replay_mode_with_a_full_hud() -> void:
	var screen := await _screen()
	await frames(2)
	assert_eq(screen.mode, "replay")
	assert_eq(screen.hud, "full")
	assert_true(screen.feed.get_parent().visible and screen.scrubber.visible and screen.bug.visible)
	assert_true(not screen.lineup_card.get_parent().get_parent().visible, "lineups belong to analysis")


func test_the_modes_show_different_things() -> void:
	var screen := await _screen()
	screen.set_mode("broadcast")
	await frames(2)
	assert_true(not screen.feed.get_parent().visible and not screen.scrubber.visible and not screen.camera_inner.get_parent().visible)
	assert_true(screen.bug.visible and screen.caption.visible)
	assert_eq(screen.state.camera_mode, "auto")
	screen.set_mode("analysis")
	await frames(2)
	assert_true(screen.feed.get_parent().visible and screen.team_card.get_parent().get_parent().visible and screen.lineup_card.get_parent().get_parent().visible)
	assert_eq(screen.state.view_id, "flat")
	assert_eq(screen.state.camera_mode, "manual")


func test_switching_mode_never_moves_the_replay() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(40, false)
	screen.set_speed(2.0)
	screen.toggle_play()
	var before := screen.state.index
	for m in ["broadcast", "analysis", "replay", "broadcast"]:
		screen.set_mode(m)
		assert_eq(screen.state.index, before, "index after %s" % m)
		assert_eq(screen.speed, 2.0)
		assert_true(screen.is_playing())
	screen.toggle_play()
	screen.start_instant_replay()
	var snap := [screen.state.index, screen.state.instant.duplicate()]
	screen.set_mode("analysis")
	assert_eq([screen.state.index, screen.state.instant], snap, "an instant replay survives a mode switch")
	screen.end_instant_replay()


func test_hud_levels_and_the_h_key() -> void:
	var screen := await _screen()
	screen.set_hud("minimal")
	assert_true(screen.bug.visible and screen.overlay.visible)
	assert_true(not screen.caption.visible and not screen.transport.visible)
	screen.set_hud("hidden")
	assert_true(not screen.bug.visible and not screen.overlay.visible and not screen.feed.get_parent().visible)
	assert_true(screen.mode_group.get_parent().visible, "the mode bar stays so there is always a way back")
	screen.cycle_hud()
	assert_eq(screen.hud, "full")
	assert_true(screen.bug.visible and screen.transport.visible)


func test_panels_fold_and_the_camera_panel_is_contextual() -> void:
	var screen := await _screen()
	screen.toggle_collapsed("feed")
	assert_true(not screen.feed.get_parent().visible)
	assert_true(screen.feed_toggle.text.contains("show"))
	screen.toggle_collapsed("feed")
	assert_true(screen.feed.get_parent().visible)
	screen.toggle_collapsed("camera")
	assert_true(not screen.camera_inner.visible and screen.camera_toggle.visible)
	screen.toggle_collapsed("camera")
	screen.set_camera_mode("auto")
	for b in screen.camera_buttons:
		assert_true(not b.visible, "manual buttons are hidden while the camera is automatic")
	screen.set_camera_mode("manual")
	for b in screen.camera_buttons:
		assert_true(b.visible and not b.disabled)


func test_the_choice_is_remembered() -> void:
	DirAccess.remove_absolute(PREFS)
	var prefs := FcPreferences.new(PREFS)
	var screen := await _screen(Vector2(1100, 800), prefs)
	screen.set_mode("analysis")
	screen.set_hud("minimal")
	var again := FcPreferences.new(PREFS)
	assert_eq(again.presentation_mode, "analysis")
	assert_eq(again.hud_level, "minimal")
	var second := await _screen(Vector2(1100, 800), again)
	assert_eq(second.mode, "analysis")
	assert_eq(second.hud, "minimal")
	DirAccess.remove_absolute(PREFS)


func test_it_lays_out_at_1080p_1440p_and_ultrawide() -> void:
	for size in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3440, 1440)]:
		for m in ["broadcast", "replay", "analysis"]:
			var screen := await _screen(size)
			screen.set_mode(m)
			await frames(2)
			assert_true(screen.stage.size.x > size.x * 0.4 and screen.stage.size.y > 150.0, "%s %s: the stage is a real size (%s)" % [m, size, screen.stage.size])
			screen.queue_free()
			await frames(1)
