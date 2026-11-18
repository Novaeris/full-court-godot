extends FcTestCase
## Career Mode phase 4: joining a team, playing days and a season, rewards from real box scores, history, save and resume, the
## badge bonus in the simulation, and proof that normal games are unchanged.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _career(seed_value: int = 51) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	# a strong build, so he plays and the box scores contain him
	for key in ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]:
		spec["attributes"][key] = 70
	for key in spec["attributes"]:
		if not key in ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]:
			spec["attributes"][key] = 25
	return FcCareerController.new_career(spec, seed_value)["controller"]


func _signed(seed_value: int = 51) -> FcCareerController:
	var c := _career(seed_value)
	assert_true(c.join_team(c.state.world.teams.ids()[2])["ok"])
	_decide(c)
	return c


## Answers the waiting career decision with its first choice (the career will not play on until it is answered).
func _decide(c: FcCareerController) -> void:
	var pending := c.pending_event()
	if not pending.is_empty():
		assert_true(c.answer_event(pending["choices"][0]["key"])["ok"])


# --- joining a team --------------------------------------------------------------------------------------------

func test_joining_a_team_gives_a_contract_a_roster_spot_and_a_valid_world() -> void:
	var c := _career()
	assert_true(not c.is_signed() and c.game() == null and c.advance_day()["ok"] == false)
	var team_id: int = c.state.world.teams.ids()[1]
	var team: FcTeam = c.state.world.teams.get_by_id(team_id)
	var size_before := team.roster.size()
	var rules := c.state.world.rules_of_league(c.state.world.league_of_team(team_id).id)
	var r := c.join_team(team_id)
	assert_true(r["ok"], r["reason"])
	assert_true(c.is_signed() and team.roster.contains(c.profile().player_id))
	assert_eq(c.state.user_team_id, team_id)
	var contract := c.state.world.active_contract_of(c.profile().player_id)
	assert_true(contract != null and contract.team_id == team_id and contract.length() == rules.cap.rookie_contract_years)
	assert_true(team.roster.size() <= rules.roster_max and team.roster.size() >= size_before)
	assert_eq(c.profile().stage, FcCareerProfile.Stage.PROFESSIONAL_ENTRY)
	assert_eq(c.state.validate(), [] as Array[String], str(c.state.validate()))
	assert_true(not c.join_team(team_id)["ok"], "a player with a team cannot sign again")
	assert_true(c.game() != null and not c.next_game().is_empty())


func test_the_draft_team_is_seeded_and_a_bad_team_is_refused() -> void:
	var a := _career(60)
	var b := _career(60)
	assert_eq(a.draft_team(), b.draft_team(), "the same career gives the same draft team")
	assert_true(not a.join_team(999999)["ok"])


# --- playing ---------------------------------------------------------------------------------------------------

func test_games_pay_career_rewards_from_real_box_scores_exactly_once() -> void:
	var c := _signed()
	var played: Array = []
	for i in 40:   # a few weeks: his team plays several times
		played.append_array(c.advance_day()["games"])
		if played.size() >= 3:
			break
	assert_true(played.size() >= 1, "the player appeared in a game of his team")
	var xp := c.profile().xp
	assert_true(xp > 0 and c.profile().milestones.has("first_game"))
	for game in played:
		assert_true(game["line"]["minutes"] > 0 and game["xp"] >= int(FcCareerRules.rules()["game_xp"]["floor"]))
	var total := 0
	for game in played:
		total += game["xp"]
	assert_true(xp >= total, "XP includes every game (plus milestones and level bonuses)")
	# nothing is paid twice: asking again without playing gives nothing
	assert_eq(c._collect_games(), [], "an already rewarded game is not paid again")
	assert_eq(c.profile().xp, xp)
	var week := c.advance_days(7)
	assert_true(week["ok"])
	var line := c.season_line()
	assert_true(int(line["games"]) >= played.size(), "the league's own statistics count his games")


