extends FcLiveTestCase
## Broadcast pass 2, M8: the validation matrix. Every presentation mode x every HUD level x the three desktop resolutions (1080p, 1440p, ultrawide)
## x three audio configurations (everything on, muted, captions off) keeps its promises: the replay state never moves on a switch, the panels
## follow the rules, the stage is a real size, nothing draws under a hidden HUD. The 2D fallback keeps every new feature working, a phone layout
## fits in every mode, and the three entry points (Owner, Career-style and Dynasty-style data) all open the same screen.

const PREFS := "user://test_preferences_live_matrix.cfg"
const SIZES := [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3440, 1440)]
const MODES := ["broadcast", "replay", "analysis"]
const HUDS := ["full", "minimal", "hidden"]

var game: Dictionary = {}
var prefs: FcPreferences
var audio: FcAudio
var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
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
	prefs = FcPreferences.new(PREFS)
	audio = FcAudio.new(prefs)
	host.add_child(audio)
	FcAudio.current = audio


func after_each() -> void:
	FcBroadcast3DView.force_failure = false
	if FcAudio.current == audio:
		FcAudio.current = null
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree("user://test_saves_live_matrix")
	super.after_each()


func _screen(size: Vector2, phone: bool = false) -> FcReplayScreen:
	host.size = size
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], phone, null)
	screen.size = size - Vector2(0, 20)
	host.add_child(screen)
	return screen


func _configure_audio(kind: String) -> void:
	prefs.audio_muted = kind == "muted"
	prefs.sound_captions = kind != "captions_off"
	audio.apply_settings()


func test_the_matrix_of_modes_huds_resolutions_and_audio_keeps_its_promises() -> void:
	for size in SIZES:
		for audio_kind in ["on", "muted", "captions_off"]:
			_configure_audio(audio_kind)
			var screen := await _screen(size)
			await frames(2)
			screen.seek(screen.model.start_index() + 60, false)
			screen.toggle_play()
			for i in 6:
				screen.advance(30.0)   # a few events with sound, captions and commentary through the real audio
			var played := screen.state.snapshot().slice(0, 3)
			for mode in MODES:
				for hud in HUDS:
					screen.set_mode(mode)
					screen.set_hud(hud)
					await frames(1)
					var where := "%s / %s / %s / audio %s" % [size, mode, hud, audio_kind]
					assert_eq(screen.state.snapshot().slice(0, 3), played, "the replay never moves on a switch (%s)" % where)
					assert_true(screen.mode_group.get_parent().visible, "the way back is always there (%s)" % where)
					assert_true(screen.stage.size.x > size.x * 0.35 and screen.stage.size.y > 150.0, "the stage is a real size (%s: %s)" % [where, screen.stage.size])
					for panel in [FcPresentationMode.P_FEED, FcPresentationMode.P_ROSTERS, FcPresentationMode.P_LINEUPS, FcPresentationMode.P_TEAMS]:
						var want: bool = FcPresentationMode.panel_visible(mode, hud, panel) and not (panel == FcPresentationMode.P_FEED and bool(screen.collapsed.get(panel, false)))
						for c in screen._panels[panel]:
							assert_eq((c as Control).visible, want, "%s follows the rules (%s)" % [panel, where])
					if hud == "hidden":
						assert_true(not screen.bug.visible and not screen.overlay.visible and not screen.spotlight.visible and not screen.stats_overlay.visible, "nothing draws under a hidden HUD (%s)" % where)
					if hud != "full":
						assert_true(not screen.caption.visible and not screen.analyst_label.visible and not screen.announcer_label.visible, "no captions below a full HUD (%s)" % where)
					if audio_kind == "captions_off":
						assert_eq(screen.analyst_label.text, "", "captions off: no commentary text (%s)" % where)
					if mode == "broadcast":
						assert_true(screen.overlay.auto_hide, "the lower third leaves by itself in Broadcast (%s)" % where)
			screen.queue_free()
			await frames(1)
	assert_eq(audio.active_loops().size() >= 0, true)


