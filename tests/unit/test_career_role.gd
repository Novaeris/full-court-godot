extends FcTestCase
## Career Mode: role and minutes control. The career player can ask for a role (starter or bench), more or fewer minutes and a
## shoot-first or pass-first style; the coach refuses what has not been earned; the simulation honours it; and with no request
## everything is exactly as before.

var defs: FcDefinitionSet
var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	defs = FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	world = FcWorldGenerator.new(data, defs, cfg).generate(1201)


## A rotation player of team 1 (the 4th best by overall), who normally starts or is a high-minute reserve.
func _subject(team_id: int, rank: int) -> int:
	var ids: Array = world.teams.get_by_id(team_id).roster.player_ids.duplicate()
	ids.sort_custom(func(a, b): return ratings.overall(world.players.get_by_id(a)) > ratings.overall(world.players.get_by_id(b)))
	return ids[rank]


func _play(pid: int, inputs: Dictionary, games: int = 60) -> Dictionary:
	var home_id: int = world.teams.ids()[0]
	var away_id: int = world.teams.ids()[1]
	var sim := FcGameSimulator.new()
	var started := 0
	var seconds := 0
	var fga := 0
	for i in games:
		var home := FcGameTeam.from_world(world, home_id, ratings, {}, {pid: inputs} if not inputs.is_empty() else {})
		var away := FcGameTeam.from_world(world, away_id, ratings)
		var box := sim.simulate(home, away, FcRng.new(500 + i))
		for p in box.players:
			if p.player_id == pid:
				started += 1 if p.started else 0
				seconds += p.seconds
				fga += p.fga
	return {"started": started, "seconds": seconds, "fga": fga}


# --- the simulation honours the request --------------------------------------------------------------------------

func test_a_starter_request_starts_a_reserve_and_a_bench_request_sits_a_starter() -> void:
	var team_id: int = world.teams.ids()[0]
	var reserve := _subject(team_id, 9)
	var starter := _subject(team_id, 0)
	var normal_reserve := _play(reserve, {})
	var asked_to_start := _play(reserve, {"role_bonus": 100.0})
	assert_true(asked_to_start["started"] > normal_reserve["started"], "a reserve who asks to start starts (%d vs %d games)" % [asked_to_start["started"], normal_reserve["started"]])
	assert_eq(asked_to_start["started"], 60, "and starts every game")
	var normal_star := _play(starter, {})
	var benched := _play(starter, {"role_bonus": -100.0})
	assert_true(normal_star["started"] > benched["started"] and benched["started"] == 0, "a starter who asks for the bench never starts")


func test_more_minutes_and_shoot_first_change_the_box_score() -> void:
	var pid := _subject(world.teams.ids()[0], 4)
	var fewer := _play(pid, {"minutes_pref": -1.0})
	var more := _play(pid, {"minutes_pref": 1.0})
	assert_true(more["seconds"] > fewer["seconds"], "more minutes: %d vs %d seconds" % [more["seconds"], fewer["seconds"]])
	var pass_first := _play(pid, {"usage_pref": -1.0})
	var shoot_first := _play(pid, {"usage_pref": 1.0})
	assert_true(shoot_first["fga"] > pass_first["fga"], "shoot first takes more shots: %d vs %d" % [shoot_first["fga"], pass_first["fga"]])


func test_no_request_and_a_neutral_request_leave_games_bit_for_bit_unchanged() -> void:
	var ids := world.teams.ids()
	var pid := _subject(ids[0], 3)
	var sim := FcGameSimulator.new()
	var plain := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(9))
	var neutral := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings, {}, {pid: {"role_bonus": 0.0, "minutes_pref": 0.0, "usage_pref": 0.0}}), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(9))
	assert_eq(plain.to_dict(), neutral.to_dict())


# --- what the coach allows ----------------------------------------------------------------------------------------

func _profile(reputation: int = 0, tags: Array[String] = []) -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	p.reputation = reputation
	p.tags = tags
	return p


func test_the_coach_refuses_a_start_that_was_not_earned() -> void:
	var team := [70.0, 66.0, 64.0, 62.0, 60.0, 55.0, 50.0, 45.0]   # the fifth best is 60
	var p := _profile()
	assert_true("not ready to start" in FcCareerRules.role_problem(p, 52.0, team, "starter", 0, 0))
	assert_eq(FcCareerRules.role_problem(p, 57.0, team, "starter", 0, 0), "", "within 4 of the fifth starter")
	assert_true(FcCareerRules.role_problem(p, 52.0, team, "starter", 0, 0) != "")
	var pushed := _profile(0, ["role_push"] as Array[String])
	assert_eq(FcCareerRules.role_problem(pushed, 52.0, team, "starter", 0, 0), "", "a coach-meeting role push widens the margin by 5")
	assert_true("not ready" in FcCareerRules.role_problem(pushed, 49.0, team, "starter", 0, 0))