func test_a_season_is_recorded_and_the_next_one_begins() -> void:
	var c := _signed()
	var year := c.state.current_season
	var result := c.finish_season()
	assert_true(result["ok"])
	assert_eq(c.state.current_season, year + 1, "the next season began")
	assert_eq(c.profile().history.size(), 1)
	var row: Dictionary = c.profile().history[0]
	assert_eq(row["year"], year)
	assert_true(row["games"] > 0 and row["wins"] + row["losses"] > 0)
	assert_true(c.profile().milestones.has("season_complete"))
	assert_true(c.is_signed(), "he is still on a team")
	assert_eq(c.state.validate(), [] as Array[String], str(c.state.validate()))
	assert_true(not c.finish_season()["ok"], "the new season starts with a decision to make")
	_decide(c)
	var again := c.finish_season()
	assert_true(again["ok"])
	assert_eq(c.profile().history.size(), 2)
	assert_eq(c.profile().history[1]["year"], year + 1)
	assert_eq(c.state.validate(), [] as Array[String])


func test_the_same_career_played_twice_is_identical() -> void:
	var a := _signed(70)
	var b := _signed(70)
	a.advance_days(30)
	b.advance_days(30)
	a.finish_season()
	b.finish_season()
	assert_eq(a.profile().checksum(), b.profile().checksum(), "deterministic: same seed and actions, same career")
	assert_eq(a.player().attributes.to_dict(), b.player().attributes.to_dict())


func test_save_and_resume_mid_season_does_not_pay_old_games_again() -> void:
	var c := _signed(80)
	c.advance_days(25)
	var xp := c.profile().xp
	var dir := "user://test_saves_career_season"
	var manager := FcSaveManager.new(dir)
	assert_true(c.save(manager).is_ok())
	var back := FcCareerController.resume(manager.load_slot("career_1", defs).state)
	assert_true(back.game() != null)
	assert_eq(back.advance_days(0)["games"], [], "nothing to reward right after loading")
	assert_eq(back.profile().xp, xp)
	assert_eq(back.profile().checksum(), c.profile().checksum())
	var more_c := c.advance_days(10)
	var more_b := back.advance_days(10)
	assert_eq(more_b["games"].size(), more_c["games"].size(), "the reloaded career plays on exactly like the original")
	assert_eq(back.profile().xp, c.profile().xp)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)


# --- the badge bonus and Owner Mode safety ---------------------------------------------------------------------

func test_equipped_badges_raise_only_the_career_players_composites() -> void:
	var c := _signed(90)
	var ratings := FcPlayerRatings.load_default()
	var pid := c.profile().player_id
	var team_id := c.state.user_team_id
	var plain := FcGameTeam.from_world(c.state.world, team_id, ratings)
	var boosted := FcGameTeam.from_world(c.state.world, team_id, ratings, {pid: {"three": 3, "block": 2}})
	for i in plain.players.size():
		var a: FcSimPlayer = plain.players[i]
		var b: FcSimPlayer = boosted.players[i]
		if a.id == pid:
			assert_eq(b.ratings["three"], minf(100.0, a.ratings["three"] + 3.0))
			assert_eq(b.ratings["block"], minf(100.0, a.ratings["block"] + 2.0))
			assert_eq(b.ratings["mid"], a.ratings["mid"], "other composites are untouched")
			assert_eq(b.overall, a.overall, "the overall rating never moves")
		else:
			assert_eq(b.ratings, a.ratings, "teammates and opponents are untouched")
	# through the controller: equipping sets the engine's bonuses, unequipping clears them
	c.profile().badges_owned = ["catch_and_shoot"]
	assert_true(c.equip_badge("catch_and_shoot", true)["ok"])
	assert_eq(c.game().engine.composite_bonuses, {pid: {"three": 2}})
	assert_true(c.equip_badge("catch_and_shoot", false)["ok"])
	assert_eq(c.game().engine.composite_bonuses, {})


func test_normal_games_are_bit_for_bit_unchanged_without_bonuses() -> void:
	var world := _career().state.world
	var ratings := FcPlayerRatings.load_default()
	var ids := world.teams.ids()
	var home_a := FcGameTeam.from_world(world, ids[0], ratings)
	var away_a := FcGameTeam.from_world(world, ids[1], ratings)
	var home_b := FcGameTeam.from_world(world, ids[0], ratings, {})
	var away_b := FcGameTeam.from_world(world, ids[1], ratings, {})
	var sim := FcGameSimulator.new()
	var first := sim.simulate(home_a, away_a, FcRng.new(7))
	var second := sim.simulate(home_b, away_b, FcRng.new(7))
	assert_eq(first.to_dict(), second.to_dict(), "an empty bonus changes nothing, down to the last box-score line")


