extends FcLiveTestCase
## Camera direction v2 in a real scene (Broadcast pass 2, M3): the director style choice works and is remembered, an instant replay takes a
## replay shot from a different angle each time, a notable basket gets a celebration shot, and the 3D camera glides between angles without
## ever coming closer than 28 ft.

const PREFS := "user://test_preferences_live_camera_direction.cfg"

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


func _screen(prefs: FcPreferences = null) -> FcReplayScreen:
	host.size = Vector2(1400, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false, prefs)
	screen.size = Vector2(1400, 900)
	host.add_child(screen)
	return screen


func test_the_director_style_choice_works_and_is_remembered() -> void:
	DirAccess.remove_absolute(PREFS)
	var prefs := FcPreferences.new(PREFS)
	var screen := await _screen(prefs)
	await frames(2)
	assert_eq(screen.court.rig.style, "standard")
	screen.set_camera_style("calm")
	assert_eq(screen.court.rig.style, "calm")
	assert_eq(FcPreferences.new(PREFS).camera_style, "calm")
	screen.set_camera_style("nonsense")
	assert_eq(screen.court.rig.style, "calm", "an unknown style is ignored")
	DirAccess.remove_absolute(PREFS)


func test_a_notable_basket_gets_a_celebration_and_an_instant_replay_a_replay_shot() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_mode("broadcast")
	var celebrated := -1
	for i in range(screen.model.start_index(), screen.model.size()):
		if FcCameraDirector.shot_for(screen.timeline, i)["preset"] == FcCameraDirector.PRESET_CELEBRATION:
			celebrated = i
			break
	assert_true(celebrated >= 0)
	screen.seek(celebrated, false)
	assert_eq(screen.court.rig.switch_log().back()["preset"], FcCameraDirector.PRESET_CELEBRATION)
	assert_eq(screen.court.rig.pose_angle()["angle"], FcCameraDirector.ANGLE_CLOSEUP)
	var angles: Array = []
	for k in 3:
		screen.start_instant_replay()
		assert_eq(screen.court.rig.switch_log().back()["preset"], FcCameraDirector.PRESET_REPLAY, "the replay takes the camera at once")
		angles.append(screen.court.rig.pose_angle()["angle"])
		screen.end_instant_replay()
	assert_eq(angles.size(), 3)
	assert_true(angles[0] != angles[1] and angles[1] != angles[2], "each instant replay looks from the next angle: %s" % str(angles))


func test_the_3d_camera_glides_between_angles_and_keeps_its_distance() -> void:
	var screen := await _screen()
	await frames(2)
	if screen.court3d == null:
		return   # the 3D view cannot be built here: the 2D fallback is what is shown, and that is tested elsewhere
	screen.set_mode("broadcast")
	await frames(3)
	var start := screen.court3d.camera_pose()
	screen.court.rig.request(FcCameraDirector.replay_shot_for(screen.timeline, screen.current_index(), 2))   # overhead
	var moved := false
	for k in 40:
		await frames(1)
		var pose := screen.court3d.camera_pose()
		var focus: Vector2 = screen.court.rig.camera()["focus"]
		var d: float = (pose["position"] as Vector3).distance_to(Vector3(focus.x, FcBroadcast3DRules.LOOK_HEIGHT, focus.y))
		assert_true(d >= FcBroadcast3DRules.MIN_DISTANCE - 0.5, "never nearer than 28 ft while gliding (%s)" % d)
		if (pose["position"] as Vector3).distance_to(start["position"]) > 5.0:
			moved = true
	assert_true(moved, "the camera moved to the new angle")
