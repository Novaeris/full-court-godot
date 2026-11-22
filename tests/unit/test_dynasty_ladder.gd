extends FcTestCase
## Dynasty ranked ladder (Phase 5A, Dynasty data version 3): exact rating maths, tiers, the computer field and rank, tier and season
## credits paid once, saving and migration, and the quick-game hook.

var env: FcDynastyEnv


func before_each() -> void:
	env = FcDynastyEnv.make(41)


func after_each() -> void:
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)


func _quick(level: String = "even") -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, level))


func test_the_ladder_data_is_sound() -> void:
	var last := -1
	for t in FcDynastyLadder.tiers():
		assert_true(int(t["min"]) > last, "tiers climb")
		last = int(t["min"])
		assert_true(int(t["reach_credits"]) >= 0 and int(t["season_credits"]) >= 0)
	assert_eq(FcDynastyLadder.tiers()[0]["min"], 0, "everyone is in the first tier")
	assert_eq(FcDynastyLadder.start_rating(), 1000)


func test_elo_changes_are_exact_and_symmetric() -> void:
	assert_eq(FcDynastyLadder.delta_for(1000, 1000, true), 12, "an even game is worth half of k")
	assert_eq(FcDynastyLadder.delta_for(1000, 1000, false), -12)
	assert_true(FcDynastyLadder.delta_for(1000, 1200, true) > 12, "an upset pays more")
	assert_true(FcDynastyLadder.delta_for(1200, 1000, true) < 12, "an expected win pays less")


func test_tiers_follow_the_rating() -> void:
	assert_eq(FcDynastyLadder.tier_of(0)["id"], "bronze")
	assert_eq(FcDynastyLadder.tier_of(949)["id"], "bronze")
	assert_eq(FcDynastyLadder.tier_of(950)["id"], "silver")
	assert_eq(FcDynastyLadder.tier_of(5000)["id"], "master")
	assert_eq(FcDynastyLadder.next_tier(1000)["id"], "gold")
	assert_true(FcDynastyLadder.next_tier(5000).is_empty())


func test_the_field_is_fixed_for_a_seed_sorted_and_the_rank_counts_those_above() -> void:
	var p := env.profile()
	var a := FcDynastyLadder.field(p)
	assert_eq(a.size(), 99)
	assert_eq(a, FcDynastyLadder.field(p), "the same seed gives the same field")
	for i in range(1, a.size()):
		assert_true(int(a[i - 1]["rating"]) >= int(a[i]["rating"]))
	p.ladder["rating"] = 100000
	assert_eq(FcDynastyLadder.rank(p), 1)
	p.ladder["rating"] = 0
	assert_eq(FcDynastyLadder.rank(p), 100)
	p.ladder["rating"] = int(a[9]["rating"])
	var above := 0
	for f in a:
		if int(f["rating"]) > int(a[9]["rating"]):
			above += 1
	assert_eq(FcDynastyLadder.rank(p), above + 1)


func test_a_quick_game_is_a_ranked_game_and_moves_the_rating_by_the_reported_delta() -> void:
	var before := int(env.profile().ladder["rating"])
	var r := _quick("even")
	assert_true(r.ok, r.message)
	var l: Dictionary = r.data["ladder"]
	assert_eq(env.profile().ladder["rating"], before + int(l["delta"]))
	assert_eq(env.profile().ladder["games"], 1)
	assert_true(int(l["delta"]) == 12 or int(l["delta"]) == -12, "an even game at the start")
	assert_eq(env.profile().ladder["season_id"], env.catalog.active_season_id())
	assert_true(int(l["rank"]) >= 1)


func test_reaching_a_new_tier_pays_once_and_only_for_the_tier_climbed_into() -> void:
	var p := env.profile()
	p.ladder["season_id"] = env.catalog.active_season_id()
	p.ladder["rating"] = 1049   # one win from gold (1050)
	p.ladder["reached"] = ["bronze", "silver"]
	var credits := p.balance("credits")
	var out := FcDynastyLadder.on_game(p, env.catalog, true, 0)
	assert_eq(out["rating"], 1061)
	assert_true(bool(out["tier_up"]))
	assert_eq(out["reward"], 300)
	assert_eq(p.balance("credits"), credits + 300)
	var again := FcDynastyLadder.on_game(p, env.catalog, true, 0)
	assert_eq(again["reward"], 0, "a tier pays once per season")
	var q := FcDynastyEnv.make(42).profile()
	q.ladder["season_id"] = env.catalog.active_season_id()
	q.ladder["rating"] = 1249
	q.ladder["reached"] = ["bronze"]
	var jump := FcDynastyLadder.on_game(q, env.catalog, true, 0)
	assert_eq(jump["reward"], 800, "only the tier just climbed into pays (diamond); lower ones were already below the old rating")
	assert_true((q.ladder["reached"] as Array).has("silver") and (q.ladder["reached"] as Array).has("diamond"), "but every tier at or below is marked reached")


