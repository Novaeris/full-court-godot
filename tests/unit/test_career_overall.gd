extends FcTestCase
## Career Mode: the goal is the maximum OVERALL (potential), reached by the player's own choices. Automatic growth becomes development
## points; potential caps overall; previews and real raises share one calculation; the league's other players are untouched.

var defs: FcDefinitionSet
var ratings: FcPlayerRatings


func before_each() -> void:
	defs = FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()


func _career(archetype: String = "two_way_wing", position: int = 3, seed_value: int = 131) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec(archetype, position, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	return c


func _world(seed_value: int = 1301) -> FcWorld:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	return FcWorldGenerator.new(data, defs, cfg).generate(seed_value)


# --- growth becomes points, nothing else moves -----------------------------------------------------------------

func test_the_growth_points_are_exactly_what_the_original_algorithm_applies() -> void:
	var progression := FcPlayerProgression.new(defs, ratings)
	var world := _world()
	var checked := 0
	for p in world.players.all():
		var age: int = p.age_on(FcDate.new(2027, 7, 1))
		var predicted := progression.growth_points_for(p, age, 50.0)
		var result := progression.progress(p, age, 50.0, FcRng.new(5))
		assert_eq(result["growth_points"], predicted, "player %d: the same number the algorithm used" % p.id)
		if age > p.development.peak_age:
			assert_eq(predicted, 0.0, "no growth after the peak")
		checked += 1
	assert_true(checked > 50)


func test_other_players_are_bit_identical_and_the_career_player_loses_only_the_growth() -> void:
	var base_world := _world()
	var career_world := _world()
	# the same world, the same random stream; in one of them one player's growth is handed to the player instead
	var career_pid: int = career_world.players.ids()[7]
	var base_off := FcOffseason.new(base_world)
	var career_off := FcOffseason.new(career_world)
	career_off.career_player_ids = [career_pid] as Array[int]
	base_off.progress_and_retire(1, 2026, 2027, FcRng.new(9))
	var report := career_off.progress_and_retire(1, 2026, 2027, FcRng.new(9))
	assert_true(report.has("career_growth") and report["career_growth"].has(career_pid))
	for p in base_world.players.all():
		var other: FcPlayer = career_world.players.get_by_id(p.id)
		if p.id == career_pid:
			continue
		assert_eq(other.attributes.to_dict(), p.attributes.to_dict(), "player %d is exactly as before (no random number shifted)" % p.id)
		assert_eq(other.development.potential, p.development.potential)
	var base_player: FcPlayer = base_world.players.get_by_id(career_pid)
	var career_player: FcPlayer = career_world.players.get_by_id(career_pid)
	var age: int = base_player.age_on(FcDate.new(2027, 7, 1))
	if age <= base_player.development.peak_age and float(report["career_growth"][career_pid]) > 0.5:
		assert_true(ratings.overall(career_player) < ratings.overall(base_player), "he did not get the automatic growth")
	else:
		assert_eq(career_player.attributes.to_dict(), base_player.attributes.to_dict(), "after the peak decline and noise are the same")


func test_without_career_players_the_offseason_is_unchanged() -> void:
	var a := _world(1302)
	var b := _world(1302)
	FcOffseason.new(a).progress_and_retire(1, 2026, 2027, FcRng.new(3))
	var off := FcOffseason.new(b)
	off.career_player_ids = [] as Array[int]
	var report := off.progress_and_retire(1, 2026, 2027, FcRng.new(3))
	assert_true(not report.has("career_growth"))
	for p in a.players.all():
		assert_eq(b.players.get_by_id(p.id).attributes.to_dict(), p.attributes.to_dict())


func test_a_season_hands_the_growth_to_the_player_once_even_across_saving() -> void:
	var c := _career()
	var before := FcCareerRules.overall_now(c.player())
	var points_before := c.profile().development_points
	var year := c.state.current_season
	var result := c.finish_season()
	assert_true(result["ok"])
	assert_true(result["growth_points"] > 0, "a young player's growth arrives as points")
	assert_eq(c.profile().growth_granted_year, year)
	assert_true(c.profile().development_points >= points_before + int(result["growth_points"]), "plus the level and milestone points")
	assert_true(FcCareerRules.overall_now(c.player()) - before <= 3, "his attributes did not grow by themselves")
	var points := c.profile().development_points
	assert_eq(c._grant_growth({"career_growth": {c.profile().player_id: 5.0}}, year), 0, "the same season is never granted twice")
	assert_eq(c.profile().development_points, points)
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_eq(back.growth_granted_year, year, "and that survives saving")
	assert_eq(FcCareerRules.growth_to_points(2.0), roundi(2.0 * float(FcCareerRules.rules()["growth_to_points"])))


# --- the cap and the preview ---------------------------------------------------------------------------------------

func test_the_preview_is_the_real_calculation_and_changes_nothing() -> void:
	var c := _career()
	var p := c.player()
	c.profile().development_points = 50
	for key in ["three_point", "durability", "perimeter_defense"]:
		var preview := FcCareerRules.raise_preview(c.profile(), p, key)
		var attrs := p.attributes.to_dict()
		var points := c.profile().development_points
		assert_eq(p.attributes.to_dict(), attrs, "a preview never changes the player")
		assert_true(preview["ok"], preview["reason"])
		var overall_before := ratings.overall(p)
		var raised := FcCareerRules.raise_attribute(c.profile(), p, key)
		assert_true(raised["ok"])
		assert_eq(c.profile().development_points, points - int(preview["cost"]), "it costs exactly what was shown")
		assert_true(absf((ratings.overall(p) - overall_before) - float(preview["gain"])) < 0.0000001, "and gains exactly what was shown")
	var weights: Dictionary = ratings.overall_weights
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var durability := FcCareerRules.raise_preview(c.profile(), p, "durability")
	var defense := FcCareerRules.raise_preview(c.profile(), p, "perimeter_defense")
	assert_true(absf(float(durability["gain"]) - 1.0 / total) < 0.0000001, "durability counts weight 1 of %d" % int(total))
	assert_true(absf(float(defense["gain"]) - 7.0 / total) < 0.0000001, "perimeter defense counts weight 7")
	assert_true(defense["gain"] > durability["gain"] * 6.0)


func test_a_raise_past_the_potential_is_blocked_with_a_reason_and_rounding_cannot_slip_through() -> void:
	var c := _career()
	var p := c.player()
	c.profile().development_points = 100000
	var cap := FcCareerRules.overall_cap(c.profile(), p)
	for i in 1500:
		var best := FcCareerRules.best_next_upgrade(c.profile(), p)
		if best.is_empty() or not FcCareerRules.raise_attribute(c.profile(), p, best["key"])["ok"]:
			break
		assert_true(FcCareerRules.overall_now(p) <= cap, "the displayed overall never passes the potential")
	assert_true(FcCareerRules.overall_now(p) >= cap - 1, "he got to the ceiling")
	var blocked := false
	for k in defs.attributes.keys():
		var preview := FcCareerRules.raise_preview(c.profile(), p, k)
		if preview["blocked"] == "potential":
			blocked = true
			assert_true("potential overall (%d)" % cap in preview["reason"] and "keep your points" in preview["reason"])
			assert_true(roundi(preview["overall_after"]) > cap, "blocked exactly because the rounded overall would pass it")
		if preview["ok"]:
			assert_true(roundi(preview["overall_after"]) <= cap, "every allowed raise stays within the cap")
	assert_true(blocked, "at the cap some raises are blocked by the potential")
	assert_true(c.profile().development_points > 0, "banked points remain")


func test_banked_points_can_be_spent_after_age_lowers_the_rating() -> void:
	var c := _career()
	var p := c.player()
	c.profile().development_points = 100000
	while true:
		var best := FcCareerRules.best_next_upgrade(c.profile(), p)
		if best.is_empty() or not FcCareerRules.raise_attribute(c.profile(), p, best["key"])["ok"]:
			break
	var banked := c.profile().development_points
	assert_true(banked > 0)
	var cap := FcCareerRules.overall_cap(c.profile(), p)
	for key in ["perimeter_defense", "interior_defense", "three_point", "close_finishing", "ball_handling", "passing"]:
		p.attributes.set_value(key, p.attributes.get_value(key) - 6)   # the years take their toll
	assert_true(FcCareerRules.overall_now(p) < cap)
	var best_after := FcCareerRules.best_next_upgrade(c.profile(), p)
	assert_true(not best_after.is_empty() and best_after["affordable"], "the bank pays to hold the rating")
	assert_true(FcCareerRules.raise_attribute(c.profile(), p, best_after["key"])["ok"])
	assert_true(c.profile().development_points < banked)


func test_best_next_upgrade_is_the_best_gain_per_point_and_deterministic() -> void:
	var c := _career()
	var best := FcCareerRules.best_next_upgrade(c.profile(), c.player())
	assert_eq(best, FcCareerRules.best_next_upgrade(c.profile(), c.player()), "deterministic")
	var winner := 0.0
	for k in defs.attributes.keys():
		var pr := FcCareerRules.raise_preview(c.profile(), c.player(), k)
		if pr["blocked"] in ["unknown", "ceiling", "potential"]:
			continue
		winner = maxf(winner, float(pr["gain"]) / float(pr["cost"]))
	assert_true(absf(float(best["gain"]) / float(best["cost"]) - winner) < 0.0000001, "nothing beats it per point")
	var view := c.development_view()
	assert_eq(view["rows"].size(), defs.attributes.keys().size())
	assert_eq(view["best"], best)
	assert_true(view["progress"]["overall"] <= view["progress"]["potential"])
	for row in view["rows"]:
		assert_true(row["ok"] or row["reason"] != "", "an unavailable upgrade always says why")


# --- the milestone ------------------------------------------------------------------------------------------------

func test_reaching_the_potential_is_a_one_time_milestone_with_a_banner() -> void:
	var c := _career()
	var p := c.player()
	assert_true(not FcCareerRules.check_potential(c.profile(), p)["ok"], "not yet")
	assert_true(not c.profile().potential_banner_pending)
	c.profile().development_points = 100000
	var xp := c.profile().xp
	var skill := c.profile().skill_points
	var currency := c.profile().currency
	while true:
		var best := FcCareerRules.best_next_upgrade(c.profile(), p)
		if best.is_empty() or not c.raise_attribute(best["key"])["ok"]:
			break
	assert_true(c.profile().milestones.has("potential_reached"), "claimed as soon as he was within a point of his potential")
	assert_true(c.profile().potential_banner_pending)
	assert_true(c.profile().xp > xp and c.profile().skill_points > skill and c.profile().currency > currency, "XP, a skill point and currency")
	assert_true(c.state.world.news.any(func(n): return "full potential" in n["text"]), "and a line in the news")
	var after := c.profile().xp
	assert_true(not FcCareerRules.check_potential(c.profile(), p)["ok"], "never claimed twice")
	assert_eq(c.profile().xp, after)
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_true(back.potential_banner_pending and back.milestones.has("potential_reached"), "saved")
	c.dismiss_potential_banner()
	assert_true(not c.profile().potential_banner_pending)
	assert_true(c.profile().milestones.has("potential_reached"), "dismissing the banner does not unclaim it")
	assert_true(c.profile().development_points > 0, "and the banked points are still there")


# --- different players, different developments ------------------------------------------------------------------------

func _develop(archetype: String, position: int, priority: Array) -> Dictionary:
	var c := _career(archetype, position, 140)
	var p := c.player()
	var progression := FcPlayerProgression.new(defs, ratings)
	var age := 19
	while age <= p.development.peak_age:
		c.profile().development_points += FcCareerRules.growth_to_points(progression.growth_points_for(p, age, 50.0))
		var progress := true
		while progress and c.profile().development_points > 0:
			progress = false
			for key in priority:
				if FcCareerRules.raise_attribute(c.profile(), p, key)["ok"]:
					progress = true
					break
		var best := FcCareerRules.best_next_upgrade(c.profile(), p)
		while not best.is_empty() and best["affordable"] and FcCareerRules.raise_attribute(c.profile(), p, best["key"])["ok"]:
			best = FcCareerRules.best_next_upgrade(c.profile(), p)
		age += 1
	return {"overall": FcCareerRules.overall_now(p), "potential": FcCareerRules.overall_cap(c.profile(), p), "player": p}


func _average(p: FcPlayer, keys: Array) -> float:
	var total := 0.0
	for k in keys:
		total += p.attributes.get_value(k)
	return total / keys.size()


func test_an_offensive_star_and_a_defensive_specialist_reach_their_potential_as_different_players() -> void:
	var offense := ["three_point", "ball_handling", "passing", "close_finishing", "layups", "mid_range", "shot_selection", "offensive_awareness"]
	var defense := ["perimeter_defense", "interior_defense", "rebounding", "steals", "blocks", "defensive_awareness", "strength", "vertical"]
	var star := _develop("scoring_guard", 2, ["three_point", "ball_handling", "passing", "close_finishing"])
	var stopper := _develop("defensive_anchor", 5, ["perimeter_defense", "interior_defense", "rebounding", "defensive_awareness"])
	assert_true(star["overall"] >= star["potential"] - 3, "the offensive player reaches his potential (%d of %d)" % [star["overall"], star["potential"]])
	assert_true(stopper["overall"] >= stopper["potential"] - 4, "so does the defender (%d of %d)" % [stopper["overall"], stopper["potential"]])
	assert_true(_average(star["player"], offense) > _average(stopper["player"], offense) + 5.0, "different shapes: the star shoots, handles and passes better")
	assert_true(_average(stopper["player"], defense) > _average(star["player"], defense) + 5.0, "and the specialist defends and rebounds better")
	assert_true(star["player"].attributes.get_value("durability") < 60 and star["player"].attributes.get_value("work_ethic") < 60, "not every skill is maxed: the weights that barely count stay low")


func test_the_spending_strategies_rank_as_designed() -> void:
	var study = load("res://tools/career_growth_study.gd")
	var focused: Dictionary = study.run(defs, "two_way_wing", "focused")
	var even: Dictionary = study.run(defs, "two_way_wing", "even")
	var template: Dictionary = study.run(defs, "two_way_wing", "template")
	var low: Dictionary = study.run(defs, "two_way_wing", "low_weight")
	assert_true(focused["final"] >= focused["potential"] - 3, "focused development gets to (within 3 of) the potential: %d of %d" % [focused["final"], focused["potential"]])
	assert_true(even["final"] < focused["final"], "even development finishes below it (%d vs %d)" % [even["final"], focused["final"]])
	assert_true(low["final"] < even["final"] and template["final"] < even["final"], "low-weight and strengths-only spending finish clearly lower")
	assert_true(focused["unspent"] <= 5, "no large idle bank when spending sensibly")
	assert_true(focused["age"] == 0 or focused["age"] >= 24, "potential is not reached unrealistically early")
