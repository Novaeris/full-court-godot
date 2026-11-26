extends FcLiveTestCase
## The game-day flow in the real app (Phase 2D): the preview opens from the Owner dashboard and the Career hub, "Play this game" plays up
## to that game and opens its summary with the replay, the Career hub lists recent games with a replay button, and the preview fits a phone.

const PREFS := "user://test_preferences_live_gameday.cfg"

var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_gameday")
	host.add_child(app)
	app.setup()


func after_each() -> void:
	super.after_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_live_gameday.cfg")
	FcSafeFile.remove_tree("user://test_saves_live_gameday")


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func test_the_owner_previews_plays_and_watches() -> void:
	await frames(2)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Day Owner"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	app.controller.advance_days(3)
	app.show_dashboard()
	await frames(2)
	var open_button := _find_button(app, "Game day")
	assert_true(open_button != null, "the dashboard offers Game day while there is a game to play")
	var game := app.controller.next_user_game()
	var played_before := app.controller.season().games_played_count()
	open_button.pressed.emit()
	await frames(2)
	assert_eq(app.navigator.current_id, "game:%d" % game.id, "Game day opens the Game Center of the next game (D-077 M5)")
	var screen := app.find_child("GameDayScreen", true, false) as FcGameDayScreen
	assert_true(screen != null, "the preview is in the Game Center")
	assert_true(screen.find_child("Home", true, false) != null and screen.find_child("Away", true, false) != null)
	assert_eq(app.controller.season().games_played_count(), played_before, "looking does not play anything")
	var play := _find_button(app, "Play and watch the broadcast")
	assert_true(play != null)
	play.pressed.emit()
	await frames(3)
	assert_true(game.played, "Play and watch played the game")
	assert_true(app.controller.season().games_played_count() > played_before)
	assert_true(app.find_child("Summary", true, false) != null, "the Game Center now shows the summary")
	var replay := app.find_child("ReplayScreen", true, false) as FcReplayScreen
	assert_true(replay != null and replay.model.box.scores[0] == game.home_score and replay.model.box.scores[1] == game.away_score, "and the replay is that game")


func test_the_career_hub_previews_plays_and_lists_recent_games() -> void:
	await frames(2)
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var strong := ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]
	for key in spec["attributes"]:
		spec["attributes"][key] = 70 if strong.has(key) else 25
	assert_true(app.on_create_career(spec, 51))
	assert_true(app.career.join_team(app.career.state.world.teams.ids()[2])["ok"])
	var pending := app.career.pending_event()
	if not pending.is_empty():
		app.career.answer_event(pending["choices"][0]["key"])
	app.show_career_hub()
	await frames(2)
	var open_button := _find_button(app, "Game day")
	assert_true(open_button != null and not open_button.disabled, "the hub offers Game day")
	open_button.pressed.emit()
	await frames(2)
	assert_true(app.find_child("GameDayScreen", true, false) != null)
	(app.find_child("PlayGameButton", true, false) as Button).pressed.emit()
	await frames(3)
	assert_true(not app._career_log.is_empty(), "the game is in the career log")
	assert_true(_find_button(app, "Watch replay") != null, "the game summary offers the replay")
	app.show_career_hub()
	await frames(2)
	assert_true(app.find_child("GamePicker", true, false) != null, "recent games can be picked")
	var watch := app.find_child("WatchReplayButton", true, false) as Button
	assert_true(watch != null)
	watch.pressed.emit()
	await frames(3)
	assert_true(app.find_child("ReplayScreen", true, false) != null, "the hub opens the replay of a recent game")


func test_the_preview_fits_a_phone() -> void:
	var g := FcGameController.new_game(_world(), 5, FcGameState.MODE_OWNER, 1)
	g.advance_days(2)
	var model := FcGameDay.for_owner(g)
	host.size = Vector2(412, 800)
	var looks: Array = []
	for side in model["sides"]:
		var team: FcTeam = g.state.world.teams.get_by_id(int(side["team_id"]))
		looks.append(FcTeamLook.resolve(FcTeamLook.subject_for_team(g.state.world, team)))
	var screen := FcGameDayScreen.new().setup(model, looks, true)
	host.add_child(screen)
	await frames(3)
	assert_true(screen.get_combined_minimum_size().x <= 412.0, "the preview needs %d px of 412" % int(screen.get_combined_minimum_size().x))


func _world() -> FcWorldGenerator:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg)
