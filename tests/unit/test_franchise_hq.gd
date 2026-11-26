extends FcTestCase
## The franchise headquarters (M3 of D-077): every number of FcFranchiseSnapshot comes from the live game (standings, statistics, the real
## playoff builder, stored result lines, objectives, books), and the HQ shows them with a featured matchup that opens the game.


func _game(seed_value: int = 31) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_the_snapshot_before_any_game_invents_nothing() -> void:
	var g := _game()
	var snap := FcFranchiseSnapshot.build(g)
	assert_eq(snap["form"], [])
	assert_eq(snap["leaders"], [], "no leaders before a game")
	assert_true(not snap.has("last_game"))
	assert_true(not snap["playoff"]["qualifies"], "no playoff position before a game")
	assert_true(snap["objectives"].size() >= 2)
	assert_true(not snap["money"]["has_books"], "no settled books in the first season")


func test_the_snapshot_matches_the_games_own_records() -> void:
	var g := _game()
	g.advance_days(30)
	var snap := FcFranchiseSnapshot.build(g)
	var st := g.standings()
	var user := g.state.user_team_id
	assert_eq(snap["record"]["wins"], st.records[user]["w"])
	var results: Array = st.records[user]["results"]
	assert_eq(snap["form"], results.slice(maxi(0, results.size() - 10)))
	assert_eq(snap["last_ten"], st.last_ten(user))
	var po := FcPlayoffBuilder.build(g.state.world.leagues.get_by_id(g.league_id), st, g.state.world.rules_of_league(g.league_id).playoffs)
	assert_eq(snap["playoff"]["qualifies"], po.qualified(user), "the playoff position is the real builder's answer")
	for l in snap["leaders"]:
		var pid := int(l["player"])
		assert_eq(g.state.world.team_of_player(pid).id, user)
		for other in g.state.world.teams.get_by_id(user).roster.player_ids:
			if g.season().stats.games_played(other) > 0:
				assert_true(g.season().stats.per_game(other, l["stat"]) <= float(l["value"]) + 0.0001, "the leader really leads")
	var last: Dictionary = snap["last_game"]
	var game := g.season().game_by_id(int(last["game_id"]))
	assert_true(game.played and game.involves(user))
	assert_eq(int(last["pog"]), int(game.line["pog"]), "the player of the game is the stored one")
	for key in ["offense", "defense", "net"]:
		assert_true(int(snap["ranks"][key]["rank"]) >= 1 and int(snap["ranks"][key]["rank"]) <= int(snap["ranks"][key]["of"]))
	assert_eq(snap["money"]["payroll"], g.state.world.payroll_of_team(user, g.contract_year()))
	for o in snap["objectives"]:
		assert_true(str(o["progress"]) != "", "open objectives show their progress")


func test_the_headquarters_shows_the_matchup_and_opens_the_game() -> void:
	FcUiTheme.build(1)
	var g := _game()
	g.advance_days(8)
	var opened: Array = []
	var ctx := FcOwnerContext.new(g)
	ctx.open_game = func(id: int) -> void: opened.append(id)
	var hq := FcOwnerHq.build(ctx)
	Engine.get_main_loop().root.add_child(hq)
	var banner := hq.find_child("FeaturedMatchup", true, false) as FcMatchupBanner
	assert_true(banner != null, "the next game is featured")
	assert_true(banner.tooltip_text.contains(g.state.world.team_display_name(g.state.user_team_id)))
	banner.activated.emit()
	assert_eq(opened, [g.next_user_game().id], "clicking it opens that game")
	var text := _texts(hq)
	for expected in ["Next game", "Standing", "Team leaders", "Last game", "League ranks", "Latest news", "Owner objectives", "Business"]:
		assert_true(text.contains(expected), "the HQ shows " + expected)
	Engine.get_main_loop().root.remove_child(hq)
	hq.free()


func _texts(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	if node is Button:
		out += (node as Button).text + "\n"
	if node is FcKpiStrip or node is FcPanel:
		out += str(node.tooltip_text) + "\n"
	for c in node.get_children():
		out += _texts(c)
	return out