func test_a_new_season_resets_halfway_pays_the_old_tier_and_keeps_history() -> void:
	var p := env.profile()
	p.ladder["season_id"] = "old_season"
	p.ladder["rating"] = 1200
	p.ladder["peak"] = 1230
	p.ladder["games"] = 20
	var credits := p.balance("credits")
	var paid := FcDynastyLadder.roll_season(p, "new_season")
	assert_eq(paid, 900, "platinum starts at 1150, so a rating of 1200 pays platinum season credits")
	assert_eq(p.balance("credits"), credits + 900)
	assert_eq(p.ladder["rating"], 1100, "halfway back to 1000")
	assert_eq(p.ladder["season_id"], "new_season")
	assert_eq(p.ladder["history"][0]["tier"], "platinum")
	assert_eq(p.ladder["history"][0]["peak"], 1230)
	assert_eq(FcDynastyLadder.roll_season(p, "new_season"), 0, "the same season is not rolled twice")


func test_the_view_lists_the_top_five_and_the_user_when_below() -> void:
	var p := env.profile()
	p.ladder["rating"] = 0
	var v := FcDynastyLadder.view(p)
	assert_eq(v["rank"], 100)
	assert_eq(v["standings"].size(), 6)
	assert_true(bool(v["standings"][5]["you"]))
	assert_eq(v["tier"], "Bronze")
	p.ladder["rating"] = 100000
	var top := FcDynastyLadder.view(p)
	assert_eq(top["rank"], 1)
	assert_true(bool(top["standings"][0]["you"]))
	assert_eq(top["next_tier"], "")


func test_the_ladder_saves_and_an_older_profile_migrates_to_the_starting_ladder() -> void:
	var p := env.profile()
	p.ladder["rating"] = 1111
	p.ladder["reached"] = ["bronze", "silver"]
	var again := FcDynastyProfile.from_dict(FcChecks.parse_json(JSON.stringify(p.to_dict())))
	assert_eq(again.ladder["rating"], 1111)
	assert_eq(again.ladder["reached"], ["bronze", "silver"])
	assert_eq(FcVersion.DYNASTY_DATA_VERSION, 4)
	var step := FcDynastyMigrator.new().migrate({"team_name": "X"}, 2, 3)
	assert_true(step["ok"])
	assert_eq(step["payload"]["ladder"]["rating"], 1000)
	var kept := FcDynastyMigrator.new().migrate({"ladder": {"rating": 1300}}, 2, 3)
	assert_eq(kept["payload"]["ladder"]["rating"], 1300, "an existing ladder is not wiped")
	var old := FcDynastyProfile.from_dict({"team_name": "Old"})
	assert_eq(old.ladder["rating"], 1000, "a profile with no ladder section starts fresh")


func test_a_tournament_placement_moves_the_rating_by_the_data_bonus() -> void:
	var p := env.profile()
	p.ladder["season_id"] = env.catalog.active_season_id()
	p.ladder["rating"] = 1000
	assert_eq(FcDynastyLadder.on_tournament(p, env.catalog, "champion")["delta"], 30)
	assert_eq(FcDynastyLadder.on_tournament(p, env.catalog, "finalist")["delta"], 15)
	assert_eq(FcDynastyLadder.on_tournament(p, env.catalog, "quarterfinal")["delta"], 0)
	assert_eq(p.ladder["rating"], 1045)
	assert_eq(p.ladder["peak"], 1045)
	assert_eq(p.ladder["games"], 0, "a tournament is not a ranked quick game")
	p.ladder["rating"] = 1045   # semifinal is +8: 1053, gold starts at 1050
	p.ladder["reached"] = ["bronze", "silver"]
	var credits := p.balance("credits")
	var up := FcDynastyLadder.on_tournament(p, env.catalog, "semifinal")
	assert_true(bool(up["tier_up"]) and int(up["reward"]) == 300, "the bonus can carry the rating into gold")
	assert_eq(p.balance("credits"), credits + 300)


func test_finishing_a_real_tournament_run_changes_the_ladder_and_records_it() -> void:
	assert_true(env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(env.session.profile, env.catalog, "test_cup")).ok)
	var finished := false
	var last: FcDynastyResult = null
	for i in 5:
		last = env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(env.session.profile, env.catalog))
		assert_true(last.ok, last.message)
		if bool(last.data["finished"]):
			finished = true
			break
	assert_true(finished)
	var bonus := int(FcDynastyLadder.rules()["tournament_bonus"].get(str(last.data["run"]["placement"]), 0))
	assert_eq(int(last.data["ladder"]["delta"]), bonus)
	var history: Array = env.profile().tournament["history"]
	assert_eq(history[history.size() - 1]["ladder_delta"], bonus)
