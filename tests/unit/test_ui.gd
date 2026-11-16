extends FcTestCase
## Smoke tests for the screens: build every screen and click through a game the way a player would.
## (They check that screens build and show real data; how they LOOK needs human eyes.)

const SAVE_DIR := "user://test_saves_ui"

var app: FcApp


func before_each() -> void:
	app = FcApp.new()
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func after_each() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(SAVE_DIR)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _trees(node: Node, out: Array = []) -> Array:
	if node is Tree:
		out.append(node)
	for c in node.get_children():
		_trees(c, out)
	return out


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text


func _start_small_game() -> void:
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Test League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])


func test_main_menu_builds() -> void:
	app.show_main_menu()
	assert_true("FULL COURT" in _labels_text(app))
	assert_eq(_trees(app).size(), 0, "no saved games yet, so no table")


func test_new_league_screen_builds_with_valid_choices() -> void:
	app.show_new_league()
	var structure: OptionButton = app._form["structure"]
	assert_true(structure.item_count > 0, "a layout is offered for the default size")
	var teams: OptionButton = app._form["teams"]
	assert_true(teams.item_count >= 20)
	assert_eq(teams.get_item_text(teams.selected), "30 teams")


func test_invalid_league_is_refused_with_a_message() -> void:
	assert_true(not app.on_create_league({"teams": 31}))
	assert_true("Cannot create" in app._message.text)


func test_creating_a_league_leads_to_team_choice() -> void:
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7"}))
	var trees := _trees(app)
	assert_eq(trees.size(), 1)
	assert_eq((trees[0] as Tree).get_root().get_child_count(), 8, "every team is listed")


func test_starting_a_game_shows_the_dashboard_with_all_tabs() -> void:
	_start_small_game()
	assert_true(app.controller != null)
	assert_eq(app._tabs.get_tab_count(), FcApp.TAB_NAMES.size())
	var text := _labels_text(app)
	assert_true("2026-10-20" in text and "Regular season" in text)


func test_every_tab_shows_data() -> void:
	_start_small_game()
	app.on_advance(14)
	for name in FcApp.TAB_NAMES:
		var tab := app.build_tab(name)
		assert_true(tab != null, name)
		var trees := _trees(tab)
		assert_true(not trees.is_empty() or name == "Overview" or name == "Trades", "%s has a table" % name)
		tab.free()
	var roster_tab := app.build_tab("Roster")
	var roster := _trees(roster_tab)[0] as Tree
	assert_true(roster.get_root().get_child_count() >= 13, "the roster lists the players")
	roster_tab.free()
	var standings_tab := app.build_tab("Standings")
	assert_eq(_trees(standings_tab).size(), 2, "one table per conference")
	standings_tab.free()
	var schedule_tab := app.build_tab("Schedule")
	var schedule := _trees(schedule_tab)[0] as Tree
	assert_true(schedule.get_root().get_child_count() > 10)
	var first := schedule.get_root().get_child(0)
	assert_true(first.get_text(4) != "", "played games show a result")
	schedule_tab.free()


func test_clicking_through_a_whole_season_and_into_the_next() -> void:
	_start_small_game()
	app.on_advance(7)
	assert_true(app.controller.state.current_date.to_iso() == "2026-10-27")
	app.on_sim_regular()
	assert_eq(app.controller.phase(), FcGameController.PHASE_PLAYOFFS)
	assert_true("Playoff" in _labels_text(app))
	app.on_sim_playoffs()
	assert_eq(app.controller.phase(), FcGameController.PHASE_COMPLETE)
	assert_true("Champions" in app._message.text)
	var overview := app.build_tab("Overview")
	assert_true("Champions:" in _labels_text(overview), "the overview names the champion")
	overview.free()
	app.on_next_season()
	assert_eq(app.controller.state.current_season, 2027)
	assert_true("New season" in app._message.text)
	assert_eq(app.controller.state.validate(), [] as Array[String])


func test_saving_and_loading_from_the_menu() -> void:
	_start_small_game()
	app.on_advance(10)
	app.on_save()
	assert_true("Saved" in app._message.text)
	var date_before := app.controller.state.current_date.to_iso()
	app.show_main_menu()
	assert_eq(_trees(app).size(), 1, "the saved game is listed")
	app.on_continue()
	assert_true(app.controller != null)
	assert_eq(app.controller.state.current_date.to_iso(), date_before)
	assert_true(_labels_text(app).contains("Regular season"))


func test_owner_can_change_prices_from_the_finance_tab() -> void:
	_start_small_game()
	assert_true(app.controller.set_ticket_price(180))
	var tab := app.build_tab("Finances")
	var text := _labels_text(tab)
	assert_true("Fan interest" in text and "Payroll" in text)
	var values := []
	var stack: Array = [tab]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SpinBox:
			values.append((n as SpinBox).value)
		stack.append_array(n.get_children())
	assert_eq(values.size(), 2, "price and marketing controls exist in Owner Mode")
	assert_true(values.has(180.0), "the ticket price field shows the current price")
	tab.free()


func test_dynasty_mode_hides_owner_controls() -> void:
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "mode": "dynasty"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	var tab := app.build_tab("Finances")
	var stack: Array = [tab]
	var found := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SpinBox:
			found += 1
		stack.append_array(n.get_children())
	assert_eq(found, 0)
	tab.free()


func test_staff_tab_lists_staff() -> void:
	_start_small_game()
	var tab := app.build_tab("Staff")
	var trees := _trees(tab)
	assert_true(trees.size() == 1 and (trees[0] as Tree).get_root().get_child_count() >= 2, "GM and head coach are listed")
	tab.free()


func test_money_formatting() -> void:
	assert_eq(FcUiTables.money(1500000), "$1.5M")
	assert_eq(FcUiTables.money(-250000), "-$250K")
	assert_eq(FcUiTables.money(2500000000), "$2.50B")
	assert_eq(FcUiTables.money(500), "$500")


func test_player_profile_text() -> void:
	_start_small_game()
	app.on_advance(20)
	var w := app.controller.state.world
	var team: FcTeam = w.teams.get_by_id(app.controller.state.user_team_id)
	var pid: int = team.roster.player_ids[0]
	var text := app.player_profile_text(pid)
	assert_true(w.players.get_by_id(pid).identity.full_name() in text)
	for needle in ["Basketball ratings", "Personality", "Tendencies", "Contract:", "Career", "Overall"]:
		assert_true(needle in text, needle)
	assert_true("Three-Point Shooting" in text and "Loyalty" in text)
	assert_eq(app.player_profile_text(999999), "")
	var roster_tab := app.build_tab("Roster")
	assert_true(roster_tab.get_child_count() == 2, "the roster has its table and the profile button")
	roster_tab.free()


func test_market_tab_lists_free_agents_and_draft() -> void:
	_start_small_game()
	app.controller.start_next_season()
	var tab := app.build_tab("Market")
	assert_true(tab is HBoxContainer and tab.get_child_count() == 2)
	tab.free()


func test_trades_tab_builds_and_a_trade_can_be_proposed() -> void:
	_start_small_game()
	var tab := app.build_tab("Trades")
	assert_true(tab is VBoxContainer and tab.get_child_count() >= 4)
	tab.free()
	var other := 1 if app.controller.state.user_team_id != 1 else 2
	var r := app.controller.propose_trade(other, [], [], true)
	assert_true(not r["accepted"])


func test_history_tab_builds() -> void:
	_start_small_game()
	app.on_advance(10)
	var tab := app.build_tab("History")
	assert_true(tab is HBoxContainer and tab.get_child_count() == 2)
	assert_true(not _trees(tab).is_empty())
	tab.free()
