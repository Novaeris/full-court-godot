extends FcTestCase
## The redesigned Owner tabs (Phase F): they keep every column, number and action the old tables had ("nothing lost"), and use the shared parts
## (FcTable, team crests, portraits, rating badges). Also FcSparkline and the controller's read-only finance_series().

const SAVE_DIR := "user://test_saves_owner_ui"

var app: FcApp


func before_each() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences_owner_ui.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Owner UI League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(14)


func after_each() -> void:
	FcSafeFile.remove_tree(SAVE_DIR)
	DirAccess.remove_absolute("user://test_preferences_owner_ui.cfg")
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _find_all(node: Node, type: Variant, out: Array = []) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		_find_all(c, type, out)
	return out


func _texts(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	elif node is Button:
		text += "[" + (node as Button).text + "]\n"
	for c in node.get_children():
		text += _texts(c)
	return text


func _titles(table: FcTable) -> Array:
	return table.columns.map(func(c: Dictionary) -> String: return str(c["title"]))


# --- roster ---------------------------------------------------------------------------------------------------------

func test_the_roster_keeps_every_old_column_and_adds_the_contract_bar() -> void:
	var tab := app.build_tab("Roster")
	var table: FcTable = _find_all(tab, FcTable)[0]
	for old in ["Player", "Pos", "Age", "Height", "Ovr", "Pot", "Salary", "Thru", "PPG", "RPG", "APG", "MPG", "Health"]:
		assert_true(old in _titles(table), "the roster still has the %s column" % old)
	assert_true("Contract" in _titles(table), "and shows how much of each contract is played")
	tab.free()


func test_the_roster_lists_the_team_best_first_with_portraits_and_rating_badges() -> void:
	var tab := app.build_tab("Roster")
	var table: FcTable = _find_all(tab, FcTable)[0]
	var team: FcTeam = app.controller.state.world.teams.get_by_id(app.controller.state.user_team_id)
	assert_eq(table.row_count(), team.roster.player_ids.size(), "every player is listed")
	var ovrs: Array = table.rows.map(func(r: Dictionary) -> int: return int(r["overall"]))
	var sorted := ovrs.duplicate()
	sorted.sort()
	sorted.reverse()
	assert_eq(ovrs, sorted, "best player first, as before")
	assert_eq(table.columns[0]["kind"], "custom", "the first column is the portrait chip")
	assert_eq(table.columns[4]["kind"], "rating", "Ovr is a rating badge")
	tab.free()


func test_the_roster_actions_are_all_still_there_and_need_a_selection() -> void:
	var tab := app.build_tab("Roster")
	var text := _texts(tab)
	for expected in ["Extend contract of selected player", "Release selected player (pay half his salary)", "Player profile of selected player", "Extension $M", "years"]:
		assert_true(expected in text, "the roster offers: " + expected)
	for b in _find_all(tab, Button):
		if (b as Button).text == "Release selected player (pay half his salary)":
			var before: int = app.controller.state.world.teams.get_by_id(app.controller.state.user_team_id).roster.size()
			(b as Button).pressed.emit()
			assert_true(app._message.text.begins_with("Select"), "releasing with nothing selected only shows a hint")
			assert_eq(app.controller.state.world.teams.get_by_id(app.controller.state.user_team_id).roster.size(), before, "and releases nobody")
	tab.free()


func test_selecting_a_roster_row_selects_that_player() -> void:
	var tab := app.build_tab("Roster")
	var table: FcTable = _find_all(tab, FcTable)[0]
	var first_id: int = int(table.rows[0]["id"])
	table.select_id(first_id)
	assert_eq(table.selected_id, first_id)
	assert_eq(int(table.selected_row()["id"]), first_id)
	tab.free()


# --- standings, schedule --------------------------------------------------------------------------------------------

func test_standings_have_one_table_per_conference_with_a_team_column_and_the_users_team() -> void:
	var tab := app.build_tab("Standings")
	var tables := _find_all(tab, FcTable)
	assert_eq(tables.size(), 2, "one table per conference")
	var found := false
	for t in tables:
		for old in ["Team", "W", "L", "Pct", "GB", "L10", "Strk"]:
			assert_true(old in _titles(t), "standings column " + old)
		for r in t.rows:
			if int(r["id"]) == app.controller.state.user_team_id:
				found = true
	assert_true(found, "the user's team is listed")
	tab.free()


func test_the_schedule_lists_the_teams_games_with_results_and_a_box_score_button() -> void:
	var tab := app.build_tab("Schedule")
	var table: FcTable = _find_all(tab, FcTable)[0]
	for old in ["Date", "Round", "Opponent", "Result"]:
		assert_true(old in _titles(table), "schedule column " + old)
	assert_true(table.row_count() > 10)
	var played := table.rows.filter(func(r: Dictionary) -> bool: return str(r["result"]) != "")
	assert_true(played.size() > 0, "played games show a result")
	assert_true(str(played[0]["result"]).begins_with("W ") or str(played[0]["result"]).begins_with("L "), "the result carries a letter, never colour alone")
	assert_true("[Box score of selected game]" in _texts(tab))
	tab.free()


func test_the_box_score_button_asks_for_a_selection_first() -> void:
	var tab := app.build_tab("Schedule")
	for b in _find_all(tab, Button):
		if (b as Button).text == "Box score of selected game":
			(b as Button).pressed.emit()
	assert_eq(app._message.text, "Select a game first.")
	tab.free()


# --- overview -------------------------------------------------------------------------------------------------------

func test_the_overview_keeps_every_section_of_the_old_tab() -> void:
	var tab := app.build_tab("Overview")
	var text := _texts(tab).to_lower()
	for expected in ["Record", "League rank", "Games left", "Next game", "Your owner career", "Owner reputation", "League rules", "Salary cap"]:
		assert_true(expected.to_lower() in text, "the overview shows: " + expected)
	if not app.controller.state.world.news.is_empty():
		assert_true("latest news" in text, "and the news")
	assert_true(_find_all(tab, FcKpiStrip).size() >= 1)
	assert_true(_find_all(tab, FcTeamCrest).size() >= 2, "crests appear in the next-game card and the standings snapshot")
	tab.free()


func test_the_overview_shows_the_owner_report_and_the_approval_meter_after_a_season() -> void:
	app.on_sim_regular()
	app.on_sim_playoffs()
	var tab := app.build_tab("Overview")
	var text := _texts(tab).to_lower()
	assert_true("owner report" in text and "owner approval" in text and "profit" in text, "the owner report is shown")
	assert_true("champions:" in text, "the champion is named")
	assert_true(_find_all(tab, FcProgress).size() >= 1, "an approval meter")
	tab.free()


# --- the chart and the controller helper ------------------------------------------------------------------------------

func test_a_sparkline_draws_only_real_points() -> void:
	var one := FcSparkline.new([5])
	assert_true(not one.has_line(), "one point is not a trend")
	assert_eq(one.summary(), "")
	var many := FcSparkline.new([2, 5, 9], FcUiTokens.INFO, ["2024", "2025", "2026"], func(v) -> String: return "$%dM" % int(v))
	assert_true(many.has_line())
	assert_eq(many.summary(), "2024: $2M, 2025: $5M, 2026: $9M")
	assert_eq(many.tooltip_text, many.summary(), "the same numbers as text for accessibility")
	one.free()
	many.free()


func test_finance_series_gives_the_users_books_oldest_first() -> void:
	var before := app.controller.finance_series()
	app.on_sim_regular()
	app.on_sim_playoffs()
	var series := app.controller.finance_series()
	assert_true(series.size() >= before.size() and series.size() >= 1, "a settled season appears")
	for i in range(1, series.size()):
		assert_true(int(series[i]["year"]) > int(series[i - 1]["year"]), "oldest first")
	assert_true(series[-1].has("profit") and series[-1].has("valuation") and series[-1].has("wins"))
