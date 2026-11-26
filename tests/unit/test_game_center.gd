extends FcTestCase
## The Game Center (M5 of D-077): one screen per game whose actions are exactly what the stored data allows (FcGameAvailability), a preview
## before and a summary after (the full summary when the box score was kept, the stored result line otherwise), the controller's
## follow_game and play_through_game, and the routes from the schedule, the HQ and the Game day button.

const SAVE_DIR := "user://test_saves_game_center"

var app: FcApp


func before_each() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences_game_center.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "9", "name": "Game Center League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[1])
	app.on_advance(6)


func after_each() -> void:
	FcSafeFile.remove_tree(SAVE_DIR)
	DirAccess.remove_absolute("user://test_preferences_game_center.cfg")
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var b := _button(c, text)
		if b != null:
			return b
	return null


func _other_future_game() -> FcScheduledGame:
	var s := app.controller.season()
	for g in s.games:
		if not g.played and not g.involves(app.controller.state.user_team_id) and g.day > s.next_day + 1:
			return g
	return null


func test_the_next_user_game_offers_play_and_watch_and_a_preview() -> void:
	var game := app.controller.next_user_game()
	app.navigator.open("game", {"id": game.id})
	assert_eq(app.navigator.current_id, "game:%d" % game.id)
	var center := app.find_child("GameCenter", true, false)
	var buttons := _buttons(center)
	assert_true("Play and watch the broadcast" in buttons and "Simulate this game" in buttons)
	assert_true(not ("Watch the replay" in buttons), "nothing to replay before the game")
	assert_true(center.find_child("GameDayScreen", true, false) != null, "the preview is shown")
	var played := app.controller.season().games_played_count()
	assert_eq(app.controller.season().games_played_count(), played, "opening the Game Center plays nothing")


func test_simulating_from_the_game_center_shows_the_summary() -> void:
	var game := app.controller.next_user_game()
	app.navigator.open("game", {"id": game.id})
	_button(app.find_child("GameCenter", true, false), "Simulate this game").pressed.emit()
	assert_true(game.played)
	var center := app.find_child("GameCenter", true, false)
	assert_true(center.find_child("Summary", true, false) != null, "the full summary (the box score was kept)")
	assert_true("Watch the replay" in _buttons(center))
	assert_eq(app.navigator.stack_ids(), ["dashboard", "game"], "simulating rebuilds the same screen")
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "dashboard")


func test_another_teams_game_can_be_followed_and_is_then_recorded() -> void:
	var game := _other_future_game()
	app.navigator.open("game", {"id": game.id})
	var center := app.find_child("GameCenter", true, false)
	var buttons := _buttons(center)
	assert_true("Follow this game (record it)" in buttons)
	assert_true(not ("Play and watch the broadcast" in buttons), "another teams' game cannot be watched live")
	_button(center, "Follow this game (record it)").pressed.emit()
	assert_true(app.controller.season().followed.has(game.id))
	assert_true(not app.controller.follow_game(game.id), "following twice is refused")
	app.controller.play_through_game(game.id)
	assert_true(game.played)
	app.navigator.open("game", {"id": game.id})
	center = app.find_child("GameCenter", true, false)
	assert_true("Watch the replay" in _buttons(center), "a followed game has its replay")


func test_an_unrecorded_game_shows_only_its_result_line() -> void:
	var s := app.controller.season()
	var played: FcScheduledGame = null
	for g in s.games:
		if g.played and not g.involves(app.controller.state.user_team_id) and not s.followed.has(g.id):
			played = g
			break
	app.navigator.open("game", {"id": played.id})
	var center := app.find_child("GameCenter", true, false)
	assert_true(center.find_child("ResultLine", true, false) != null, "the stored line (periods, top scorers, player of the game)")
	assert_true(center.find_child("Summary", true, false) == null, "no summary is invented")
	assert_true(not ("Watch the replay" in _buttons(center)))


func test_play_through_game_uses_the_day_by_day_path() -> void:
	var c := app.controller
	var game := _other_future_game()
	var before := c.season().next_day
	var entry := c.play_through_game(game.id)
	assert_true(game.played)
	assert_eq(c.season().next_day, game.day + 1, "it stops right after the game's day")
	assert_true(c.season().next_day > before)
	assert_eq(entry, {}, "an unfollowed game of other teams keeps no box score")
	assert_eq(c.play_through_game(game.id), {}, "a played game is not played again")
	assert_eq(FcSimIntegrity.check(c.state), [] as Array[String])


func test_the_schedule_and_the_game_day_button_open_the_game_center() -> void:
	app.show_dashboard()
	var tab := app.build_tab("Schedule")
	app.add_child(tab)
	var table: FcTable = tab.get_meta("table")
	table.select_id(0)
	_button(tab, "Open in Game Center").pressed.emit()
	assert_true(app.navigator.current_id.begins_with("game:"), "the schedule opens the Game Center")
	tab.free()
	app.show_dashboard()
	_button(app, "Game day").pressed.emit()
	assert_eq(app.navigator.current_id, "game:%d" % app.controller.next_user_game().id)
