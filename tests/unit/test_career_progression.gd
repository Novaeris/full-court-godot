extends FcTestCase
## Career Mode phase 3: XP and levels, points, game and training rewards, milestones, spending points under the ceilings, badges.
## Every rule is pure and deterministic, so most tests need no world at all.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile() -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	return p


func _career(seed_value: int = 41) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	return FcCareerController.new_career(spec, seed_value)["controller"]


# --- the XP curve and levels ----------------------------------------------------------------------------

func test_levels_and_xp_are_inverse_and_strictly_increasing() -> void:
	var max_level := int(FcCareerRules.rules()["max_level"])
	assert_eq(FcCareerRules.xp_for_level(1), 0)
	var previous := 0
	for level in range(2, max_level + 1):
		var need := FcCareerRules.xp_for_level(level)
		assert_true(need > previous, "level %d needs more than level %d" % [level, level - 1])
		assert_eq(FcCareerRules.level_for_xp(need), level, "exactly the XP of level %d" % level)
		assert_eq(FcCareerRules.level_for_xp(need - 1), level - 1, "one XP short of level %d" % level)
		previous = need
	assert_eq(FcCareerRules.level_for_xp(10000000), max_level, "the level never passes the maximum")
	assert_eq(FcCareerRules.level_for_xp(0), 1)


func test_level_progress_shows_a_fraction_of_the_current_level() -> void:
	var xp := FcCareerRules.xp_for_level(4) + 10
	var prog := FcCareerRules.level_progress(xp)
	assert_eq(prog["level"], 4)
	assert_eq(prog["into_level"], 10)
	assert_eq(prog["needed"], FcCareerRules.xp_for_level(5) - FcCareerRules.xp_for_level(4))
	assert_between(prog["fraction"], 0.0, 1.0)
	assert_eq(FcCareerRules.level_progress(10000000)["fraction"], 1.0)


func test_level_rewards_follow_the_data() -> void:
	assert_eq(FcCareerRules.level_rewards(2), {"development_points": 3, "skill_points": 1})
	assert_eq(FcCareerRules.level_rewards(3), {"development_points": 3, "skill_points": 0})
	assert_eq(FcCareerRules.level_rewards(5), {"development_points": 5, "skill_points": 0}, "a bonus every 5 levels")
	assert_eq(FcCareerRules.level_rewards(10), {"development_points": 5, "skill_points": 1})


func test_awarding_xp_grants_the_points_of_every_level_crossed_exactly_once() -> void:
	var p := _profile()
	var granted := FcCareerRules.award_xp(p, FcCareerRules.xp_for_level(6))
	assert_eq(p.level, 6)
	var dev := 0
	var skill := 0
	for level in range(2, 7):
		dev += FcCareerRules.level_rewards(level)["development_points"]
		skill += FcCareerRules.level_rewards(level)["skill_points"]
	assert_eq(p.development_points, dev)
	assert_eq(p.skill_points, skill)
	assert_eq(granted["levels_gained"], 5)
	var again := FcCareerRules.award_xp(p, 1)
	assert_eq(again["levels_gained"], 0, "a little more XP in the same level grants no points again")
	assert_eq(p.development_points, dev)
	assert_eq(FcCareerRules.award_xp(p, 0)["xp"], 0, "zero XP does nothing")
	assert_eq(FcCareerRules.award_xp(p, -500)["xp"], 0, "negative XP is refused: XP can only grow")
	assert_eq(p.xp, FcCareerRules.xp_for_level(6) + 1)


func test_the_same_events_always_give_the_same_profile() -> void:
	var lines := [{"minutes": 32, "points": 18, "rebounds": 6, "assists": 5, "steals": 1, "blocks": 0, "turnovers": 2, "won": true},
		{"minutes": 20, "points": 4, "rebounds": 2, "assists": 1, "steals": 0, "blocks": 0, "turnovers": 3, "won": false}]
	var a := _profile()
	var b := _profile()
	for i in 12:
		FcCareerRules.apply_game(a, lines[i % 2])
		FcCareerRules.apply_game(b, lines[i % 2])
	FcCareerRules.train(a, 2026)
	FcCareerRules.train(b, 2026)
	assert_eq(a.checksum(), b.checksum(), "deterministic: the same events give a byte-identical profile")


