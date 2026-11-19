extends FcTestCase
## Career Mode phase 5: contract talks. When the player's contract ends, the season does not roll over until he decides; his agent
## and reputation decide how far he can push; the league's AI never re-signs him behind his back.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _career(seed_value: int = 81, agent_tag: String = "") -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	if agent_tag != "":
		c.profile().tags.append(agent_tag)
	return c


## A career whose contract ends this season (the rookie deal is cut to the current year).
func _expiring(seed_value: int = 81, agent_tag: String = "") -> FcCareerController:
	var c := _career(seed_value, agent_tag)
	var contract := c.state.world.active_contract_of(c.profile().player_id)
	var year := c.state.current_season
	contract.years = [contract.years[0]]
	assert_eq(contract.end_season(), year)
	return c


func _cap() -> FcCapRules:
	return FcCapRules.from_preset("soft_cap_with_hard_limit", 140000000, FcCapRules.load_presets())


# --- the rules --------------------------------------------------------------------------------------------------

func test_the_offer_scales_with_rotation_rank_and_the_agent_and_reputation_raise_the_ceiling() -> void:
	var cap := _cap()
	var p := FcCareerProfile.new()
	var team := [70.0, 66.0, 64.0, 62.0, 60.0, 58.0, 56.0, 54.0, 50.0]   # the eighth best is 54
	var star := FcCareerRules.contract_terms(p, 10000000, 74.0, team, 3, cap)
	var fringe := FcCareerRules.contract_terms(p, 10000000, 50.0, team, 3, cap)
	assert_true(star["salary"] > fringe["salary"], "a clear rotation player gets more of his market value")
	assert_between(float(fringe["salary"]) / 10000000.0, 0.89, 0.91)
	assert_between(float(star["salary"]) / 10000000.0, 1.09, 1.11)
	assert_eq(star["years"], 3)
	assert_true(star["max_salary"] >= star["salary"])
	var base_ceiling: int = star["max_salary"]
	p.tags = ["agent_flashy"] as Array[String]
	assert_true(FcCareerRules.contract_terms(p, 10000000, 74.0, team, 3, cap)["max_salary"] > base_ceiling, "a flashy agent pushes harder")
	p.tags = [] as Array[String]
	p.reputation = 80
	assert_true(FcCareerRules.contract_terms(p, 10000000, 74.0, team, 3, cap)["max_salary"] > base_ceiling, "reputation helps")
	assert_eq(FcCareerRules.contract_terms(p, 1000, 74.0, team, 3, cap)["salary"], cap.min_player_salary, "never below the league minimum")
	assert_eq(FcCareerRules.contract_terms(p, 900000000, 74.0, team, 3, cap)["salary"], cap.max_player_salary, "never above the maximum")
	assert_eq(FcCareerRules.agent_negotiation(FcCareerProfile.new()), 40.0)


# --- the flow ---------------------------------------------------------------------------------------------------

func test_a_rookie_contract_does_not_trigger_talks_but_an_expiring_one_does() -> void:
	var c := _career(82)
	assert_true(c.contract_offer().is_empty())
	var early := c.finish_season()
	assert_true(early["ok"] and not early["contract_pending"], "years remain: the season rolls over")
	var e := _expiring(83)
	var year := e.state.current_season
	var r := e.finish_season()
	assert_true(r["ok"] and r["contract_pending"], "the contract ends: the offseason waits")
	assert_true(e.profile().contract_pending)
	assert_eq(e.state.current_season, year, "the new season has not begun")
	var offer := e.contract_offer()
	assert_true(not offer.is_empty() and offer["salary"] > 0 and offer["max_salary"] >= offer["salary"] and offer["years"] >= 1)
	var blocked := e.finish_season()
	assert_true(not blocked["ok"] and "contract talks" in blocked["reason"], "no moving on while the talks are open")


