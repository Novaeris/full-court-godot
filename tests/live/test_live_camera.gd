extends FcLiveTestCase
## The 2D broadcast camera in the real replay screen (master plan B2b option B): the director's shots reach the camera, the person can take
## over by buttons, drag and wheel, the camera comes back or is reset, the flat view stays selectable, switching views or moving the camera
## never changes the replay position, score, clock or caption, reduced motion snaps, and a phone still fits.

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


func after_each() -> void:
	FcMotion.reduced = false
	super.after_each()


func _screen(width: float = 1100.0, phone: bool = false) -> FcReplayScreen:
	host.size = Vector2(width, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], phone)
	screen.size = Vector2(width, 880)
	host.add_child(screen)
	return screen


func _first(screen: FcReplayScreen, type: int) -> int:
	for e in screen.model.entries:
		if e["type"] == type:
			return e["index"]
	return -1


func _state(screen: FcReplayScreen) -> Array:
	return [screen.current_index(), screen.bug.summary(), screen.caption.text, FcOnlineCrypto.canonical(screen.model.state_at(screen.current_index())["points"])]


func test_it_opens_in_the_broadcast_view_with_the_director_in_charge() -> void:
	var screen := await _screen()
	await frames(2)
	assert_true(screen.court.broadcast_view, "the broadcast view is the default")
	assert_eq(screen.court.rig.mode, FcCameraRig.Mode.HYBRID)
	var made := _first(screen, FcGameEventLog.EV_SHOT_MADE)
	screen.seek(made, false)
	var shot := FcCameraDirector.shot_for(screen.timeline, made)
	assert_eq(screen.court.rig.target()["focus"], shot["focus"], "the camera was asked to frame the basket")
	assert_eq(screen.court.rig.target()["zoom"], shot["zoom"])
	assert_eq(screen.court.rig.camera()["focus"], shot["focus"], "a made shot is a cut: it is already there")
	assert_eq(screen.court.home_abbreviation, str(screen.model.box.abbreviations[0]), "the home mark is at centre court")
	screen.court.queue_redraw()
	await frames(2)


func test_the_flat_view_is_selectable_and_switching_views_changes_nothing_else() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(_first(screen, FcGameEventLog.EV_FOUL), false)
	var before := _state(screen)
	screen.set_view("flat")
	await frames(2)
	assert_true(not screen.court.broadcast_view)
	assert_eq(_state(screen), before, "same event, score, clock and caption in the flat view")
	screen.court.queue_redraw()
	await frames(2)
	screen.set_view("broadcast")
	await frames(2)
	assert_true(screen.court.broadcast_view)
	assert_eq(_state(screen), before, "and back again")
	for i in 6:
		screen.set_view("flat" if i % 2 == 0 else "broadcast")
	assert_eq(_state(screen), before, "many switches change nothing")


func test_the_person_takes_over_by_buttons_and_the_camera_returns() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(_first(screen, FcGameEventLog.EV_SHOT_MADE), false)
	var zoom_before: float = screen.court.rig.target()["zoom"]
	var before := _state(screen)
	screen.camera_buttons[1].pressed.emit()   # zoom in
	assert_true(screen.court.rig.is_overridden(), "the person has the camera")
	assert_true(float(screen.court.rig.target()["zoom"]) > zoom_before)
	assert_eq(_state(screen), before, "moving the camera changes no game state")
	screen.seek(_first(screen, FcGameEventLog.EV_FREE_THROW), false)
	assert_true(float(screen.court.rig.target()["zoom"]) > zoom_before, "a new event does not pull the camera back while the person is steering")
	screen.court.rig.advance(5.0)   # the idle time passes
	assert_true(not screen.court.rig.is_overridden())
	assert_eq(screen.court.rig.target()["focus"], FcCameraDirector.shot_for(screen.timeline, screen.current_index())["focus"], "back to the director's latest shot")
	screen.camera_buttons[1].pressed.emit()
	screen.reset_camera()
	assert_true(not screen.court.rig.is_overridden(), "reset gives it back at once")


func test_automatic_mode_ignores_the_person_and_disables_the_buttons() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_camera_mode("auto")
	for b in screen.camera_buttons:
		assert_true(b.disabled, "%s is off in automatic mode" % b.text)
	var target_before := screen.court.rig.target()
	screen.court.rig.manual_move(Vector2(20, 0), 2.0)
	assert_eq(screen.court.rig.target(), target_before, "input is ignored")
	screen.set_camera_mode("manual")
	for b in screen.camera_buttons:
		assert_true(not b.disabled)
	screen.camera_buttons[0].pressed.emit()   # whole court
	var held := screen.court.rig.target()
	screen.seek(_first(screen, FcGameEventLog.EV_SHOT_MADE), false)
	assert_eq(screen.court.rig.target(), held, "manual mode keeps the camera where the person put it")
	screen.reset_camera()
	assert_eq(screen.court.rig.mode, FcCameraRig.Mode.HYBRID)
	assert_eq(screen.camera_group.current_id, "hybrid", "the mode control shows the shared mode again")


func test_dragging_pans_the_court_under_the_pointer_and_the_wheel_zooms() -> void:
	var screen := await _screen()
	await frames(3)
	screen.set_camera_mode("manual")
	screen.court.rig.manual_set(Vector2(47, 25), 2.0)
	screen.court.rig.advance(1.0)
	var start: Vector2 = screen.court.rig.target()["focus"]
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen.court.size / 2.0
	screen.court._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = screen.court.size / 2.0 + Vector2(60, 0)
	move.relative = Vector2(60, 0)
	screen.court._gui_input(move)
	var after: Vector2 = screen.court.rig.target()["focus"]
	assert_true(after.x < start.x, "dragging the court to the right moves the camera left (%s to %s)" % [str(start), str(after)])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	screen.court._gui_input(release)
	screen.court._gui_input(move)
	assert_eq(screen.court.rig.target()["focus"], after, "after the button is released a move does nothing")
	var zoom: float = screen.court.rig.target()["zoom"]
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	screen.court._gui_input(wheel)
	assert_true(float(screen.court.rig.target()["zoom"]) > zoom, "the wheel zooms in")


func test_reduced_motion_snaps_the_camera() -> void:
	FcMotion.reduced = true
	var screen := await _screen()
	await frames(2)
	screen.seek(_first(screen, FcGameEventLog.EV_REBOUND), false)
	await frames(3)
	assert_eq(screen.court.rig.camera(), screen.court.rig.target(), "no glide with reduced motion")


func test_the_controls_fit_a_phone() -> void:
	var screen := await _screen(360.0, true)
	await frames(3)
	assert_true(screen.get_combined_minimum_size().x <= 360.0, "the replay screen fits 360 px (%d)" % int(screen.get_combined_minimum_size().x))
	var controls := screen.find_child("CameraControls", true, false) as Control
	assert_true(controls != null and controls.get_combined_minimum_size().x <= 330.0, "the camera controls wrap on a phone (%d)" % int(controls.get_combined_minimum_size().x))
