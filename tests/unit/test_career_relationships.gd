extends FcTestCase
## Career Mode: relationships with the coach and teammates, and what they change.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile() -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	return p


func _career(seed_value: int = 91) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	return c


func test_a_season_moves_trust_and_chemistry_by_rank_games_wins_and_tags() -> void:
	var p := _profile()
	var good := FcCareerRules.relationships_after_season(p, {"rank": 2, "win_pct": 0.7, "games": 30})
	assert_eq(good, {"coach_trust": 3, "chemistry": 3, "development_points": 0})
	assert_eq([p.coach_trust, p.chemistry], [53, 53])
	var bad := _profile()
	var worse := FcCareerRules.relationships_after_season(bad, {"rank": 12, "win_pct": 0.3, "games": 4})
	assert_eq(worse["coach_trust"], -4, "below the rotation and barely playing")
	assert_eq(worse["chemistry"], -2, "a losing team")
	var tagged := _profile()
	tagged.tags = ["role_push", "hardball", "outspoken", "community"] as Array[String]
	var r := FcCareerRules.relationships_after_season(tagged, {"rank": 4, "win_pct": 0.5, "games": 30})
	assert_eq(r["coach_trust"], 3 - 1 - 1, "pushing and hard bargaining cost the coach's trust")
	assert_eq(r["chemistry"], 2 - 2, "community work and an outspoken streak cancel")


func test_relationships_stay_within_zero_and_a_hundred_and_a_close_team_earns_a_point() -> void:
	var p := _profile()
	p.coach_trust = 99
	p.chemistry = 69
	var up := FcCareerRules.relationships_after_season(p, {"rank": 1, "win_pct": 0.8, "games": 34})
	assert_eq(p.coach_trust, 100)
	assert_eq(p.chemistry, 72)
	assert_eq(up["development_points"], 1)
	assert_eq(p.development_points, 1, "a close team (chemistry 70+) grants a development point")
	var low := _profile()
	low.coach_trust = 1
	low.chemistry = 0
	FcCareerRules.relationships_after_season(low, {"rank": 12, "win_pct": 0.2, "games": 0})
	assert_eq([low.coach_trust, low.chemistry], [0, 0])
	assert_eq(low.validate(), [] as Array[String])


func test_trust_changes_what_the_coach_allows_and_how_hard_the_agent_can_push() -> void:
	var team := [70.0, 66.0, 64.0, 62.0, 60.0, 55.0]   # fifth starter: 60
	var cold := _profile()
	cold.coach_trust = 10
	var warm := _profile()
	warm.coach_trust = 90
	assert_true(FcCareerRules.role_problem(cold, 57.0, team, "starter", 0, 0) != "", "a doubting coach wants more: 57 is not enough")
	assert_eq(FcCareerRules.role_problem(warm, 57.0, team, "starter", 0, 0), "")
	assert_eq(FcCareerRules.role_problem(warm, 52.0, team, "starter", 0, 0), "", "a trusting coach gives a start 8 points under his fifth")
	assert_true(FcCareerRules.role_problem(warm, 50.0, team, "starter", 0, 0) != "", "but not unlimited")
	var cap := FcCapRules.from_preset("soft_cap_with_hard_limit", 140000000, FcCapRules.load_presets())
	var deep := [70.0, 66.0, 64.0, 62.0, 60.0, 58.0, 56.0, 54.0, 50.0]
	assert_true(FcCareerRules.contract_terms(warm, 10000000, 74.0, deep, 3, cap)["max_salary"] > FcCareerRules.contract_terms(cold, 10000000, 74.0, deep, 3, cap)["max_salary"], "a coach who trusts him backs a bigger deal")


func test_a_finished_season_scores_the_relationships_once_even_across_saving() -> void:
	var c := _career()
	assert_eq(c.relationships()["coach_trust"], 50)
	var year := c.state.current_season
	var result := c.finish_season()
	assert_true(result["ok"])
	assert_eq(c.profile().relationships_year, year)
	assert_true(result["summary"].has("trust_change") and result["summary"].has("chemistry_change"), "the season summary records the change")
	# a retried finish of an already scored season must not score it again
	c.profile().relationships_year = c.state.current_season - 1
	var trust := c.profile().coach_trust
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_eq([back.coach_trust, back.chemistry, back.relationships_year], [trust, c.profile().chemistry, c.state.current_season - 1])
	var labels := c.relationships()
	assert_true(labels["coach_label"] in ["Trusted", "Neutral", "Doubtful"] and labels["chemistry_label"] in ["Close-knit", "Fine", "Strained"])
	assert_eq(c.state.validate(), [] as Array[String])


func test_the_same_career_builds_the_same_relationships() -> void:
	var a := _career(92)
	var b := _career(92)
	for i in 3:
		a.finish_season()
		b.finish_season()
		for c in [a, b]:
			if not c.pending_event().is_empty():
				c.answer_event(c.pending_event()["choices"][0]["key"])
			var talks: Dictionary = c.contract_offer()
			if not talks.is_empty():
				c.answer_contract("accept")
				c.finish_season()
	assert_eq(a.profile().checksum(), b.profile().checksum())
	assert_eq(a.relationships(), b.relationships())