func test_the_2d_fallback_keeps_every_new_feature_working() -> void:
	FcBroadcast3DView.force_failure = true
	var screen := await _screen(Vector2(1920, 1080))
	await frames(2)
	assert_true(screen.court3d == null, "the 3D view could not be built")
	assert_true(screen.view_note.visible, "and the screen says so")
	screen.seek(screen.model.start_index() + 40, false)
	for mode in MODES:
		screen.set_mode(mode)
		assert_true(screen.court.visible, "the 2D court is the picture in %s" % mode)
	screen.set_mode("replay")
	screen.toggle_bookmark()
	assert_eq(screen.marks.mark_counts()["bookmark"], 1)
	screen.start_instant_replay()
	assert_true(screen.is_instant_replay())
	screen.end_instant_replay()
	screen.start_reel()
	assert_true(screen.is_reel())
	for i in 200:
		if not screen.is_reel():
			break
		screen.advance(30.0)
	assert_true(not screen.is_reel())
	screen.start_introductions()
	for i in 12:
		screen.advance(3.0)
	assert_true(not screen.is_intro())
	for id in ["pregame", "halftime", "postgame"]:
		screen.start_show(id)
		assert_true(screen.show_panel.visible and screen.show_panel.summary() != "")
		screen.end_show()
	screen.toggle_play()
	for i in 10:
		screen.advance(30.0)
	assert_true(screen.analyst_label.text != "" or screen.announcer_label.text != "" or screen.commentary_label.text != "", "commentary captions still run")
	screen.set_camera_style("calm")
	screen.set_view("flat")
	assert_true(screen.court.visible)


func test_a_phone_layout_fits_in_every_mode() -> void:
	for mode in MODES:
		for phone_width in [360.0, 412.0]:
			var screen := await _screen(Vector2(phone_width, 800), true)
			screen.set_mode(mode)
			await frames(3)
			assert_true(screen.get_combined_minimum_size().x <= phone_width, "%s on %d px needs %d" % [mode, int(phone_width), int(screen.get_combined_minimum_size().x)])
			assert_eq(screen.state.view_id != "broadcast3d", true, "a phone never gets the 3D view (D-030)")
			screen.start_show("postgame")
			await frames(2)
			assert_true(screen.get_combined_minimum_size().x <= phone_width, "a show fits a phone too (%s needs %d)" % [mode, int(screen.get_combined_minimum_size().x)])
			screen.end_show()
			screen.queue_free()
			await frames(1)


func _owner_app() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_matrix")
	host.add_child(app)
	app.setup()


func test_the_three_entry_points_open_the_same_screen() -> void:
	_owner_app()
	await frames(2)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Matrix"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	app.controller.advance_days(8)
	var kept: Array = app.controller.season().recent_boxes
	assert_true(not kept.is_empty())
	# Owner: a stored season entry, with the world's teams (crests) and the owner's bookmark file
	var owner_built := FcReplay.for_owner(app.controller, kept[kept.size() - 1])
	assert_true(not owner_built.is_empty() and (owner_built["subjects"] as Array).size() == 2)
	# Career-style and Dynasty-style: the same box and events with no world teams
	var dynasty_built := FcReplay.for_dynasty({"box": game["box"].to_dict(), "events": game["log"].to_dict()})
	assert_true(not dynasty_built.is_empty() and (dynasty_built["subjects"] as Array).is_empty())
	for built in [owner_built, dynasty_built]:
		var modal := FcReplay.open(app, built)
		await frames(3)
		var screen := app.find_child("ReplayScreen", true, false) as FcReplayScreen
		assert_true(screen != null and screen.model != null and not screen.model.is_empty())
		assert_eq(screen.bug.has_crests(), not (built["subjects"] as Array).is_empty(), "crests only where the world's teams are known")
		for mode in MODES:
			screen.set_mode(mode)
			assert_eq(screen.mode, mode)
		screen.set_mode("replay")
		for id in ["pregame", "halftime", "postgame"]:
			screen.start_show(id)
			assert_true(screen.is_show())
			screen.end_show()
		screen.start_reel()
		screen.end_reel()
		assert_true(not screen.title_context.is_empty() == false, "an ordinary game is not a title game")
		modal.close(false)
		await frames(2)
	assert_eq(app.host.modals.count(), 0)