# --- games, milestones, training -------------------------------------------------------------------------------

func test_game_xp_rewards_winning_play_with_a_floor_and_a_cap() -> void:
	var quiet := {"minutes": 30, "points": 0, "rebounds": 0, "assists": 0, "steals": 0, "blocks": 0, "turnovers": 5, "won": false}
	assert_eq(FcCareerRules.game_xp(quiet), int(FcCareerRules.rules()["game_xp"]["floor"]), "a bad night still earns the floor")
	var huge := {"minutes": 40, "points": 80, "rebounds": 30, "assists": 30, "steals": 10, "blocks": 10, "turnovers": 0, "won": true}
	assert_eq(FcCareerRules.game_xp(huge), int(FcCareerRules.rules()["game_xp"]["cap"]), "a monster night is capped")
	var base := {"minutes": 30, "points": 15, "rebounds": 5, "assists": 5, "steals": 1, "blocks": 1, "turnovers": 2, "won": false}
	var win := base.duplicate()
	win["won"] = true
	assert_true(FcCareerRules.game_xp(win) > FcCareerRules.game_xp(base), "a win is worth more")
	var short := base.duplicate()
	short["minutes"] = 10
	assert_true(FcCareerRules.game_xp(short) < FcCareerRules.game_xp(base), "few minutes, less XP")
	assert_eq(FcCareerRules.game_xp({"minutes": 0, "points": 30}), 0, "no minutes, no XP")
	assert_eq(FcCareerRules.game_xp({}), 0, "a missing line is not a game")


func test_milestones_pay_once_and_games_find_them() -> void:
	var p := _profile()
	var line := {"minutes": 30, "points": 12, "rebounds": 11, "assists": 2, "steals": 0, "blocks": 0, "turnovers": 1, "won": true}
	var first := FcCareerRules.apply_game(p, line)
	assert_true(first["milestones"].has("first_game") and first["milestones"].has("ten_point_game") and first["milestones"].has("double_double"))
	var xp_after_first := p.xp
	var currency := p.currency
	assert_true(currency > 0, "the double-double pays currency")
	var second := FcCareerRules.apply_game(p, line)
	assert_eq(second["milestones"], [], "every milestone pays only once")
	assert_eq(p.currency, currency)
	assert_eq(p.xp, xp_after_first + FcCareerRules.game_xp(line))
	assert_true(not FcCareerRules.claim_milestone(p, "double_double")["ok"], "claiming again is refused")
	assert_true(not FcCareerRules.claim_milestone(p, "nonsense")["ok"])
	var season := FcCareerRules.claim_milestone(p, "season_complete")
	assert_true(season["ok"] and season["granted"]["development_points"] >= 1)


func test_training_is_limited_per_season_and_worth_less_each_time() -> void:
	var p := _profile()
	var limit := int(FcCareerRules.rules()["training"]["sessions_per_season"])
	var previous := 1000000
	for i in limit:
		var before := p.xp
		var r := FcCareerRules.train(p, 2026)
		assert_true(r["ok"], "session %d" % (i + 1))
		var xp := p.xp - before
		assert_true(xp <= previous, "each session is worth no more than the last")
		previous = xp
	var refused := FcCareerRules.train(p, 2026)
	assert_true(not refused["ok"] and "all %d training sessions" % limit in refused["reason"])
	assert_true(FcCareerRules.train(p, 2027)["ok"], "a new season has new sessions")


# --- attributes under ceilings ------------------------------------------------------------------------------

func test_attribute_costs_rise_with_the_value() -> void:
	assert_eq(FcCareerRules.attribute_cost(30), 1)
	assert_eq(FcCareerRules.attribute_cost(59), 1)
	assert_eq(FcCareerRules.attribute_cost(60), 2)
	assert_eq(FcCareerRules.attribute_cost(75), 3)
	assert_eq(FcCareerRules.attribute_cost(85), 4)
	assert_eq(FcCareerRules.attribute_cost(98), 4)


