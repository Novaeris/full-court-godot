extends FcTestCase
## Dynasty collection goals (Phase 5B, Dynasty data version 4): data soundness, derived progress for every goal type, claiming once with
## the reward through the ledger, and saving / migration.

var env: FcDynastyEnv


func before_each() -> void:
	env = FcDynastyEnv.make(43)


func after_each() -> void:
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)


func _goal(id: String) -> Dictionary:
	for g in FcDynastyGoals.definitions():
		if str(g["id"]) == id:
			return g
	return {}


func _claim(id: String) -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyGoals.claim(env.session.profile, env.catalog, id))


func test_the_goal_data_passes_its_validator() -> void:
	assert_eq(FcDynastyGoals.validate(), [])
	assert_true(FcDynastyGoals.definitions().size() >= 8)


func test_owned_goals_count_distinct_cards_matching_the_filter() -> void:
	var before := int(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("first_ten"))["have"])
	assert_eq(before, mini(10, env.profile().unique_owned()))
	for i in 12:
		env.give(FcDynastyFixture.card_id(i + 1))
	var p := FcDynastyGoals.progress(env.profile(), env.catalog, _goal("first_ten"))
	assert_true(bool(p["done"]) and int(p["have"]) == 10, "capped at the need")


func test_position_and_team_goals_read_the_release() -> void:
	for i in 20:
		env.give(FcDynastyFixture.card_id(i + 1))
	var positions := FcDynastyGoals.progress(env.profile(), env.catalog, _goal("every_position"))
	var seen := {}
	for id in env.profile().cards:
		seen[env.catalog.owned_view(str(id), env.profile().cards[id])["position"]] = true
	assert_eq(positions["have"], mini(5, seen.size()))
	var teams := FcDynastyGoals.progress(env.profile(), env.catalog, _goal("many_teams"))
	assert_true(int(teams["have"]) >= 0 and int(teams["have"]) <= 5)


func test_mastery_goals_read_the_profile() -> void:
	var id := FcDynastyFixture.card_id(1)
	env.give(id)
	assert_true(not bool(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("first_mastery"))["done"]))
	env.profile().cards[id]["mastery"] = 3
	assert_true(bool(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("first_mastery"))["done"]))
	assert_true(bool(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("mastery_three"))["done"]))
	assert_eq(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("mastery_ten"))["have"], 3)
	var other := FcDynastyFixture.card_id(2)
	env.give(other)
	env.profile().cards[other]["mastery"] = 7
	assert_true(bool(FcDynastyGoals.progress(env.profile(), env.catalog, _goal("mastery_ten"))["done"]), "mastery adds up across cards")


func test_a_finished_goal_pays_once_through_the_ledger() -> void:
	var id := FcDynastyFixture.card_id(1)
	env.give(id)
	env.profile().cards[id]["mastery"] = 1
	var shards := env.profile().balance("shards")
	var r := _claim("first_mastery")
	assert_true(r.ok, r.message)
	assert_eq(env.profile().balance("shards"), shards + 20)
	assert_eq(env.profile().ledger[env.profile().ledger.size() - 1]["kind"], "goal_reward")
	assert_eq(_claim("first_mastery").code, "already_claimed")
	assert_eq(env.profile().balance("shards"), shards + 20, "no second payment")
	assert_true(FcDynastyGoals.listing(env.profile(), env.catalog).any(func(g): return g["id"] == "first_mastery" and g["claimed"]))


func test_an_unfinished_or_unknown_goal_cannot_be_claimed() -> void:
	var credits := env.profile().balance("credits")
	assert_eq(_claim("mastery_ten").code, "not_done")
	assert_eq(_claim("nope").code, "unknown_goal")
	assert_eq(env.profile().balance("credits"), credits)


func test_claims_save_and_an_older_profile_migrates_to_none_claimed() -> void:
	env.profile().goals["claimed"] = ["first_ten"]
	var again := FcDynastyProfile.from_dict(FcChecks.parse_json(JSON.stringify(env.profile().to_dict())))
	assert_eq(again.goals["claimed"], ["first_ten"])
	var step := FcDynastyMigrator.new().migrate({"team_name": "X"}, 3, 4)
	assert_true(step["ok"])
	assert_eq(step["payload"]["goals"], {"claimed": []})
	assert_eq(FcDynastyMigrator.new().migrate({"goals": {"claimed": ["a"]}}, 3, 4)["payload"]["goals"], {"claimed": ["a"]})
	assert_eq(FcDynastyProfile.from_dict({"team_name": "Old"}).goals, {"claimed": []})