func test_accepting_gives_exactly_the_offered_deal_and_the_season_rolls_on() -> void:
	var c := _expiring(84)
	c.finish_season()
	var offer := c.contract_offer()
	var year := c.state.current_season
	var r := c.answer_contract("accept")
	assert_true(r["ok"], r["reason"])
	assert_true(not c.profile().contract_pending and c.profile().contract_resolved_year == year)
	var done := c.finish_season()
	assert_true(done["ok"] and not done["contract_pending"])
	assert_eq(c.state.current_season, year + 1)
	var contract := c.state.world.active_contract_of(c.profile().player_id)
	assert_true(contract != null, "he has a contract again")
	assert_eq(contract.years[0].salary, int(offer["salary"]), "the deal he accepted")
	assert_eq(contract.length(), int(offer["years"]))
	assert_true(c.is_signed() and c.state.user_team_id == contract.team_id)
	assert_eq(c.state.validate(), [] as Array[String], str(c.state.validate()))
	assert_true(c.profile().decisions.any(func(d): return d["key"] == "contract"))
	assert_eq(c.state.agreed_terms, {}, "nothing is left over")


func test_a_counter_within_the_ceiling_wins_more_and_one_above_it_is_refused() -> void:
	var c := _expiring(85, "agent_flashy")
	c.profile().reputation = 20
	c.finish_season()
	var offer := c.contract_offer()
	assert_true(offer["max_salary"] > offer["salary"])
	var too_much := c.answer_contract("counter", int(offer["max_salary"]) + 1000000)
	assert_true(not too_much["ok"] and "most it would go to" in too_much["reason"])
	assert_true(c.profile().contract_pending, "a refused counter leaves the talks open")
	var rep := c.profile().reputation
	var hard := int(offer["max_salary"])
	var won := c.answer_contract("counter", hard)
	assert_true(won["ok"], won["reason"])
	assert_true(hard > int(offer["salary"]) * 1.05)
	assert_eq(c.profile().reputation, rep - 1, "hard bargaining costs reputation")
	assert_true(c.profile().tags.has("hardball"))
	c.finish_season()
	assert_eq(c.state.world.active_contract_of(c.profile().player_id).years[0].salary, hard, "the pushed salary is what he signed")
	var small := _expiring(86)
	small.finish_season()
	var s_offer := small.contract_offer()
	var rep2 := small.profile().reputation
	assert_true(small.answer_contract("counter", int(s_offer["salary"]) - 500000)["ok"], "asking for less than the offer just takes the offer")
	small.finish_season()
	assert_eq(small.state.world.active_contract_of(small.profile().player_id).years[0].salary, int(s_offer["salary"]))
	assert_eq(small.profile().reputation, rep2)


func test_letting_it_run_out_sends_him_to_free_agency_and_the_ai_does_not_re_sign_him() -> void:
	var c := _expiring(87)
	c.finish_season()
	var r := c.answer_contract("expire")
	assert_true(r["ok"] and "free agency" in r["reason"])
	var done := c.finish_season()
	assert_true(done["ok"])
	var contract := c.state.world.active_contract_of(c.profile().player_id)
	assert_true(contract != null, "somebody signed him, or the draft team did")
	assert_true(c.is_signed())
	assert_eq(c.state.validate(), [] as Array[String])
	assert_true(not c.answer_contract("expire")["ok"], "no talks left to answer")
	assert_true(not c.answer_contract("bogus")["ok"])


func test_talks_survive_saving_and_the_same_choices_give_the_same_career() -> void:
	var a := _expiring(88)
	a.finish_season()
	var dir := "user://test_saves_career_contract"
	var manager := FcSaveManager.new(dir)
	assert_true(a.save(manager).is_ok())
	var back := FcCareerController.resume(manager.load_slot("career_1", defs).state)
	assert_true(back.profile().contract_pending)
	assert_eq(back.contract_offer(), a.contract_offer(), "the same offer after loading")
	back.answer_contract("accept")
	back.finish_season()
	a.answer_contract("accept")
	a.finish_season()
	assert_eq(back.profile().checksum(), a.profile().checksum(), "the loaded career continues identically")
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)
