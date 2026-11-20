extends FcLiveTestCase
## Player visuals in a live tree: every surface draws without errors, the showcase stage idles and stops for reduced motion, and the
## profile lays out in every mode.


func _subjects() -> Array:
	var out: Array = []
	for i in 14:
		out.append(FcPlayerPresentation.subject("owner_player:%d" % i, "Player Number%d" % i, {"name": "Team %d" % (i % 3), "abbreviation": "T%d" % (i % 3)}, i))
	out.append(FcPlayerPresentation.subject("career_player:1", "Maya Okoro", {"primary": "#1F3A5F", "secondary": "#C8A951"}, 11, {"skin": "tone_6", "hair": "braids", "face": "face_5", "facial_hair": "goatee"}))
	return out


func test_every_look_draws_on_every_surface() -> void:
	var flow := HFlowContainer.new()
	flow.size = Vector2(900, 700)
	host.add_child(flow)
	for subject in _subjects():
		flow.add_child(FcPlayerPortrait.new().setup(subject, 64))
		flow.add_child(FcShowcaseStage.new().setup(subject, 120))
		flow.add_child(FcUniformPreview.new().setup(FcPlayerVisual.resolve(subject), 60))
	var mono := FcPlayerPortrait.new().setup(_subjects()[0], 64)
	mono.visual = FcPlayerVisual.monogram_only(_subjects()[0])
	flow.add_child(mono)
	await frames(4)
	assert_eq(flow.get_child_count(), 15 * 3 + 1)
	for c in flow.get_children():
		assert_true(c.size.x > 0.0, "laid out")


func test_the_showcase_idles_and_a_reduced_motion_stage_stands_still() -> void:
	var stage := FcShowcaseStage.new().setup(_subjects()[0], 160)
	host.add_child(stage)
	await seconds(0.6)
	assert_true(stage.bob > 0.0, "a gentle idle bob (%s)" % stage.bob)
	FcMotion.reduced = true
	var still := FcShowcaseStage.new().setup(_subjects()[0], 160)
	host.add_child(still)
	await seconds(0.5)
	assert_eq(still.bob, 0.0, "no idle motion when reduced")


func test_the_profile_draws_for_a_card_a_world_player_and_a_career() -> void:
	var dir := "user://test_dynasty_live_player"
	FcSafeFile.remove_tree(dir)
	FcDynastyFixture.wipe()
	host.size = Vector2(1000, 800)
	var app := FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences_live_player.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_player")
	host.add_child(app)
	await frames(2)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(dir))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Live Players", "LVP")
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	var modal := FcPlayerProfile.open_modal(app, vm)
	await frames(3)
	var stage: FcShowcaseStage = modal.find_children("*", "FcShowcaseStage", true, false)[0]
	assert_true(stage.size.x > 100 and stage.size.y > 100, "the stage is laid out at a readable size")
	modal.close(true)
	await seconds(0.3)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Live League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	FcPlayerProfile.open_modal(app, FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id))
	await frames(3)
	assert_eq(app.host.modals.count(), 1)
	FcSafeFile.remove_tree(dir)
	FcSafeFile.remove_tree("user://test_saves_live_player")
	FcDynastyFixture.wipe()
	DirAccess.remove_absolute("user://test_preferences_live_player.cfg")