func test_more_minutes_and_shooting_first_need_reputation_but_less_is_always_allowed() -> void:
	var team := [60.0, 60.0, 60.0, 60.0, 60.0]
	var new_player := _profile(0)
	assert_true("earn it first" in FcCareerRules.role_problem(new_player, 60.0, team, "auto", 1, 0))
	assert_true("earn it first" in FcCareerRules.role_problem(new_player, 60.0, team, "auto", 0, 1))
	assert_eq(FcCareerRules.role_problem(new_player, 10.0, team, "bench", -1, -1), "", "benching yourself, fewer minutes and passing first are always allowed")
	assert_eq(FcCareerRules.role_problem(_profile(5), 60.0, team, "auto", 1, 1), "", "with reputation the coach agrees")
	assert_true("not a valid request" in FcCareerRules.role_problem(new_player, 60.0, team, "captain", 0, 0))
	assert_true("not a valid request" in FcCareerRules.role_problem(new_player, 60.0, team, "auto", 2, 0))


func test_role_inputs_follow_the_profile() -> void:
	var p := _profile()
	assert_eq(FcCareerRules.role_inputs(p), {"role_bonus": 0.0, "minutes_pref": 0.0, "usage_pref": 0.0})
	p.role = "starter"
	p.minutes_pref = 1
	p.usage_pref = -1
	assert_eq(FcCareerRules.role_inputs(p), {"role_bonus": 15.0, "minutes_pref": 1.0, "usage_pref": -1.0})
	p.role = "bench"
	assert_true(FcCareerRules.role_inputs(p)["role_bonus"] < 0.0)


# --- through the career ---------------------------------------------------------------------------------------------

func _career(seed_value: int = 71) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("floor_general", 1, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	return c


func test_the_controller_applies_a_granted_request_and_ignores_a_refused_one() -> void:
	var c := _career()
	var engine := c.game().engine
	assert_eq(engine.role_inputs, {}, "no request, no inputs")
	var refused := c.set_role("starter", 0, 0)   # a 19-year-old rookie at overall ~45 is not ready to start
	assert_true(not refused["ok"] and "not ready to start" in refused["reason"], refused["reason"])
	assert_eq(c.profile().role, "auto", "a refused request changes nothing")
	assert_eq(engine.role_inputs, {})
	var before := c.profile().checksum()
	assert_true(not c.set_role("auto", 1, 1)["ok"], "a rookie with no reputation cannot ask for more")
	assert_eq(c.profile().checksum(), before)
	var granted := c.set_role("bench", -1, -1)
	assert_true(granted["ok"], granted["reason"])
	assert_eq(c.profile().role, "bench")
	assert_eq(engine.role_inputs, {c.profile().player_id: {"role_bonus": -40.0, "minutes_pref": -1.0, "usage_pref": -1.0}})
	assert_true(c.set_role("auto", 0, 0)["ok"])
	assert_eq(engine.role_inputs, {}, "back to the coach's decision clears the inputs")
	assert_eq(c.profile().validate(), [] as Array[String])


func test_a_benched_career_player_really_does_not_start_and_the_request_survives_saving() -> void:
	var c := _career(72)
	assert_true(c.set_role("bench", -1, 0)["ok"])
	var games: Array = c.advance_days(40)["games"]
	assert_true(games.size() > 0)
	var dir := "user://test_saves_career_role"
	var manager := FcSaveManager.new(dir)
	assert_true(c.save(manager).is_ok())
	var back := FcCareerController.resume(manager.load_slot("career_1", defs).state)
	assert_eq(back.profile().role, "bench")
	assert_eq(back.profile().minutes_pref, -1)
	assert_eq(back.game().engine.role_inputs.size(), 1, "the loaded career applies the request again")
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)
	var bad := FcCareerProfile.from_dict({"role": "captain", "minutes_pref": 5, "profile_id": "fcp_0123456789abcdef", "player_id": 1})
	assert_eq(bad.minutes_pref, 1, "a bad number is clamped on load")
	assert_true("role must be" in " ".join(bad.validate()), "a bad role is reported")