func test_raising_an_attribute_spends_points_and_respects_the_ceiling() -> void:
	var c := _career()
	var p := c.player()
	var profile := c.profile()
	var key := "three_point"
	var value := p.attributes.get_value(key)
	var none := c.raise_attribute(key)
	assert_true(not none["ok"] and "costs" in none["reason"], "no points, no raise")
	assert_eq(p.attributes.get_value(key), value)
	profile.development_points = 5
	var r := c.raise_attribute(key)
	assert_true(r["ok"], r["reason"])
	assert_eq(p.attributes.get_value(key), value + 1)
	assert_eq(profile.development_points, 5 - FcCareerRules.attribute_cost(value))
	assert_true(not c.raise_attribute("bogus")["ok"], "unknown attributes are refused")
	# with unlimited points the ceiling still stops growth, and nothing ever goes above 99
	profile.development_points = 100000
	var ceiling := FcPlayerBuild.attribute_ceiling(key, FcPlayerBuild.spec_of(p))
	for i in 100:
		c.raise_attribute(key)
	assert_eq(p.attributes.get_value(key), ceiling, "growth stops exactly at the ceiling")
	var refused := c.raise_attribute(key)
	assert_true(not refused["ok"] and "most your body and potential allow" in refused["reason"])
	for k in defs.attributes.keys():
		for i in 120:
			c.raise_attribute(k)
		assert_true(p.attributes.get_value(k) <= FcPlayerBuild.attribute_ceiling(k, FcPlayerBuild.spec_of(p)) and p.attributes.get_value(k) <= 99, k)


# --- badges ----------------------------------------------------------------------------------------------------

func test_the_badge_data_is_consistent() -> void:
	var ratings_file := FileAccess.open("res://data/simulation/ratings.json", FileAccess.READ)
	var composite_names: Dictionary = JSON.parse_string(ratings_file.get_as_text())["composites"]
	assert_true(FcBadges.keys().size() >= 8, "the brief's examples")
	for badge in FcBadges.all():
		assert_true(int(badge["cost"]) >= 1, badge["key"])
		for composite in badge["effects"]:
			assert_true(composite_names.has(composite), "%s changes a real composite (%s)" % [badge["key"], composite])
			assert_true(int(badge["effects"][composite]) <= FcBadges.bonus_cap(), "a single badge stays within the cap")
		for attribute in badge["requires"]["attributes"]:
			assert_true(defs.attributes.has_key(attribute), "%s needs a real attribute" % badge["key"])
		for other in badge["requires"]["badges"]:
			assert_true(not FcBadges.get_badge(other).is_empty() and other != badge["key"], "%s has a real prerequisite" % badge["key"])


func test_unlocking_a_badge_needs_level_attributes_prerequisites_and_points() -> void:
	var c := _career()
	var p := c.player()
	var profile := c.profile()
	assert_true("Needs level" in FcCareerRules.badge_problem(profile, p, "catch_and_shoot"))
	profile.level = 10
	p.attributes.set_value("three_point", 50)
	assert_true("Needs Three-Point Shooting 60" in FcCareerRules.badge_problem(profile, p, "catch_and_shoot"))
	p.attributes.set_value("three_point", 70)
	assert_true("skill points" in FcCareerRules.badge_problem(profile, p, "catch_and_shoot"))
	profile.skill_points = 5
	assert_eq(FcCareerRules.badge_problem(profile, p, "catch_and_shoot"), "")
	assert_true("Needs the Catch and Shoot badge first" in FcCareerRules.badge_problem(profile, p, "corner_specialist"), "a prerequisite chain")
	var r := c.unlock_badge("catch_and_shoot")
	assert_true(r["ok"], r["reason"])
	assert_eq(profile.skill_points, 5 - int(FcBadges.get_badge("catch_and_shoot")["cost"]))
	assert_true("already own" in FcCareerRules.badge_problem(profile, p, "catch_and_shoot"))
	assert_eq(FcCareerRules.badge_problem(profile, p, "corner_specialist"), "", "now the prerequisite is met")
	assert_true(not c.unlock_badge("nonsense")["ok"])


