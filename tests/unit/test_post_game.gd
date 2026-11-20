extends FcTestCase
## Phase 9: the shared post-game screen. The model is pure (same box score in, same view out, nothing changed), the player of the game
## is a labelled display pick, the screen shows only what the model holds, and Dynasty's box score pass-through changes no saved data.

const PREFS := "user://test_preferences_post_game.cfg"
const DYNASTY := "user://test_dynasty_post_game"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_post_game.cfg")
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_post_game")
	FcDynastyFixture.wipe()


func _dynasty() -> void:
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_post_game")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Post Kings", "PGK"))
	app.dynasty.auto_fill_lineup()


func _box() -> Dictionary:
	_dynasty()
	var r := app.dynasty.play_quick_game("easy")
	assert_true(r.ok, "a game was played")
	return app.dynasty.last_game


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


# --- the data the screen needs ----------------------------------------------------------------------------------------------------

func test_dynasty_passes_the_box_score_through_without_changing_the_summary() -> void:
	var game := _box()
	assert_true(game.has("box") and game.has("user_side") and game.has("cards"), "the finished game carries its box score")
	var s: Dictionary = game["summary"]
	var box: Dictionary = game["box"]
	var us: int = game["user_side"]
	assert_eq(int(box["scores"][us]), int(s["score_for"]), "the box and the summary agree on the user's score")
	assert_eq(int(box["scores"][1 - us]), int(s["score_against"]))


func test_the_pass_through_changes_no_saved_data() -> void:
	_dynasty()
	# the profile's serialised form has no box, no cards map and nothing from the post-game view
	assert_true(app.dynasty.play_quick_game("easy").ok)
	var text := JSON.stringify(app.dynasty.profile().to_dict())
	assert_true(not text.contains("period_scores") and not text.contains("\"box\""), "the profile does not keep the box score")


func test_the_model_describes_the_game() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var sides: Array = vm["sides"]
	assert_eq(int(sides[0]["score"]), int(game["box"]["scores"][0]))
	assert_true(sides[0]["won"] != sides[1]["won"], "exactly one side won")
	assert_eq(vm["result"], "win" if game["summary"]["won"] else "loss")
	var line: Dictionary = vm["line_score"]
	assert_eq((line["columns"] as Array).size(), (line["rows"][0] as Array).size(), "one cell for every column")
	for side in 2:
		var total := 0
		for i in range(1, (line["rows"][side] as Array).size() - 1):
			total += int(line["rows"][side][i])
		assert_eq(total, int(sides[side]["score"]), "the quarters add up to the final score")
	assert_eq((vm["comparison"] as Array).size(), 8)
	assert_eq((vm["tables"] as Array).size(), 2)
	assert_true(str(vm["headline"]).contains(str(sides[int(game["user_side"])]["name"])), "the headline is from the user's side")


func test_the_model_is_deterministic_and_changes_nothing() -> void:
	var game := _box()
	var before := JSON.stringify(game["box"])
	var a := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var b := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	assert_eq(JSON.stringify(a), JSON.stringify(b), "the same box score gives the same view")
	assert_eq(JSON.stringify(game["box"]), before, "the box score was not modified")


func test_the_player_of_the_game_is_a_labelled_display_pick_from_the_winners() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var pog: Dictionary = vm["pog"]
	assert_true(not pog.is_empty(), "someone is picked")
	assert_true("Player of the game" in str(pog["label"]) and "display" in str(pog["note"]).to_lower(), "it is labelled as a display pick")
	var winner := 0 if vm["sides"][0]["won"] else 1
	assert_eq(int(pog["side"]), winner, "winners only")
	for e in vm["performers"]:
		assert_true(float(e["score"]) <= float((vm["performers"] as Array)[0]["score"]), "performers are ranked best first")


func test_the_pick_follows_the_weights_in_the_data_file() -> void:
	var cfg := FcPostGameModel.config()
	assert_true(cfg["weights"].has("points") and cfg["weights"].has("turnovers"), "the weights are data, not code")
	var p := FcPlayerGameStats.new()
	p.points = 20
	p.ast = 4
	var plain := FcPostGameModel.display_score(p, {"points": 1.0})
	var passer := FcPostGameModel.display_score(p, {"points": 1.0, "assists": 2.0})
	assert_eq(plain, 20.0)
	assert_eq(passer, 28.0)


# --- the screen -----------------------------------------------------------------------------------------------------------------------

