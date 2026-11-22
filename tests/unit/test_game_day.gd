extends FcTestCase
## The game-day preview (Phase 2D): the model of the user's next game, and above all that the preview agrees with the game: the five
## it projects are the five who start, the records are the standings, injured players are listed and left out.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _owner(seed_value: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcGameController.new_game(FcWorldGenerator.new(data, defs, cfg), seed_value, FcGameState.MODE_OWNER, 1)


func _ids_of(side: Dictionary) -> Array:
	var ids: Array = []
	for p in side["starters"]:
		ids.append(p["id"])
	ids.sort()
	return ids


func test_the_preview_describes_the_next_game() -> void:
	var g := _owner()
	g.advance_days(6)
	var game := g.next_user_game()
	var model := FcGameDay.for_owner(g)
	assert_true(not model.is_empty() and game != null)
	assert_eq(model["sides"][0]["team_id"], game.home_id, "side 0 is the home team")
	assert_eq(model["sides"][1]["team_id"], game.away_id)
	assert_eq(model["sides"][model["user_side"]]["team_id"], g.state.user_team_id, "the user's side is marked")
	assert_eq(model["date"], g.season().date_of_day(game.day).to_iso())
	var st := g.standings()
	for side in model["sides"]:
		assert_eq((side["starters"] as Array).size(), 5)
		assert_eq(side["record"], "%d-%d" % [st.records[side["team_id"]]["w"], st.records[side["team_id"]]["l"]], "the record is the standings")
		assert_eq(side["rank"], st.league_ranking().find(side["team_id"]) + 1)
		assert_true(side["overall"] > 20 and side["overall"] < 100)
		assert_eq(side["name"], g.state.world.team_display_name(side["team_id"]))
		var seen := {}
		for p in side["starters"]:
			assert_true(not seen.has(p["id"]), "five different players")
			seen[p["id"]] = true
			assert_true(["PG", "SG", "SF", "PF", "C"].has(p["position"]))
			assert_true(p["name"].contains("."), "short names")


func test_the_projected_starters_are_the_ones_who_start() -> void:
	var g := _owner(21)
	g.advance_days(2)
	var checked := 0
	for round in 6:
		while g.next_user_game() != null and g.days_to_next_user_game() > 1:
			g.advance_day()   # the preview is made on the morning of the game
		var game := g.next_user_game()
		if game == null:
			break
		var model := FcGameDay.for_owner(g)
		var day := game.day
		g.advance_day()
		var entry := {}
		for e in g.season().recent_boxes:
			if int(e["day"]) == day and int(e["series"]) == 0:
				entry = e
		assert_true(not entry.is_empty(), "the game was played and stored")
		var box := FcBoxScore.from_dict(entry["box"])
		for side in 2:
			var started: Array = []
			for p in box.players_of(side):
				if p.started:
					started.append(p.player_id)
			started.sort()
			assert_eq(started, _ids_of(model["sides"][side]), "game %d side %d: the preview named the five who started" % [round, side])
		checked += 1
	assert_true(checked >= 4, "checked %d games" % checked)


func test_days_to_the_next_game_plays_exactly_up_to_it() -> void:
	var g := _owner()
	assert_true(g.days_to_next_user_game() >= 1)
	var first := g.next_user_game()
	g.advance_days(g.days_to_next_user_game())
	assert_true(first.played, "the game itself was played")
	var second := g.next_user_game()
	assert_true(second != first and second.day > first.day)
	g.sim_regular_season()
	assert_eq(g.days_to_next_user_game(), 0, "no game left, no days")
	assert_eq(FcGameDay.for_owner(g), {}, "and no preview")


func test_an_injured_player_is_listed_and_does_not_start() -> void:
	var g := _owner(33)
	g.advance_days(3)
	var game := g.next_user_game()
	var mine: FcTeam = g.state.world.teams.get_by_id(g.state.user_team_id)
	var best_id := 0
	var best := -1.0
	var ratings := FcPlayerRatings.load_default()
	for pid in mine.roster.player_ids:
		var p: FcPlayer = g.state.world.players.get_by_id(pid)
		if ratings.overall(p) > best:
			best = ratings.overall(p)
			best_id = pid
	var star: FcPlayer = g.state.world.players.get_by_id(best_id)
	star.games_out = 4
	star.injury = "sprained ankle"
	g.engine.refresh_teams()
	var model := FcGameDay.for_owner(g)
	var me: Dictionary = model["sides"][model["user_side"]]
	var out_names: Array = []
	for o in me["out"]:
		out_names.append(o["name"])
	assert_true(out_names.has(FcPlayByPlay.short_name(star.identity.full_name())), "the injured star is listed as out")
	assert_true(not _ids_of(me).has(best_id), "and he is not in the projected five")
	assert_true(game != null)


func test_a_career_team_gets_a_preview_too() -> void:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var strong := ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]
	for key in spec["attributes"]:
		spec["attributes"][key] = 70 if strong.has(key) else 25
	var c: FcCareerController = FcCareerController.new_career(spec, 51)["controller"]
	assert_true(c.join_team(c.state.world.teams.ids()[2])["ok"])
	var model := FcGameDay.for_owner(c.game())
	assert_true(not model.is_empty())
	assert_eq(model["sides"][model["user_side"]]["team_id"], c.state.user_team_id)


func test_the_simulator_exposes_the_starters_it_would_pick() -> void:
	var g := _owner()
	var team := FcGameTeam.from_world(g.state.world, g.state.user_team_id, FcPlayerRatings.load_default())
	var five := FcGameSimulator.new().projected_starters(team)
	assert_eq(five.size(), 5)
	for p in five:
		assert_true(team.players.has(p), "each is from this team")