func test_a_league_without_a_career_plays_the_same_season_as_before() -> void:
	# an Owner-style league played twice with the same seed gives identical standings: the career hooks add no randomness
	var results: Array = []
	for i in 2:
		var data := FcGenerationData.load_default()
		var cfg := FcGenerationConfig.load_default(data)
		cfg.team_count = 8
		cfg.conference_count = 2
		cfg.divisions_per_conference = 1
		var game := FcGameController.new_game(FcWorldGenerator.new(data, defs, cfg), 33, FcGameState.MODE_OWNER, 0)
		game.sim_playoffs()
		results.append(JSON.stringify(game.standings().records))
	assert_eq(results[0], results[1])


func test_the_hub_season_tab_plays_days_and_shows_results() -> void:
	var app := FcApp.new()
	app.saves = FcSaveManager.new("user://test_saves_career_hub")
	app.preferences = FcPreferences.new("user://test_preferences_career_hub.cfg")
	app.preferences.tutorial_done = true
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	assert_true(app.on_create_career(spec, 12))
	assert_true("do not have a team yet" in _labels_text(app), "a new career starts without a team")
	assert_true(app.career.join_team(app.career.draft_team())["ok"])
	app.show_career_hub()
	assert_true("A decision" in _labels_text(app), "the first decision is waiting")
	assert_true(not app.on_career_play(3)["ok"], "no playing before deciding")
	_decide(app.career)
	app.show_career_hub()
	assert_true("Next game" in _labels_text(app) and "Career history" in _labels_text(app))
	var result := app.on_career_play(14)
	assert_true(result["ok"])
	var after := app.on_career_finish_season()
	assert_true(after["ok"])
	assert_true(app.career.profile().history.size() == 1 and "Season %d finished" % after["summary"]["year"] in _labels_text(app))
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	var dir := DirAccess.open("user://test_saves_career_hub")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute("user://test_saves_career_hub")
	DirAccess.remove_absolute("user://test_preferences_career_hub.cfg")


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text


# --- found by the 20-season career playthrough ---------------------------------------------------------------------

func test_the_leagues_yearly_progression_cannot_push_attributes_past_the_ceilings() -> void:
	var c := _signed(95)
	var spec := FcPlayerBuild.spec_of(c.player(), c.profile().build_potential)
	var ceiling := FcPlayerBuild.attribute_ceiling("three_point", spec)
	c.player().attributes.set_value("three_point", 99)   # as if the league's growth had overshot
	assert_true(99 > ceiling)
	c.finish_season()
	assert_true(c.player().attributes.get_value("three_point") <= ceiling, "the ceiling is a hard limit after the offseason too")
	assert_eq(c.state.validate(), [] as Array[String])


func test_ceilings_come_from_the_potential_the_player_was_created_with() -> void:
	var c := _career(96)
	assert_eq(c.profile().build_potential, c.player().development.potential)
	var before := FcPlayerBuild.attribute_ceiling("blocks", FcPlayerBuild.spec_of(c.player(), c.profile().build_potential))
	c.player().development.potential = 40   # the league's aging lowers potential over the years
	var after := FcPlayerBuild.attribute_ceiling("blocks", FcPlayerBuild.spec_of(c.player(), c.profile().build_potential))
	assert_eq(after, before, "the career's limits do not shrink behind the player's back")
	assert_eq(FcCareerProfile.from_dict(c.profile().to_dict()).build_potential, c.profile().build_potential, "and it is saved")


func test_a_retired_player_ends_the_career_instead_of_being_signed_again() -> void:
	var c := _signed(97)
	c.advance_days(10)
	var pid := c.profile().player_id
	var team := c.state.world.team_of_player(pid)
	team.roster.remove(pid)
	c.state.world.active_contract_of(pid).status = FcContract.Status.TERMINATED
	c.player().status = FcPlayer.Status.RETIRED
	c.player().retired_season = c.state.current_season
	c._after_offseason()
	assert_true(c.is_retired())
	assert_eq(c.profile().stage, FcCareerProfile.Stage.LEGACY)
	assert_true(not c.is_signed(), "he is not put on a roster again")
	assert_true(not c.advance_day()["ok"] and not c.finish_season()["ok"] and "over" in c.advance_days(3)["reason"], "no more games after retirement")
	assert_eq(c.state.validate(), [] as Array[String], str(c.state.validate()))