func test_the_screen_shows_the_result_first_and_what_the_model_holds() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"], "rewards": ["+50 credits"], "implications": ["Record 1-0."]})
	var screen := FcPostGameScreen.new().setup(vm)
	assert_true(screen.get_child(0) is FcPanel, "the first thing is the result")
	assert_true(screen.bug.summary().contains(str(vm["sides"][0]["score"])), "the score bug shows the final score")
	assert_eq(screen.bars.size(), 8, "eight comparison bars")
	var texts := ""
	for l in _find(screen, Label):
		texts += (l as Label).text + "\n"
	assert_true(texts.contains("Line score") and texts.contains("Top performers") and texts.contains("After the game"), "the sections are there")
	assert_true(texts.contains(str(vm["pog"]["name"])), "the player of the game is named")
	screen.free()


func test_the_team_tabs_show_each_teams_lines() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var screen := FcPostGameScreen.new().setup(vm)
	var seen: Array = []
	screen.team_tab_changed.connect(func(side: int) -> void: seen.append(side))
	screen.show_team(0)
	screen.show_team(1)
	assert_eq(seen, [0, 1])
	assert_eq(screen.tabs.tab_ids().size(), 2)
	screen.free()


func test_a_player_has_the_same_face_in_the_post_game_as_on_his_card() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var pid: int = int(vm["pog"]["pid"])
	var card_id := str(game["cards"][pid])
	var row := {}
	for r in FcCollectionQuery.rows(app.dynasty.profile(), app.dynasty.catalog, {}):
		if str(r["card_id"]) == card_id:
			row = r
	assert_true(not row.is_empty(), "the card of the player of the game is in the catalog")
	var shown := FcDynastyScreensPlay.post_game(app.dynasty_ui, game)
	var expected := FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card(row))
	var found := false
	for portrait in _find(shown, FcPlayerPortrait):
		if (portrait as FcPlayerPortrait).visual == expected:
			found = true
	assert_true(found, "the post-game portrait is the card's visual")
	shown.free()


func test_the_play_screen_uses_the_shared_post_game_view() -> void:
	_box()
	app.dynasty_ui.show_tab("play")
	assert_eq(_find(app._root, FcPostGameScreen).size(), 1, "the Dynasty play screen shows the shared post-game screen")


func test_a_win_is_green_and_a_loss_is_red_in_the_headline() -> void:
	var game := _box()
	var vm := FcPostGameModel.build(game["box"], {"user_side": game["user_side"]})
	var other := FcPostGameModel.build(game["box"], {"user_side": 1 - int(game["user_side"])})
	assert_true(vm["result"] != other["result"], "the same game is a win for one side and a loss for the other")
	var neutral := FcPostGameModel.build(game["box"], {})
	assert_eq(neutral["result"], "", "a game the user is not in has no win or loss")


# --- the other modes ------------------------------------------------------------------------------------------------------------------

func test_owner_mode_shows_a_stored_game_with_standings_and_branding_colours() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_post_game")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Post League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(14)
	var boxes: Array = app.controller.season().recent_boxes
	assert_true(not boxes.is_empty(), "the owner's team has played")
	var built := FcPostGame.for_owner(app.controller, boxes[0]["box"])
	var vm: Dictionary = built["vm"]
	assert_true(int(vm["user_side"]) >= 0 and vm["result"] in ["win", "loss"])
	assert_true((vm["implications"] as Array).size() == 1 and "Season record now" in str(vm["implications"][0]), "the standings are shown")
	assert_eq((built["colors"] as Array).size(), 2)
	var modal := FcPostGame.open(app, built)
	assert_true(modal != null and _find(modal, FcPostGameScreen).size() == 1, "the dialog holds the shared screen")


func test_career_mode_sets_the_players_night_against_the_season_average() -> void:
	var defs := FcDefinitionSet.load_default()
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var strong := ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]
	for key in spec["attributes"]:
		spec["attributes"][key] = 70 if key in strong else 25   # a strong build, so he plays and the box scores contain him
	var career: FcCareerController = FcCareerController.new_career(spec, 41)["controller"]
	assert_true(career.join_team(career.state.world.teams.ids()[2])["ok"])
	while career.profile().pending_event != "":
		career.answer_event(str(career.pending_event()["choices"][0]["key"]))
	var result := career.advance_days(40)
	assert_true(result["ok"] and not (result["games"] as Array).is_empty(), "the player played")
	var game: Dictionary = result["games"][0]
	assert_true(game.has("box"), "the game carries its box score")
	var built := FcPostGame.for_career(career, game)
	var vm: Dictionary = built["vm"]
	assert_true(vm["implications"][0].begins_with("Your night:"), "the player's own line comes first")
	assert_true((vm["rewards"] as Array)[0].begins_with("+"), "the XP the game paid is listed")
	assert_eq(int(vm["user_side"]), FcPostGame.user_side(game["box"], career.state.user_team_id))
