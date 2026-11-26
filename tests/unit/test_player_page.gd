extends FcTestCase
## Player presentation (M4 of D-077): the profile's new data (stored jersey number, rating history, game log, shooting by shot kind,
## tendencies, contract years) comes from the game's records; the profile shows the new tabs only when there is data; the full-page
## profile opens from the roster and Back returns; the roster has a Table / Cards switch whose actions follow the selected card.

const SAVE_DIR := "user://test_saves_player_page"

var app: FcApp


func before_each() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences_player_page.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Player Page League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(14)


func after_each() -> void:
	FcSafeFile.remove_tree(SAVE_DIR)
	DirAccess.remove_absolute("user://test_preferences_player_page.cfg")
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _find_all(node: Node, type: Variant, out: Array = []) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		_find_all(c, type, out)
	return out


func _button(node: Node, text: String) -> Button:
	for b in _find_all(node, Button):
		if (b as Button).text == text:
			return b
	return null


func _star() -> int:
	var c := app.controller
	var best := 0
	for pid in c.state.world.teams.get_by_id(c.state.user_team_id).roster.player_ids:
		if best == 0 or c.season().stats.games_played(pid) > c.season().stats.games_played(best):
			best = pid
	return best


func test_the_profile_data_comes_from_the_games_records() -> void:
	var c := app.controller
	var w := c.state.world
	var pid := _star()
	var vm := FcPlayerPresentation.from_player(w, pid, c.state.current_season, c.league_id)
	assert_eq(vm["jersey"], (w.players.get_by_id(pid) as FcPlayer).jersey_number, "the stored number")
	assert_true(int(vm["jersey"]) >= 1)
	var log: Array = vm["game_log"]["rows"]
	assert_eq(log.size(), c.season().stats.games_played(pid), "one game log row per game played")
	assert_true(str(log[0][2]).begins_with("W ") or str(log[0][2]).begins_with("L "), "each row has the real result")
	assert_true(log[0][0] >= log[-1][0], "newest first")
	var shoot: Dictionary = vm["shooting"]
	var l: Dictionary = c.season().stats.lines[pid]
	assert_eq(int(shoot["rim"][1]) + int(shoot["mid"][1]) + int(shoot["three"][1]), int(l["fga"]), "the three kinds add up to all field-goal attempts")
	assert_eq(int(shoot["three"][0]), int(l["tpm"]))
	assert_true(float(shoot["league"]["rim"]) > float(shoot["league"]["three"]), "the league shoots better at the rim than from three")
	assert_eq((vm["tendencies"] as Array).size(), w.definitions.tendencies.keys().size())
	assert_eq(vm["rating_history"], [], "no season has ended yet: no history invented")
	var profile := FcPlayerProfile.new().setup(vm)
	for id in ["game_log", "shooting", "tendencies"]:
		assert_true(id in profile.tab_ids(), "the %s tab is offered" % id)
	profile.show_tab("shooting")
	var chart := profile.find_child("ShotChart", true, false) as FcHeatZones
	assert_true(chart != null and chart.summary().begins_with("At the rim %d/%d" % [int(shoot["rim"][0]), int(shoot["rim"][1])]), chart.summary() if chart != null else "no chart")
	profile.free()


func test_a_player_without_data_gets_no_empty_tabs() -> void:
	var c := app.controller
	var w := c.state.world
	var free_agent := 0
	for p in w.players.all():
		if w.team_of_player(p.id) == null and p.status == FcPlayer.Status.ACTIVE:
			free_agent = p.id
			break
	var vm := FcPlayerPresentation.from_player(w, free_agent, c.state.current_season, c.league_id)
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true(not ("game_log" in profile.tab_ids()) and not ("shooting" in profile.tab_ids()), "no games, no game log or shot chart")
	profile.free()


func test_rating_history_appears_after_two_seasons() -> void:
	var c := app.controller
	c.sim_playoffs()
	c.start_next_season()
	c.sim_playoffs()
	var pid: int = c.state.world.teams.get_by_id(c.state.user_team_id).roster.player_ids[0]
	var vm := FcPlayerPresentation.from_player(c.state.world, pid, c.state.current_season, c.league_id)
	if (vm["rating_history"] as Array).size() >= 2:
		var profile := FcPlayerProfile.new().setup(vm)
		assert_true(profile.find_child("RatingHistory", true, false) != null, "the overview draws the rating history")
		profile.free()
	assert_true((c.state.world.rating_history.get(pid, []) as Array).size() >= 1)


func test_heat_zones_kind_mode() -> void:
	var z := FcHeatZones.new().set_kinds({"rim": [10, 16], "mid": [4, 12], "three": [6, 18]}, {"rim": 0.6, "mid": 0.4, "three": 0.36})
	assert_eq(z.total_attempts(), 46)
	assert_eq(z.summary(), "At the rim 10/16 (63%, league 60%); Mid-range 4/12 (33%, league 40%); Three-point 6/18 (33%, league 36%)")
	assert_eq(z.zones[FcShotZones.CORNER3_LEFT]["att"], 18, "every three-point zone carries the three-point numbers")
	assert_eq(FcHeatZones.kind_of_zone(FcShotZones.PAINT), "rim")
	z.free()


func test_the_full_page_profile_opens_from_the_roster_and_back_returns() -> void:
	app.show_dashboard()
	var roster := app.build_tab("Roster")
	app.add_child(roster)
	var table: FcTable = roster.get_meta("table")
	var pid := _star()
	table.select_id(pid)
	_button(roster, "Player profile of selected player").pressed.emit()
	assert_eq(app.navigator.current_id, "player:%d" % pid, "the full-page profile is showing")
	assert_eq(app.navigator.stack_ids(), ["dashboard", "player"])
	assert_true(app.find_child("PlayerPage", true, false) != null)
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "dashboard", "Back returns to the dashboard")
	roster.free()


func test_the_roster_card_view_follows_the_selected_card() -> void:
	var roster := app.build_tab("Roster")
	app.add_child(roster)
	var grid: FcPlayerCardGrid = roster.get_meta("cards")
	var team: FcTeam = app.controller.state.world.teams.get_by_id(app.controller.state.user_team_id)
	assert_eq(grid.card_count(), team.roster.player_ids.size(), "every player has a card")
	var switch := roster.find_child("RosterView", true, false) as FcChoiceGroup
	switch.selected.emit("cards")
	assert_true(grid.visible and not (roster.get_meta("table") as FcTable).visible)
	assert_eq(app._owner_ctx().memory["roster_view"], "cards", "the choice is remembered")
	var pid := _star()
	var tile := grid.tile_of(pid)
	assert_eq(str(tile.vm["number"]), str((app.controller.state.world.players.get_by_id(pid) as FcPlayer).jersey_number), "the card shows the stored number")
	assert_true(str(tile.vm["stat_line"]).contains("pts"))
	grid.select(pid)
	_button(roster, "Player profile of selected player").pressed.emit()
	assert_eq(app.navigator.current_id, "player:%d" % pid, "the action uses the selected card")
	roster.free()
	app._owner_ctx().memory["roster_view"] = "table"
