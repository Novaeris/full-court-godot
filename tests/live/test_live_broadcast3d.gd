extends FcLiveTestCase
## The 3D broadcast view inside the real replay screen (master plan B4, decision D-070 reduced scope): it shows the same replay as the 2D court
## (same event, score and clock), the characters stand where the reconstruction puts them, switching views and falling back to 2D lose nothing
## (and a forced failure leaves a working 2D screen), the camera never gets closer than the minimum distance and can be moved by hand, and
## nothing in the game data changes.

var game: Dictionary = {}


func before_each() -> void:
	super.before_each()
	FcBroadcast3DView.force_failure = false
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
	FcBroadcast3DView.force_failure = false
	super.after_each()


func _screen() -> FcReplayScreen:
	host.size = Vector2(1100, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1100, 880)
	host.add_child(screen)
	return screen


func _state(screen: FcReplayScreen) -> Array:
	return [screen.current_index(), screen.bug.summary(), screen.caption.text, screen.speed, screen.is_playing()]


func test_the_3d_view_is_offered_and_shows_ten_players() -> void:
	var screen := await _screen()
	await frames(3)
	assert_true(screen.court3d != null, "the 3D view was built")
	screen.set_view("broadcast3d")
	screen.seek(screen.model.start_index() + 20, false)
	await frames(3)
	assert_true(screen.court3d.visible and not screen.court.visible, "3D shown, 2D hidden")
	assert_eq(screen.court3d.on_court_ids().size(), 10, "ten characters on court")


func test_switching_views_loses_nothing() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 25, false)
	screen.set_speed(2.0)
	await frames(2)
	var before := _state(screen)
	for id in ["broadcast3d", "broadcast", "flat", "broadcast3d", "broadcast"]:
		screen.set_view(id)
		await frames(2)
		assert_eq(_state(screen), before, "state after switching to %s" % id)


func test_characters_walk_to_the_reconstructed_positions() -> void:
	var screen := await _screen()
	screen.set_view("broadcast3d")
	await frames(2)
	var index := screen.model.start_index() + 30
	screen.seek(index, false)   # no animation: everyone is placed at once
	await frames(2)
	var result := FcReconstructor.build(screen.timeline)
	var last := {}
	for f in result["keyframes"]:
		if int(f["event"]) == index:
			last = f
	assert_true(not last.is_empty(), "the reconstruction has frames for the event")
	var checked := 0
	for pid in last["players"]:
		var c: FcBroadcastCharacter = screen.court3d.characters[pid]
		var at: Vector2 = last["players"][pid]
		assert_true(Vector2(c.position.x, c.position.z).distance_to(at) < 0.5, "player %d stands at the reconstructed spot" % pid)
		checked += 1
	assert_eq(checked, 10)


func test_a_forced_failure_leaves_a_working_2d_screen_without_losing_state() -> void:
	FcBroadcast3DView.force_failure = true
	var screen := await _screen()
	await frames(3)
	assert_true(screen.court3d == null, "no 3D view")
	assert_true(screen.view_note.visible, "the user is told, in words")
	screen.set_view("broadcast3d")   # asking for 3D anyway
	screen.seek(screen.model.start_index() + 12, false)
	await frames(2)
	assert_true(screen.court.visible, "the 2D court is what shows")
	assert_eq(screen.current_index(), screen.model.start_index() + 12, "the replay position is kept")
	assert_true(screen.bug.summary() != "", "score and clock still show")


func test_the_camera_never_comes_closer_than_the_minimum_and_obeys_the_hand() -> void:
	var screen := await _screen()
	screen.set_view("broadcast3d")
	screen.seek(screen.model.start_index() + 20, false)
	await frames(2)
	for i in 20:
		screen.court.rig.manual_move(Vector2.ZERO, 1.5)   # zoom in hard, many times
	await frames(3)
	var pose := screen.court3d.camera_pose()
	var focus := screen.court.rig.camera()["focus"] as Vector2
	var distance: float = (pose["position"] as Vector3).distance_to(Vector3(focus.x, FcBroadcast3DRules.LOOK_HEIGHT, focus.y))
	assert_true(distance >= FcBroadcast3DRules.MIN_DISTANCE - 0.01, "never closer than %.0f ft (was %.1f)" % [FcBroadcast3DRules.MIN_DISTANCE, distance])
	var before := screen.court3d.camera_pose()["position"] as Vector3
	screen.court.rig.mode = FcCameraRig.Mode.MANUAL
	screen.court.rig.manual_move(Vector2(15, 0), 1.0)
	await frames(3)
	var after := screen.court3d.camera_pose()["position"] as Vector3
	assert_true(before.distance_to(after) > 1.0, "a manual move moves the 3D camera")


func test_the_3d_view_changes_no_game_data() -> void:
	var screen := await _screen()
	var rows_before := JSON.stringify((game["log"] as FcGameEventLog).to_dict())
	var box_before := JSON.stringify((game["box"] as FcBoxScore).to_dict())
	screen.set_view("broadcast3d")
	for k in 12:
		screen.seek(screen.model.start_index() + k * 5, true)
		await frames(2)
	assert_eq(JSON.stringify((game["log"] as FcGameEventLog).to_dict()), rows_before)
	assert_eq(JSON.stringify((game["box"] as FcBoxScore).to_dict()), box_before)


func test_an_introduction_spotlights_the_player_and_ends_cleanly() -> void:
	var screen := await _screen()
	await frames(3)
	screen.set_view("broadcast3d")
	await frames(2)
	screen.start_introductions()
	await frames(6)
	var step: Dictionary = (screen.state.intro["steps"] as Array)[0]
	var id := int(step["player_id"])
	assert_eq(screen.court3d.character_state(id), "intro", "the introduced player waves")
	assert_true(screen.court3d._spot_ring != null and screen.court3d._spot_ring.visible, "a ring on the floor picks him out")
	var others := 0
	for pid in screen.court3d.on_court_ids():
		if pid != id and screen.court3d.character_state(pid) == "idle":
			others += 1
	assert_true(others >= 8, "the others stand still (%d)" % others)
	var subject: FcBroadcastCharacter = screen.court3d.characters[id]
	var chest := subject.global_position + Vector3(0.0, 4.2, 0.0)
	var cam_distance: float = screen.court3d.scene.camera.global_position.distance_to(chest)
	assert_true(cam_distance >= FcBroadcast3DRules.MIN_DISTANCE - 1.0, "the introduction camera keeps the 28 ft minimum (%.1f ft from his chest)" % cam_distance)
	screen.end_introductions()
	await frames(4)
	assert_true(not screen.court3d._spot_ring.visible, "the ring is gone when the introductions end")


func test_a_phone_keeps_the_2d_replay_and_never_builds_3d() -> void:
	host.size = Vector2(412, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], true)
	screen.size = Vector2(412, 880)
	host.add_child(screen)
	await frames(3)
	assert_true(screen.court3d == null, "no 3D view is built on a phone (D-030): no memory or start-up time is spent on it")
	assert_true(screen.court.visible, "the 2D court is shown")
	for mode in ["broadcast", "replay", "analysis"]:
		screen.set_mode(mode)
		await frames(2)
		assert_true(screen.court.visible, "%s mode on a phone shows the 2D court" % mode)
	screen.seek(screen.model.start_index() + 20, false)
	await frames(2)
	assert_eq(screen.current_index(), screen.model.start_index() + 20, "the replay position still works")
	screen.start_introductions()
	await frames(2)
	screen.end_introductions()
	await frames(2)
	assert_true(screen.is_intro() == false, "the introductions run and end on a phone without a 3D view")