func test_equipping_is_limited_and_the_bonus_is_capped() -> void:
	var profile := _profile()
	assert_true(not FcCareerRules.set_badge_equipped(profile, "clamps", true)["ok"], "you cannot equip what you do not own")
	profile.badges_owned = ["catch_and_shoot", "corner_specialist", "ankle_breaker", "pick_and_roll_maestro", "clamps", "rim_protector"]
	for key in profile.badges_owned.slice(0, 5):
		assert_true(FcCareerRules.set_badge_equipped(profile, key, true)["ok"], key)
	var sixth := FcCareerRules.set_badge_equipped(profile, "rim_protector", true)
	assert_true(not sixth["ok"] and "at most 5" in sixth["reason"])
	assert_true(FcCareerRules.set_badge_equipped(profile, "clamps", false)["ok"])
	assert_true(FcCareerRules.set_badge_equipped(profile, "rim_protector", true)["ok"])
	assert_eq(profile.validate(), [] as Array[String], str(profile.validate()))
	var bonus := FcCareerRules.composite_bonus(["catch_and_shoot", "corner_specialist"])
	assert_eq(bonus["three"], 4, "two +2 badges reach the cap exactly")
	var stacked := FcCareerRules.composite_bonus(["catch_and_shoot", "corner_specialist", "catch_and_shoot"])
	assert_eq(stacked["three"], FcBadges.bonus_cap(), "the total on one composite never passes the cap")
	assert_eq(FcCareerRules.composite_bonus([]), {})
	for composite in FcCareerRules.composite_bonus(FcBadges.keys()).values():
		assert_true(composite <= FcBadges.bonus_cap())


# --- persistence and the screens -----------------------------------------------------------------------------

func test_progression_survives_saving_and_loading() -> void:
	var c := _career()
	c.award_game({"minutes": 30, "points": 14, "rebounds": 4, "assists": 3, "steals": 1, "blocks": 0, "turnovers": 2, "won": true})
	c.train()
	c.profile().development_points += 10
	c.raise_attribute("passing")
	var dir := "user://test_saves_progression"
	var manager := FcSaveManager.new(dir)
	assert_true(c.save(manager).is_ok())
	var back := FcCareerController.resume(manager.load_slot("career_1", defs).state)
	assert_eq(back.profile().checksum(), c.profile().checksum(), "XP, points, milestones and training survive")
	assert_eq(back.player().attributes.get_value("passing"), c.player().attributes.get_value("passing"), "the raised attribute survives")
	assert_eq(back.progress(), c.progress())
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)


func test_the_controller_reports_progress_and_badges() -> void:
	var c := _career()
	var progress := c.progress()
	assert_eq(progress["level"], 1)
	assert_eq(progress["training_left"], int(FcCareerRules.rules()["training"]["sessions_per_season"]))
	c.train()
	assert_eq(c.progress()["training_left"], progress["training_left"] - 1)
	assert_true(c.progress()["xp"] > 0)
	var list := c.badge_list()
	assert_eq(list.size(), FcBadges.all().size())
	assert_true(list.all(func(b): return not b["owned"] and b["problem"] != ""), "nothing is unlockable at level 1")
	assert_eq(c.badge_bonus(), {})


func test_the_hub_has_card_develop_and_skills_tabs_that_work() -> void:
	var app := FcApp.new()
	app.saves = FcSaveManager.new("user://test_saves_hub_tabs")
	app.preferences = FcPreferences.new("user://test_preferences_hub.cfg")
	app.preferences.tutorial_done = true
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	var spec := FcPlayerBuild.default_spec("sharpshooter", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	assert_true(app.on_create_career(spec, 9))
	var text := _labels_text(app)
	assert_true("Development points" in text and "Skill points" in text and "Level 1" in text)
	var names: Array = []
	var stack: Array = [app]
	var tabs: TabContainer = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is TabContainer:
			tabs = n
		stack.append_array(n.get_children())
	assert_true(tabs != null)
	for i in tabs.get_tab_count():
		names.append(tabs.get_tab_title(i))
	assert_eq(names, ["Card", "Season", "Develop", "Skills"])
	var xp_before := app.career.profile().xp
	app.career.train()
	app.show_career_hub()
	assert_true(app.career.profile().xp > xp_before and "XP %d" % app.career.profile().xp in _labels_text(app), "the hub shows the new XP")
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	var dir := DirAccess.open("user://test_saves_hub_tabs")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute("user://test_saves_hub_tabs")
	DirAccess.remove_absolute("user://test_preferences_hub.cfg")


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text
